#!/usr/bin/env bash
#
# Build firmware locally in ZMK's Docker image, mirroring the GitHub workflow.
#
#   ./build.sh                 build every target in build.yaml
#   ./build.sh corne_left      build targets whose name contains "corne_left"
#   ./build.sh --update        re-run `west update` before building
#   ./build.sh --pristine      wipe build dirs and build from scratch
#
# Firmware lands in ./firmware/. ZMK/Zephyr sources and build dirs are cached
# in $ZMK_CACHE_DIR (default ~/.cache/zmk-config-corne) between runs.

set -euo pipefail

IMAGE="${ZMK_IMAGE:-zmkfirmware/zmk-build-arm:stable}"
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CACHE_DIR="${ZMK_CACHE_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/zmk-config-corne}"

update=0
pristine=0
filter=""
for arg in "$@"; do
    case "$arg" in
        --update) update=1 ;;
        --pristine) pristine=1 ;;
        -h|--help) sed -n '3,11p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        -*) echo "unknown option: $arg" >&2; exit 1 ;;
        *) filter="$arg" ;;
    esac
done

mkdir -p "$CACHE_DIR" "$REPO_DIR/firmware"

docker run --rm -t \
    --user "$(id -u):$(id -g)" \
    -e HOME=/tmp \
    -e UPDATE="$update" \
    -e PRISTINE="$pristine" \
    -e FILTER="$filter" \
    -v "$CACHE_DIR:/workspace:z" \
    -v "$REPO_DIR/config:/workspace/config:z" \
    -v "$REPO_DIR:/zmk-config:z" \
    -w /workspace \
    "$IMAGE" \
    bash -euo pipefail -c '
        manifest_hash="$(sha256sum config/west.yml | cut -d" " -f1)"
        if [ ! -d .west ]; then
            west init -l config
            UPDATE=1
        fi
        if [ "$UPDATE" = 1 ] || [ "$(cat .west-manifest-hash 2>/dev/null)" != "$manifest_hash" ]; then
            west update --fetch-opt=--filter=tree:0
            echo "$manifest_hash" > .west-manifest-hash
        fi
        west zephyr-export >/dev/null

        # Expand build.yaml into one "name|board|shield|snippet|cmake-args" line per target.
        targets="$(python3 - <<EOF
import itertools, yaml
cfg = yaml.safe_load(open("/zmk-config/build.yaml")) or {}
def as_list(v):
    return v if isinstance(v, list) else ([v] if v else [])
entries = [{"board": b, "shield": s}
           for b, s in itertools.product(as_list(cfg.get("board")), as_list(cfg.get("shield")) or [None])]
entries += cfg.get("include") or []
for e in entries:
    board, shield = e["board"], e.get("shield") or ""
    name = e.get("artifact-name") or "-".join(filter(None, [shield.replace(" ", "-"), board, "zmk"]))
    print("|".join([name, board, shield, e.get("snippet") or "", e.get("cmake-args") or ""]))
EOF
)"

        built=0
        while IFS="|" read -r name board shield snippet cmake_args; do
            [ -n "$FILTER" ] && [[ "$name" != *"$FILTER"* ]] && continue
            echo "==> Building $name"
            build_dir="build/$name"
            [ "$PRISTINE" = 1 ] && rm -rf "$build_dir"
            west build -s zmk/app -d "$build_dir" -b "$board" \
                ${snippet:+-S "$snippet"} -- \
                -DZMK_CONFIG=/workspace/config \
                ${shield:+-DSHIELD="$shield"} \
                -DZMK_EXTRA_MODULES=/zmk-config \
                $cmake_args
            for ext in uf2 hex bin; do
                if [ -f "$build_dir/zephyr/zmk.$ext" ]; then
                    cp "$build_dir/zephyr/zmk.$ext" "/zmk-config/firmware/$name.$ext"
                    break
                fi
            done
            built=$((built + 1))
        done <<< "$targets"

        if [ "$built" = 0 ]; then
            echo "no targets matched \"$FILTER\"" >&2
            exit 1
        fi
        echo "==> Built $built target(s) into firmware/"
    '
