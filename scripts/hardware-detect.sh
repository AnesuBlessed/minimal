#!/usr/bin/env bash
# =============================================================================
#  MINIMAL — HARDWARE & GPU AUTO-DETECTION ENGINE
# =============================================================================
#  - Detects Intel, AMD, NVIDIA, and Virtual Machines via /sys/class/drm & lspci
#  - Distinguishes legacy Intel i965 (Haswell / HD 4400 & older) vs modern iHD
#  - Distinguishes NVIDIA proprietary driver vs nouveau
#  - Exports optimal Wayland, VA-API, VDPAU, Vulkan, and compositor flags
#  - Writes results to $MINIMAL_CACHE/hardware.env
# =============================================================================
set -Eeuo pipefail

SCRIPT_DIR="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
# shellcheck source=/dev/null
[[ -f "$SCRIPT_DIR/paths.sh" ]] && source "$SCRIPT_DIR/paths.sh"
MINIMAL_CACHE="${MINIMAL_CACHE:-${XDG_CACHE_HOME:-$HOME/.cache}/minimal}"
ENV_FILE="$MINIMAL_CACHE/hardware.env"

ACTION="write"
for arg in "$@"; do
    case "$arg" in
        --print)
            ACTION="print"
            ;;
        --export)
            ACTION="export"
            ;;
        --help|-h)
            cat <<EOF
Usage: hardware-detect.sh [OPTIONS]

Options:
  --print   Print human-readable hardware detection summary and applied flags
  --export  Output export KEY="VALUE" environment variable lines to stdout
  --help    Show this help message
EOF
            exit 0
            ;;
    esac
done

# Allow mocking via environment variables for deterministic test suites
DRM_DIR="${MINIMAL_SYSFS_DRM_DIR:-/sys/class/drm}"

# -----------------------------------------------------------------------------
# 1. Platform & Virtual Machine Detection
# -----------------------------------------------------------------------------
detect_platform() {
    if [[ -n "${MINIMAL_MOCK_PLATFORM:-}" ]]; then
        echo "$MINIMAL_MOCK_PLATFORM"
        return
    fi

    # Check systemd container/VM detection
    if command -v systemd-detect-virt >/dev/null 2>&1; then
        local virt
        virt=$(systemd-detect-virt 2>/dev/null || true)
        if [[ -n "$virt" && "$virt" != "none" ]]; then
            echo "$virt"
            return
        fi
    fi

    # Check DMI system vendor & product name
    for dmi in /sys/class/dmi/id/sys_vendor /sys/class/dmi/id/product_name; do
        if [[ -r "$dmi" ]]; then
            local val
            val=$(<"$dmi")
            if [[ "$val" =~ (QEMU|KVM|VirtualBox|VMware|Bochs) ]]; then
                echo "$val"
                return
            fi
        fi
    done

    echo "baremetal"
}

PLATFORM=$(detect_platform)

# -----------------------------------------------------------------------------
# 2. GPU Enumeration
# -----------------------------------------------------------------------------
# We check both lspci (if present or mocked) and /sys/class/drm

declare -a DETECTED_GPUS=()
# GPU entry format: PCI_SLOT|VENDOR_HEX|DEVICE_HEX|DRIVER|MODEL_NAME

# Normalize both lspci's short slots and sysfs's domain-qualified PCI slots.
normalize_slot() {
    local slot=${1,,}
    [[ ! $slot =~ ^[0-9a-f]{2}:[0-9a-f]{2}\.[0-9a-f]$ ]] || slot="0000:$slot"
    printf '%s\n' "$slot"
}
card_slot() {
    local card=$1 slot='' key value
    if [[ -r $card/device/uevent ]]; then
        while IFS='=' read -r key value; do
            [[ $key != PCI_SLOT_NAME ]] || slot=$value
        done < "$card/device/uevent"
    fi
    if [[ -z $slot ]]; then
        slot=$(basename "$(readlink -f "$card/device")")
        [[ $slot =~ ^([0-9a-fA-F]{4}:)?[0-9a-fA-F]{2}:[0-9a-fA-F]{2}\.[0-9a-fA-F]$ ]] || slot="drm:${card##*/}"
    fi
    normalize_slot "$slot"
}

get_lspci_output() {
    if [[ -n "${MINIMAL_MOCK_LSPCI:-}" ]]; then
        printf '%s\n' "$MINIMAL_MOCK_LSPCI"
    elif command -v lspci >/dev/null 2>&1; then
        lspci -nn -k 2>/dev/null || true
    fi
}

