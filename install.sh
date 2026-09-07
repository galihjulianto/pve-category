#!/bin/sh
# pve-category installer
#
# Copies the main script, the apt auto-reinstall hook, and (if missing) an
# example config into place. Does NOT run 'pve-category install' for you --
# you need a real /root/pve-ui-categories.json first (edit the example or
# write your own), then run that step manually.
#
# Usage:
#   ./install.sh            # install everything, including the apt hook
#   ./install.sh --no-hook   # install only pve-category itself, skip the
#                            #   apt Post-Invoke auto-reinstall hook

set -eu

if [ "$(id -u)" -ne 0 ]; then
    echo "This installer must be run as root." >&2
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
WITH_HOOK=1

for arg in "$@"; do
    case "$arg" in
        --no-hook) WITH_HOOK=0 ;;
        *)
            echo "Unknown argument: $arg" >&2
            echo "Usage: $0 [--no-hook]" >&2
            exit 1
            ;;
    esac
done

echo "==> Installing pve-category to /usr/local/sbin/pve-category"
cp "$SCRIPT_DIR/pve-category" /usr/local/sbin/pve-category
chmod 755 /usr/local/sbin/pve-category

if [ "$WITH_HOOK" -eq 1 ]; then
    echo "==> Installing apt auto-reinstall hook"
    cp "$SCRIPT_DIR/apt-hook/pve-category-apt-check.sh" /usr/local/sbin/pve-category-apt-check.sh
    chmod 755 /usr/local/sbin/pve-category-apt-check.sh
    cp "$SCRIPT_DIR/apt-hook/99-pve-category" /etc/apt/apt.conf.d/99-pve-category
    chmod 644 /etc/apt/apt.conf.d/99-pve-category
    echo "    Hook installed: pve-manager upgrades will auto-run 'pve-category ensure'."
else
    echo "==> Skipping apt hook (--no-hook given)."
    echo "    You'll need to manually re-run 'pve-category install' after any"
    echo "    pve-manager package upgrade."
fi

echo
if [ -f /root/pve-ui-categories.json ]; then
    echo "==> Found existing /root/pve-ui-categories.json — leaving it as-is."
else
    echo "==> No /root/pve-ui-categories.json found."
    echo "    An example is provided at: $SCRIPT_DIR/config/pve-ui-categories.example.json"
    echo "    Copy and edit it, e.g.:"
    echo "      cp $SCRIPT_DIR/config/pve-ui-categories.example.json /root/pve-ui-categories.json"
    echo "      \$EDITOR /root/pve-ui-categories.json"
fi

echo
echo "==> Done. Next steps:"
echo "    1. Make sure /root/pve-ui-categories.json reflects your VM/CT layout."
echo "    2. Run: pve-category install"
echo "    3. Run: pve-category status   (to confirm hooks are active)"
