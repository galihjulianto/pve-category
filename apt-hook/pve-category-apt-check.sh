#!/bin/sh
# Bridges apt's DPkg::Pre-Install-Pkgs and DPkg::Post-Invoke hooks so that
# 'pve-category ensure' runs only when pve-manager was actually part of the
# current dpkg transaction, and only after the new files are unpacked.
#
#   --mark            : read package list from stdin (Pre-Install-Pkgs
#                        format: one "name:arch" per line), and if
#                        pve-manager is among them, drop a flag file.
#   --run-if-marked    : if the flag file exists, remove it and run
#                        'pve-category ensure'. If pve-category itself
#                        isn't installed on this host, this is a no-op.
#
# Never exits non-zero for conditions that are expected/benign, so a
# transaction that has nothing to do with pve-manager, or a host that
# doesn't have pve-category installed, never makes dpkg/apt see a failure.

set -u

FLAG_FILE="/run/pve-category-apt-pending"

find_pvec_bin() {
    for candidate in /usr/local/sbin/pve-category /usr/local/bin/pve-category; do
        if [ -x "$candidate" ]; then
            echo "$candidate"
            return 0
        fi
    done
    return 1
}

case "${1:-}" in
    --mark)
        # Only bother marking if pve-category is even present on this host.
        find_pvec_bin >/dev/null 2>&1 || exit 0
        if grep -q '^pve-manager:' 2>/dev/null; then
            : > "$FLAG_FILE" 2>/dev/null || true
        fi
        exit 0
        ;;
    --run-if-marked)
        if [ -f "$FLAG_FILE" ]; then
            rm -f "$FLAG_FILE" 2>/dev/null || true
            PVEC_BIN="$(find_pvec_bin 2>/dev/null)" || exit 0
            "$PVEC_BIN" ensure || true
        fi
        exit 0
        ;;
    *)
        echo "Usage: $0 --mark | --run-if-marked" >&2
        exit 0
        ;;
esac
