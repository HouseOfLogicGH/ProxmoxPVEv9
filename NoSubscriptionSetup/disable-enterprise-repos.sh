#!/usr/bin/env bash
# Proxmox VE 9: disable the enterprise repositories and add the no-subscription repository.
# Safe to run more than once.
set -euo pipefail

d=/etc/apt/sources.list.d

[ "$(id -u)" = 0 ] || { echo "Run as root." >&2; exit 1; }
grep -q '^VERSION_CODENAME=trixie' /etc/os-release || { echo "This script is for Proxmox VE 9 (Debian trixie)." >&2; exit 1; }

# deb822 .sources files: add "Enabled: no" to each enterprise file
for f in "$d"/*.sources; do
  [ -e "$f" ] || continue
  grep -q 'enterprise\.proxmox\.com' "$f" || continue
  # ponytail: one repo block per file, as Proxmox creates them; edit multi-block files by hand
  if [ "$(grep -c '^Types:' "$f")" -gt 1 ]; then
    echo "Skipped $f: it has more than one block. Add 'Enabled: no' to the enterprise block by hand." >&2
    continue
  fi
  if grep -q '^Enabled:' "$f"; then
    sed -i 's/^Enabled:.*/Enabled: no/' "$f"
  else
    echo 'Enabled: no' >> "$f"
  fi
  echo "Disabled $f"
done

# Old one-line .list files left over from Proxmox 8: comment out enterprise lines
for f in "$d"/*.list; do
  [ -e "$f" ] || continue
  if grep -q '^deb[[:space:]]\+https://enterprise\.proxmox\.com' "$f"; then
    sed -i 's|^\(deb[[:space:]]\+https://enterprise\.proxmox\.com\)|# \1|' "$f"
    echo "Commented out enterprise lines in $f"
  fi
done

# Add the no-subscription repository unless it is already configured
if grep -qs '^Components:.*pve-no-subscription' "$d"/*.sources || grep -qs '^deb .*pve-no-subscription' "$d"/*.list /etc/apt/sources.list; then
  echo "No-subscription repository already configured"
else
  cat > "$d/proxmox.sources" <<'EOF'
Types: deb
URIs: http://download.proxmox.com/debian/pve
Suites: trixie
Components: pve-no-subscription
Signed-By: /usr/share/keyrings/proxmox-archive-keyring.gpg
EOF
  echo "Created $d/proxmox.sources"
fi

apt-get update
