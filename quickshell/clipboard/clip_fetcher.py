#!/usr/bin/env python3
import subprocess
import json
import os
import sys
import fcntl
import time
import resource
import tempfile
import hashlib

# Preview/search work is bounded independently of the original clipboard value.
# Copy still decodes the untouched original through clipboard-action.sh.
MAX_DECODE_BYTES = 16 * 1024 * 1024
MAX_PREVIEW_PIXELS = 12_000_000
MAX_TEXT_PREVIEW_BYTES = 64 * 1024

def decoder_limits():
    resource.setrlimit(resource.RLIMIT_FSIZE, (MAX_DECODE_BYTES, MAX_DECODE_BYTES))
    resource.setrlimit(resource.RLIMIT_CORE, (0, 0))

def decode_entry(iid, output, timeout=8):
    subprocess.run(["cliphist", "decode", iid], stdout=output,
                   stderr=subprocess.DEVNULL, timeout=timeout, check=True,
                   preexec_fn=decoder_limits)

def create_preview(source, destination):
    from PIL import Image
    with Image.open(source) as preview:
        if preview.width * preview.height > MAX_PREVIEW_PIXELS:
            raise ValueError("Clipboard preview exceeds pixel budget")
        preview.thumbnail((1280, 1280))
        preview.convert("RGBA").save(destination, "PNG")

def valid_cached_preview(path):
    from PIL import Image
    try:
        if not 0 < os.path.getsize(path) <= MAX_DECODE_BYTES:
            return False
        with Image.open(path) as cached:
            if cached.width > 1280 or cached.height > 1280 or cached.format != "PNG":
                return False
            cached.verify()
        return True
    except (OSError, ValueError, Image.DecompressionBombError):
        return False

def cleanup_cache(all_lines, cache_dir):
    valid_ids = set()
    # Keep top 100 recent IDs to prevent infinite cache bloat
    for line in all_lines[:100]:
        if '\t' in line:
            valid_ids.add(line.split('\t', 1)[0])
            
    try:
        for f in os.listdir(cache_dir):
            if f.endswith('.png'):
                iid = f.replace('.png', '')
                if iid not in valid_ids:
                    try:
                        os.remove(os.path.join(cache_dir, f))
                    except Exception:
                        pass
    except Exception:
        pass

def print_text_preview(iid):
    if not iid.isdigit():
        raise ValueError("Invalid clipboard ID")
    with tempfile.TemporaryFile() as decoded:
        try:
            decode_entry(iid, decoded)
        except (subprocess.SubprocessError, OSError):
            if decoded.tell() <= MAX_TEXT_PREVIEW_BYTES:
                print("Preview unavailable; the original entry can still be copied.")
                return
        decoded.seek(0)
        content = decoded.read(MAX_TEXT_PREVIEW_BYTES + 1)
    truncated = len(content) > MAX_TEXT_PREVIEW_BYTES
    print(content[:MAX_TEXT_PREVIEW_BYTES].decode("utf-8", errors="replace"), end="")
    if truncated:
        print("\n\n[Preview truncated; copying keeps the complete original.]")

