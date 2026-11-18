#!/bin/sh
# Optional, one-time root setup for the CPU boost toggle. Run: sh boost/install.sh [--remove]
# Installs a root-owned helper, a polkit action (no password for the active local
# session) and a boot unit that re-applies the saved state.
set -eu
d=$(cd "$(dirname "$0")" && pwd)
if [ "${1:-}" = "--remove" ]; then
    sudo systemctl disable omarchy-asus-boost.service 2>/dev/null || true
    sudo rm -f /usr/local/bin/omarchy-asus-boost \
        /usr/share/polkit-1/actions/io.github.moneytosms.asus.cpu-boost.policy \
        /etc/systemd/system/omarchy-asus-boost.service \
        /var/lib/omarchy-asus/cpu-boost
    sudo rmdir /var/lib/omarchy-asus 2>/dev/null || true
    sudo systemctl daemon-reload
    echo "removed (current boost state left as is)"; exit 0
fi
sudo install -m755 -o root -g root "$d/omarchy-asus-boost" /usr/local/bin/omarchy-asus-boost
sudo install -m644 -o root -g root "$d/io.github.moneytosms.asus.cpu-boost.policy" /usr/share/polkit-1/actions/
sudo install -m644 -o root -g root "$d/omarchy-asus-boost.service" /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable omarchy-asus-boost.service
echo "installed; toggle it from the ASUS panel > Advanced > CPU Boost"