parse_gpus_from_lspci() {
    local lspci_text
    lspci_text=$(get_lspci_output)
    [[ -n "$lspci_text" ]] || return 0

    local current_slot=""
    local current_vendor=""
    local current_device=""
    local current_driver=""
    local current_model=""
    local in_gpu_block=false

    while IFS= read -r line || [[ -n "$line" ]]; do
        if [[ ! "$line" =~ ^[[:space:]] && "$line" =~ ^(([0-9a-fA-F]{4}:)?[0-9a-fA-F]{2}:[0-9a-fA-F]{2}\.[0-9a-fA-F]) ]]; then
            # New device block
            if $in_gpu_block && [[ -n "$current_vendor" ]]; then
                DETECTED_GPUS+=("$current_slot|$current_vendor|$current_device|$current_driver|$current_model")
            fi
            current_slot=$(normalize_slot "${BASH_REMATCH[1]}")
            current_vendor=""
            current_device=""
            current_driver=""
            current_model=""
            in_gpu_block=false

            if [[ "$line" =~ (VGA compatible controller|3D controller|Display controller) ]]; then
                in_gpu_block=true
                if [[ "$line" =~ \[([0-9a-fA-F]{4}):([0-9a-fA-F]{4})\] ]]; then
                    current_vendor="${BASH_REMATCH[1],,}"
                    current_device="${BASH_REMATCH[2],,}"
                fi
                # Extract description between controller type and PCI ID
                local desc="$line"
                desc="${desc#*: }" # Remove slot + class
                desc="${desc%% \[*\]*}" # Strip bracketed tags at end
                current_model="$desc"
            fi
        elif $in_gpu_block; then
            if [[ "$line" =~ Kernel[[:space:]]driver[[:space:]]in[[:space:]]use:[[:space:]]*([[:alnum:]_-]+) ]]; then
                current_driver="${BASH_REMATCH[1]}"
            fi
        fi
    done <<< "$lspci_text"

    if $in_gpu_block && [[ -n "$current_vendor" ]]; then
        DETECTED_GPUS+=("$current_slot|$current_vendor|$current_device|$current_driver|$current_model")
    fi
}

parse_gpus_from_sysfs() {
    [[ -d "$DRM_DIR" ]] || return 0

    for card_dir in "$DRM_DIR"/card[0-9]*; do
        [[ -d "$card_dir" ]] || continue
        # Verify it's a primary card directory, not a connector like card1-eDP-1
        [[ "$card_dir" =~ /card[0-9]+$ ]] || continue
        [[ -r "$card_dir/device/vendor" && -r "$card_dir/device/device" ]] || continue

        local vendor
        vendor=$(<"$card_dir/device/vendor")
        vendor="${vendor#0x}"
        vendor="${vendor,,}"

        local device
        device=$(<"$card_dir/device/device")
        device="${device#0x}"
        device="${device,,}"

        local driver=""
        if [[ -e "$card_dir/device/driver" ]]; then
            driver=$(basename "$(readlink -f "$card_dir/device/driver" 2>/dev/null || echo "")")
        fi

        local slot
        slot=$(card_slot "$card_dir")
        local already_found=false matches=0
        for entry in "${DETECTED_GPUS[@]}"; do
            IFS='|' read -r e_slot e_vendor e_device e_driver e_model <<< "$entry"
            if [[ $e_slot == "$slot" ]]; then
                already_found=true
                break
            fi
            if [[ $e_vendor == "$vendor" && $e_device == "$device" ]]; then
                matches=$((matches + 1))
            fi
        done
        # Synthetic/non-PCI sysfs may lack a slot. Deduplicate only if unambiguous.
        if [[ $slot == drm:* && $matches == 1 ]]; then already_found=true; fi

        if ! $already_found; then
            local model="DRM GPU ($vendor:$device)"
            DETECTED_GPUS+=("$slot|$vendor|$device|$driver|$model")
        fi
    done
}

# Run discovery
parse_gpus_from_lspci
parse_gpus_from_sysfs

# -----------------------------------------------------------------------------
# 3. Analyze Hardware & Select Drivers
# -----------------------------------------------------------------------------

# Environmental variables map
declare -A ENV_VARS=()

PRIMARY_VENDOR="unknown"
PRIMARY_FAMILY="generic"
PRIMARY_MODEL="Unknown Graphics"
PRIMARY_DRIVER="unknown"
PRIMARY_SUMMARY=""