def get_cliphist():
    # Implement pagination arguments
    try:
        offset = int(sys.argv[1]) if len(sys.argv) > 1 else 0
        limit = int(sys.argv[2]) if len(sys.argv) > 2 else 12
    except (ValueError, IndexError):
        offset, limit = 0, 12

    # Use dynamically provided cache dir from QML or fallback securely
    default_cache = os.path.join(
        os.environ.get("MINIMAL_CACHE") or os.path.join(os.environ.get("XDG_CACHE_HOME") or os.path.expanduser("~/.cache"), "minimal"),
        "clipboard"
    )
    cache_dir = sys.argv[3] if len(sys.argv) > 3 else os.environ.get("QS_CACHE_CLIPBOARD", default_cache)
    os.makedirs(cache_dir, mode=0o700, exist_ok=True)
    os.chmod(cache_dir, 0o700)
    lock = open(os.path.join(cache_dir, ".action.lock"), "a")
    try:
        fcntl.flock(lock, fcntl.LOCK_EX)
        try:
            # Fetch the entire list quickly.
            # Bound database contention and subprocess failures so the UI can recover.
            result = subprocess.run(
                ["cliphist", "list"], capture_output=True, text=True, timeout=8
            )
            if result.returncode != 0:
                # A failed list must not look like "no more entries", which would
                # permanently hide pagination.
                print("null")
                return

            stdout = result.stdout.strip()
            all_lines = stdout.split('\n') if stdout else []

            query = sys.argv[4].casefold() if len(sys.argv) > 4 else ""
            if query:
                head = all_lines[0].split('\t', 1)[0] if all_lines else ""
                tail = all_lines[-1].split('\t', 1)[0] if all_lines else ""
                fingerprint = f"{len(all_lines)}:{len(stdout)}:{head}:{tail}"
                search_path = os.path.join(cache_dir, '.search.json')
                try:
                    with open(search_path) as stream:
                        saved = json.load(stream)
                except (OSError, ValueError):
                    saved = {}
                if saved.get('fingerprint') == fingerprint and saved.get('query') == query:
                    ids = set(saved['ids'])
                    matching = [line for line in all_lines if line.split('\t', 1)[0] in ids]
                else:
                    matching = []
                    deadline = time.monotonic() + 20
                    for line in all_lines:
                        parts = line.split('\t', 1)
                        if len(parts) != 2 or not parts[0].isdigit():
                            continue
                        if "[[ binary data" in parts[1]:
                            if query in parts[1].casefold(): matching.append(line)
                            continue
                        if time.monotonic() >= deadline:
                            raise TimeoutError("Clipboard search timed out; narrow the query")
                        with tempfile.TemporaryFile() as decoded:
                            decode_entry(parts[0], decoded, min(8, max(.1, deadline-time.monotonic())))
                            decoded.seek(0)
                            content = decoded.read(MAX_DECODE_BYTES).decode("utf-8", errors="replace")
                        if query in content.casefold():
                            matching.append(line)
                    search_tmp = search_path + ".tmp"
                    with open(search_tmp, 'w', opener=lambda path, flags: os.open(path, flags, 0o600)) as stream:
                        json.dump(dict(fingerprint=fingerprint, query=query,
                                       ids=[line.split('\t', 1)[0] for line in matching]), stream)
                    os.replace(search_tmp, search_path)
                all_lines = matching

            # Slice only the requested chunk
            lines = all_lines[offset:offset+limit]

            # Serialize cleanup with decoding and mutations; never race a wipe.
            if offset == 0 and not query:
                cleanup_cache(all_lines, cache_dir)

        except subprocess.TimeoutExpired:
            print("null")
            return
        except Exception:
            print("null")
            return

        items = []
        for line in lines:
            if not line: continue
            parts = line.split('\t', 1)
            if len(parts) != 2: continue
            
            iid, content = parts[0], parts[1]
            if not iid.isdigit(): continue
            item_type = "text"
            display_content = content.strip()

            # Detect images in cliphist output
            if "[[ binary data" in content:
                item_type = "image"
                img_path = os.path.join(cache_dir, f"{iid}.png")
                
                # CACHING: Only decode the specific item if it doesn't already exist
                if not valid_cached_preview(img_path):
                    try:
                        with open(img_path + ".tmp", "wb") as f:
                            decode_entry(iid, f)
                        # Decode into a temp file first: a timeout or a crash
                        # previously left a truncated .png behind, and the next open
                        # treated the corrupt file as a valid cache hit.
                        if os.path.getsize(img_path + ".tmp") == 0:
                            raise ValueError("Empty clipboard image")
                        create_preview(img_path + ".tmp", img_path + ".preview")
                        os.replace(img_path + ".preview", img_path)
                        os.remove(img_path + ".tmp")
                    except Exception:
                        for invalid in (img_path + ".tmp", img_path + ".preview", img_path):
                            try:
                                os.remove(invalid)
                            except OSError:
                                pass
                        # Fall back to the textual marker so the row still renders.
                        display_content = "[image unavailable]"
                        item_type = "text"
                if item_type == "image" and os.path.exists(img_path):
                    display_content = img_path

            items.append({
                "id": iid,
                "content": display_content,
                "type": item_type
            })

        print(json.dumps(items))
    finally:
        lock.close()

if __name__ == "__main__":
    if len(sys.argv) == 3 and sys.argv[1] == "--text":
        print_text_preview(sys.argv[2])
    else:
        get_cliphist()
