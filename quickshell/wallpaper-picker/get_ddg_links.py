#!/usr/bin/env python3
import sys, json, time, re, os
import urllib.request, urllib.parse, http.cookiejar

# Dynamic cache and runtime paths
_CACHE_ROOT = os.environ.get("MINIMAL_CACHE") or os.path.join(os.environ.get("XDG_CACHE_HOME") or os.path.expanduser("~/.cache"), "minimal")
_RUN_ROOT = os.environ.get("MINIMAL_RUNTIME") or os.environ.get("XDG_RUNTIME_DIR") or os.path.join(_CACHE_ROOT, "run")

QS_RUN_WP = os.environ.get("QS_RUN_WALLPAPER_PICKER", os.path.join(_RUN_ROOT, "wallpaper-picker"))
QS_LOG_DIR = os.environ.get("QS_LOG_DIR", os.path.join(QS_RUN_WP, "logs"))

LOG_FILE = os.path.join(QS_LOG_DIR, "ddg_python_scraper.log")
CONTROL_FILE = os.path.join(QS_RUN_WP, "ddg_search_control")

try:
    os.makedirs(QS_LOG_DIR, exist_ok=True)
    os.makedirs(QS_RUN_WP, exist_ok=True)
except Exception:
    pass

def log(msg):
    try:
        with open(LOG_FILE, "a") as f:
            f.write(f"{time.strftime('%H:%M:%S')} - {msg}\n")
    except Exception:
        pass

def get_state():
    try:
        with open(CONTROL_FILE, "r") as f:
            return f.read().strip()
    except Exception:
        return "run"

def read_bounded(response, limit=4 * 1024 * 1024):
    with response:
        data = response.read(limit + 1)
    if len(data) > limit:
        raise ValueError("Search response exceeds size limit")
    return data

def main():
    log("=== NEW SEARCH STARTING (Safe Search: OFF) ===")
    if len(sys.argv) < 2: 
        log("ERROR: No query provided.")
        return
        
    query = sys.argv[1].strip() + " wallpaper"
    log(f"Query: '{query}'")
    
    cj = http.cookiejar.CookieJar()
    opener = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(cj))
    urllib.request.install_opener(opener)

    headers = {
        "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
        "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8",
        "Accept-Language": "en-US,en;q=0.5",
        "Referer": "https://duckduckgo.com/"
    }

    search_url = f"https://duckduckgo.com/?q={urllib.parse.quote(query)}&iar=images&iax=images&ia=images&kp=-1"
    vqd = None

    log(f"Fetching VQD token from: {search_url}")
    for i in range(3):
        try:
            req = urllib.request.Request(search_url, headers=headers)
            html = read_bounded(urllib.request.urlopen(req, timeout=10)).decode("utf-8")
            match = re.search(r'vqd=([0-9a-zA-Z_-]+)', html) or re.search(r'vqd[\'\"]?\s*:\s*[\'\"]?([0-9a-zA-Z_-]+)', html)
            
            if match: 
                vqd = match.group(1)
                log(f"Success! Found VQD token: {vqd}")
                break
            else:
                log(f"Attempt {i+1}: No VQD found in HTML.")
        except Exception as e: 
            log(f"Attempt {i+1} Network Error: {str(e)}")
            time.sleep(1)

    if not vqd: 
        log("CRITICAL ERROR: Failed to get VQD token. Exiting.")
        return

    headers["Referer"] = search_url
    headers["Accept"] = "application/json, text/javascript, */*; q=0.01"

    next_url = None
    links_found = 0
    
    for page in range(5): 
        state = get_state()
        if state == "stop":
            log("Stop signal detected. Exiting cleanly.")
            break
            
        while state == "pause":
            time.sleep(1)
            state = get_state()

        log(f"Fetching JSON page {page + 1}...")

        params = {
            "l": "us-en",
            "o": "json",
            "q": query,
            "vqd": vqd,
            "f": ",,,",
            "p": "-1",
            "ex": "-1"
        }

        if next_url:
            url = "https://duckduckgo.com" + next_url
            if "p=-1" not in url: url += "&p=-1"
            if "vqd=" not in url: url += f"&vqd={vqd}"
        else:
            url = "https://duckduckgo.com/i.js?" + urllib.parse.urlencode(params)

        try:
            req = urllib.request.Request(url, headers=headers)
            response = urllib.request.urlopen(req, timeout=10)
            data = json.loads(read_bounded(response).decode("utf-8"))
            results = data.get("results", [])
            log(f"Successfully parsed JSON. Found {len(results)} raw image results.")
            
            for res in results:
                try:
                    width = int(res.get("width") or 0)
                    height = int(res.get("height") or 0)
                except (TypeError, ValueError):
                    continue
                if width >= 1920 and height >= 1080:
                    t, i = res.get("thumbnail"), res.get("image")
                    if (t and i and all(urllib.parse.urlparse(u).scheme in ('http', 'https')
                                       and not any(c in u for c in '\n\r|') for u in (t, i))):
                        try:
                            sys.stdout.write(f"{t}|{i}\n")
                            sys.stdout.flush()
                            links_found += 1
                        except BrokenPipeError:
                            log("Broken pipe detected. Bash script stopped listening. Exiting.")
                            os._exit(0) 
            
            next_url = data.get("next")
            if not next_url: 
                log("No 'next' URL provided by DDG.")
                break
                
        except BrokenPipeError:
            os._exit(0)
        except Exception as e: 
            log(f"Error fetching page {page + 1}: {str(e)}. Assuming session expired or blocked.")
            break
            
    log(f"=== SEARCH COMPLETE. Total FHD links: {links_found} ===")

if __name__ == "__main__": 
    try:
        os.remove(LOG_FILE)
    except Exception:
        pass
    
    try:
        main()
        sys.stdout.flush()
    except BrokenPipeError:
        os._exit(0)
    except KeyboardInterrupt:
        os._exit(1)
    except Exception as e: 
        log(f"FATAL: {str(e)}")
        os._exit(1)
