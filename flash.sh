#!/usr/bin/env bash
#
# Flash both halves from the prebuilt firmware in ./firmware/ (does not build).
#
#   ./flash.sh                 settings reset on both halves, then firmware
#   ./flash.sh --no-reset      skip the settings reset, only flash firmware
#
# Plug both halves in and keep them on. For each step the script tells you which
# half to put into the bootloader (double-tap its reset button), waits for the
# NICENANO drive to show up, mounts it, copies the file and waits for the half
# to reboot before moving on.

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FW_DIR="$REPO_DIR/firmware"
LABEL="NICENANO"
DEV_LINK="/dev/disk/by-label/$LABEL"

reset=1
for arg in "$@"; do
    case "$arg" in
        --no-reset) reset=0 ;;
        -h|--help) sed -n '3,11p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "unknown option: $arg" >&2; exit 1 ;;
    esac
done

bold() { printf '\033[1m%s\033[0m\n' "$*"; }
info() { printf '==> %s\n' "$*"; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }

# find exactly one file matching a glob in the firmware dir
find_fw() {
    local matches=("$FW_DIR"/$1)
    [[ -e "${matches[0]}" ]] || die "no firmware matching $1 in $FW_DIR (run ./build.sh first)"
    (( ${#matches[@]} == 1 )) || die "more than one file matches $1: ${matches[*]}"
    printf '%s\n' "${matches[0]}"
}

settings_fw="$(find_fw 'settings_reset-*.uf2')"
left_fw="$(find_fw 'corne_left-*.uf2')"
right_fw="$(find_fw 'corne_right-*.uf2')"

device_present() { [[ -e "$DEV_LINK" ]]; }

# inside a distrobox/toolbox container, mounting has to happen on the host
IN_CONTAINER=0
HOST=()
if [[ -e /run/.containerenv ]]; then
    IN_CONTAINER=1
    command -v distrobox-host-exec >/dev/null || die "running in a container without distrobox-host-exec"
    HOST=(distrobox-host-exec)
fi
host() { "${HOST[@]}" "$@"; }

mountpoint_of() { host findmnt -n -o TARGET --source "$1" 2>/dev/null | head -n1 || true; }

# sets MP to the drive's mount point, and USED_SUDO if we had to mount it ourselves
MP=""
USED_SUDO=0
mount_device() {
    local dev
    USED_SUDO=0
    dev="$(readlink -f "$DEV_LINK")"

    # something may already have mounted it
    for _ in 1 2 3 4 5; do
        MP="$(mountpoint_of "$dev")"
        [[ -n "$MP" ]] && return
        sleep 0.2
    done

    info "mounting $dev"
    host udisksctl mount -b "$dev" >/dev/null || true
    MP="$(mountpoint_of "$dev")"
    [[ -n "$MP" ]] && return

    (( IN_CONTAINER )) && die "could not mount $dev on the host (is udisks2 installed there?)"

    MP="$(mktemp -d "${TMPDIR:-/tmp}/nicenano.XXXXXX")"
    info "mounting $dev with sudo"
    sudo mount -o "uid=$(id -u),gid=$(id -g)" "$dev" "$MP"
    USED_SUDO=1
}

wait_for() {
    local what="$1" check="$2"
    local spin='|/-\' i=0
    while ! $check; do
        printf '\r   waiting for %s %s' "$what" "${spin:i++%4:1}"
        sleep 0.25
    done
    printf '\r\033[K'
}

device_gone() { ! device_present; }

flash() {
    local half="$1" file="$2" step="$3" total="$4"

    if device_present; then
        info "a $LABEL drive is already connected; press reset once on that half (or replug it) to leave the bootloader"
        wait_for "the old drive to disappear" device_gone
    fi

    echo
    bold "[$step/$total] $half half: $(basename "$file")"
    bold "    double-tap the reset button on the $half half"
    wait_for "the $half half's bootloader drive" device_present

    mount_device
    local mp="$MP"
    info "mounted at $mp, copying"
    # the half reboots as soon as the copy lands, so the drive can vanish mid-sync
    host cp "$file" "$mp/" || true
    host sync 2>/dev/null || true

    wait_for "the $half half to reboot" device_gone
    if (( USED_SUDO )); then
        sudo umount -l "$mp" 2>/dev/null || true
        rmdir "$mp" 2>/dev/null || true
    fi
    info "$half half done"
}

bold "plug in both halves and make sure both are switched on."
read -rp "press enter when ready... " _

if (( reset )); then
    flash left "$settings_fw" 1 4
    flash right "$settings_fw" 2 4
    flash left "$left_fw" 3 4
    flash right "$right_fw" 4 4
else
    flash left "$left_fw" 1 2
    flash right "$right_fw" 2 2
fi

echo
bold "all done. the halves should pair with each other within a few seconds."