is_intel_i965_legacy() {
    local device_id="$1"
    local model_str="$2"

    # Normalize lowercase
    device_id="${device_id,,}"
    model_str="${model_str,,}"

    # Name-based checks for Haswell and older Intel graphics
    if [[ "$model_str" =~ (haswell|ivy[ -]?bridge|ivybridge|sandy[ -]?bridge|sandybridge|ironlake|pineview|bay[ -]?trail|valleyview|gma[ -]?|hd graphics [234][0-9]{3}|hd graphics 5000|iris 5100|iris pro 5200|hd graphics p[234][0-9]{3}) ]]; then
        return 0
    fi

    # PCI ID prefix checks for Haswell (04xx, 0axx, 0cxx, 0dxx), Ivy Bridge (015x, 016x),
    # Sandy Bridge (010x, 011x, 012x), Bay Trail (0f3x), Ironlake (004x), GMA (2a4x, 2e0x.. etc.)
    if [[ "$device_id" =~ ^(04|0a|0c|0d|015|016|010|011|012|0f3|004|2a4|2e) ]]; then
        return 0
    fi

    return 1
}

analyze_gpus() {
    if [[ ${#DETECTED_GPUS[@]} -eq 0 ]]; then
        # Fallback when no GPU detected via PCI/DRM (e.g. headless or pure software container)
        if [[ "$PLATFORM" != "baremetal" ]]; then
            PRIMARY_VENDOR="virtual"
            PRIMARY_FAMILY="vm-fallback"
            PRIMARY_MODEL="Virtual Machine / Software Renderer"
            PRIMARY_DRIVER="virtio"
            ENV_VARS["WLR_NO_HARDWARE_CURSORS"]="1"
            ENV_VARS["WLR_RENDERER_ALLOW_SOFTWARE"]="1"
            ENV_VARS["HYPR_VFR"]="true"
            ENV_VARS["HYPR_BLUR"]="false"
            PRIMARY_SUMMARY="Virtual Machine Display Adapter (Software/VirtIO rendering safe mode)"
        else
            PRIMARY_VENDOR="generic"
            PRIMARY_FAMILY="fallback"
            PRIMARY_MODEL="Generic Display Adapter"
            PRIMARY_DRIVER="unknown"
            ENV_VARS["HYPR_VFR"]="true"
            ENV_VARS["HYPR_BLUR"]="false"
            PRIMARY_SUMMARY="Generic display adapter with safe VFR and disabled blur"
        fi
    else
        # Determine primary GPU.
        # Preference:
        # 1. Connected output card in DRM sysfs (matched by PCI slot, then boot_vga/driver/vendor+device)
        # 2. Card marked boot_vga=1 in DRM sysfs when no connector reports connected yet
        # 3. First non-virtual GPU, or primary discrete/integrated
        local chosen_gpu="${DETECTED_GPUS[0]}"
        local selected=0

        # Match the connected card by identity, not vendor (two cards may be identical).
        local conn card_name connected_slot candidate matches c_vendor c_device c_driver
        for conn in "$DRM_DIR"/card*-*/status; do
            [[ -r $conn && $(<"$conn") == connected ]] || continue
            card_name=${conn%/status}; card_name=${card_name##*/}; card_name=${card_name%%-*}
            connected_slot=$(card_slot "$DRM_DIR/$card_name")
            candidate='' matches=0
            for entry in "${DETECTED_GPUS[@]}"; do
                IFS='|' read -r g_slot g_vendor g_device g_driver g_model <<< "$entry"
                if [[ $g_slot == "$connected_slot" ]]; then
                    chosen_gpu=$entry
                    selected=1
                    break 2
                fi
            done
            # Without PCI identity, match by vendor+device (and driver when available).
            [[ $connected_slot == drm:* ]] || continue
            c_vendor=$(cat "$DRM_DIR/$card_name/device/vendor" 2>/dev/null || true)
            c_device=$(cat "$DRM_DIR/$card_name/device/device" 2>/dev/null || true)
            c_driver=""
            if [[ -L "$DRM_DIR/$card_name/device/driver" ]]; then
                c_driver=$(basename "$(readlink -f "$DRM_DIR/$card_name/device/driver")")
            fi
            c_vendor=${c_vendor#0x}; c_vendor=${c_vendor,,}
            c_device=${c_device#0x}; c_device=${c_device,,}
            for entry in "${DETECTED_GPUS[@]}"; do
                IFS='|' read -r g_slot g_vendor g_device g_driver g_model <<< "$entry"
                if [[ $c_vendor == "$g_vendor" && $c_device == "$g_device" ]]; then
                    if [[ -z $c_driver || -z $g_driver || $c_driver == "$g_driver" ]]; then
                        [[ -n $candidate ]] || candidate=$entry
                        matches=$((matches + 1))
                    fi
                fi
            done
            if ((matches >= 1)); then chosen_gpu=$candidate; selected=1; break; fi
        done

        # Fallback: if no connector reported connected yet, prefer the DRM card with boot_vga=1
        if (( ! selected && ${#DETECTED_GPUS[@]} > 1 )); then
            local boot_file boot_card boot_slot
            for boot_file in "$DRM_DIR"/card*/device/boot_vga; do
                [[ -r $boot_file && $(<"$boot_file") == 1 ]] || continue
                boot_card=${boot_file%/device/boot_vga}
                boot_slot=$(card_slot "$boot_card")
                for entry in "${DETECTED_GPUS[@]}"; do
                    IFS='|' read -r g_slot _ <<< "$entry"
                    if [[ $g_slot == "$boot_slot" ]]; then
                        chosen_gpu=$entry
                        break 2
                    fi
                done
            done
        fi

        local slot vendor device driver model
        IFS='|' read -r slot vendor device driver model <<< "$chosen_gpu"
        PRIMARY_DRIVER="$driver"
        PRIMARY_MODEL="$model"

        # Virtual Machine GPU check (VirtIO, VMware SVGA, VirtualBox, QXL, Bochs)
        if [[ "$vendor" =~ ^(1af4|15ad|80ee|1b36|1234)$ || "$driver" =~ (virtio|vmwgfx|vboxvideo|qxl|bochs) || "$model" =~ (Virtio|VMware|VirtualBox|QEMU|Bochs) ]]; then
            PRIMARY_VENDOR="virtual"
            PRIMARY_FAMILY="vm-virtio"
            ENV_VARS["WLR_NO_HARDWARE_CURSORS"]="1"
            ENV_VARS["WLR_RENDERER_ALLOW_SOFTWARE"]="1"
            ENV_VARS["HYPR_VFR"]="true"
            ENV_VARS["HYPR_BLUR"]="false"
            PRIMARY_SUMMARY="Virtual Machine ($model) with safe software/virtio rendering fallbacks"

        # Intel Graphics
        elif [[ "$vendor" == "8086" || "$model" =~ Intel ]]; then
            PRIMARY_VENDOR="intel"
            if is_intel_i965_legacy "$device" "$model"; then
                PRIMARY_FAMILY="haswell"
                ENV_VARS["LIBVA_DRIVER_NAME"]="i965"
                ENV_VARS["HYPR_VFR"]="true"
                ENV_VARS["HYPR_BLUR"]="false"
                PRIMARY_SUMMARY="Intel Legacy Gen 7.5 or older (Haswell / HD 4400) using i965 VA-API driver"
            else
                PRIMARY_FAMILY="broadwell-plus"
                ENV_VARS["LIBVA_DRIVER_NAME"]="iHD"
                ENV_VARS["HYPR_VFR"]="true"
                ENV_VARS["HYPR_BLUR"]="false"
                PRIMARY_SUMMARY="Intel Modern Gen 8+ (Broadwell / Iris / Arc) using iHD VA-API driver"
            fi

        # AMD Graphics
        elif [[ "$vendor" == "1002" || "$model" =~ (AMD|ATI|Radeon) ]]; then
            PRIMARY_VENDOR="amd"
            PRIMARY_FAMILY="radeonsi"
            ENV_VARS["LIBVA_DRIVER_NAME"]="radeonsi"
            ENV_VARS["VDPAU_DRIVER"]="radeonsi"
            ENV_VARS["AMD_VULKAN_ICD"]="RADV"
            ENV_VARS["HYPR_VFR"]="true"
            ENV_VARS["HYPR_BLUR"]="false"
            PRIMARY_SUMMARY="AMD Radeon using radeonsi VA-API / VDPAU driver and Mesa RADV Vulkan provider"

        # NVIDIA Graphics
        elif [[ "$vendor" == "10de" || "$model" =~ NVIDIA ]]; then
            PRIMARY_VENDOR="nvidia"
            # Detect proprietary driver vs nouveau
            local is_proprietary=false
            if [[ "$driver" =~ ^nvidia || -d /sys/module/nvidia || -f /proc/driver/nvidia/version ]]; then
                is_proprietary=true
            fi

            if $is_proprietary; then
                PRIMARY_FAMILY="nvidia-proprietary"
                ENV_VARS["LIBVA_DRIVER_NAME"]="nvidia"
                ENV_VARS["__GLX_VENDOR_LIBRARY_NAME"]="nvidia"
                ENV_VARS["NVD_BACKEND"]="direct"
                ENV_VARS["ELECTRON_OZONE_PLATFORM_HINT"]="auto"
                ENV_VARS["GBM_BACKEND"]="nvidia-drm"
                ENV_VARS["HYPR_VFR"]="true"
                PRIMARY_SUMMARY="NVIDIA Proprietary Driver with direct backend and Ozone Wayland hints"
            else
                PRIMARY_FAMILY="nvidia-nouveau"
                ENV_VARS["LIBVA_DRIVER_NAME"]="nouveau"
                ENV_VARS["VDPAU_DRIVER"]="nouveau"
                ENV_VARS["HYPR_VFR"]="true"
                ENV_VARS["HYPR_BLUR"]="false"
                PRIMARY_SUMMARY="NVIDIA Nouveau Open-Source Driver with Mesa Gallium acceleration"
            fi

        else
            PRIMARY_VENDOR="unknown"
            PRIMARY_FAMILY="generic"
            ENV_VARS["HYPR_VFR"]="true"
            ENV_VARS["HYPR_BLUR"]="false"
            PRIMARY_SUMMARY="Unknown GPU ($model) — applied standard VFR and zero-blur defaults"
        fi
    fi
}

analyze_gpus


# Ensure standard metadata is stored
ENV_VARS["GPU_PLATFORM"]="$PLATFORM"
ENV_VARS["GPU_VENDOR"]="$PRIMARY_VENDOR"
ENV_VARS["GPU_FAMILY"]="$PRIMARY_FAMILY"
ENV_VARS["GPU_MODEL"]="$PRIMARY_MODEL"
ENV_VARS["GPU_DRIVER"]="$PRIMARY_DRIVER"

# -----------------------------------------------------------------------------
# 4. Write Configuration to Cache
# -----------------------------------------------------------------------------
mkdir -p "$MINIMAL_CACHE"

escape_env_val() {
    local val=$1
    val=${val//\\/\\\\}
    val=${val//\"/\\\"}
    val=${val//\$/\\\$}
    val=${val//\`/\\\`}
    printf '%s' "$val"
}

write_cache() {
    local tmp_file
    tmp_file=$(mktemp "$MINIMAL_CACHE/hardware.env.XXXXXXXX")
    trap 'rm -f -- "$tmp_file"' EXIT
    {
        printf '# =============================================================================\n'
        printf '#  MINIMAL — HARDWARE AUTO-DETECTION CACHE\n'
        printf '#  Generated: %s\n' "$(date -u +"%Y-%m-%d %H:%M:%S UTC")"
        printf '#  Platform: %s | GPU: %s (%s)\n' "$PLATFORM" "$PRIMARY_MODEL" "$PRIMARY_FAMILY"
        printf '# =============================================================================\n\n'
        while IFS= read -r k; do
            [[ -n $k ]] || continue
            printf 'export %s="%s"\n' "$k" "$(escape_env_val "${ENV_VARS[$k]}")"
        done < <(printf '%s\n' "${!ENV_VARS[@]}" | sort)
    } > "$tmp_file"
    chmod 0644 "$tmp_file"
    mv -f "$tmp_file" "$ENV_FILE"
    trap - EXIT
}

write_cache

# -----------------------------------------------------------------------------
# 5. Output Handling (--print, --export, or quiet write)
# -----------------------------------------------------------------------------
if [[ "$ACTION" == "export" ]]; then
    while IFS= read -r k; do
        [[ -n $k ]] || continue
        printf 'export %s="%s"\n' "$k" "$(escape_env_val "${ENV_VARS[$k]}")"
    done < <(printf '%s\n' "${!ENV_VARS[@]}" | sort)
elif [[ "$ACTION" == "print" ]]; then
    printf '=============================================================================\n'
    printf '  MINIMAL HARDWARE & GPU AUTO-DETECTION SUMMARY\n'
    printf '=============================================================================\n'
    printf '  Platform       : %s\n' "$PLATFORM"
    printf '  Primary GPU    : %s\n' "$PRIMARY_MODEL"
    printf '  Vendor / Type  : %s (%s)\n' "$PRIMARY_VENDOR" "$PRIMARY_FAMILY"
    printf '  Kernel Driver  : %s\n' "$PRIMARY_DRIVER"
    printf '  Classification : %s\n' "$PRIMARY_SUMMARY"
    printf '\n'
    printf 'Applied Environment & Hyprland Flags:\n'
    while IFS= read -r k; do
        [[ -n $k ]] || continue
        printf '  export %s="%s"\n' "$k" "$(escape_env_val "${ENV_VARS[$k]}")"
    done < <(printf '%s\n' "${!ENV_VARS[@]}" | sort)
    printf '\n'
    printf 'Cached Configuration:\n'
    printf '  File           : %s [updated]\n' "$ENV_FILE"
    printf '=============================================================================\n'
fi

exit 0
