#!/usr/bin/env bash
# Proxmox VE 9: stop the "No valid subscription" pop-up in the web UI.
# Unsupported by Proxmox. Updates to proxmox-widget-toolkit undo it; run the script again.
# Safe to run more than once. Undo with: remove-subscription-popup.sh --undo
set -euo pipefail

f=/usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js
backup=/root/proxmoxlib.js.orig

[ "$(id -u)" = 0 ] || { echo "Run as root." >&2; exit 1; }

if [ "${1:-}" = "--undo" ]; then
  cp "$backup" "$f"
  systemctl restart pveproxy
  echo "Restored $f from $backup"
  exit 0
fi

# Back up the file while it is unpatched (also refreshes the backup after a package update)
grep -q 'false /\* kit \*/' "$f" || cp "$f" "$backup"

# Put "false /* kit */ && " in front of each subscription status check.
# The look-behind skips checks that are already patched; \b anchors the match at the start of the variable name.
perl -i -pe "s{(?<!false /\* kit \*/ && )\b(\w+\.data\.status\.toLowerCase\(\) !== 'active')}{false /* kit */ && \$1}g" "$f"

n=$(grep -c 'false /\* kit \*/ && ' "$f" || true)
if [ "$n" -eq 0 ]; then
  echo "No subscription check found. Proxmox may have changed the file; nothing was patched." >&2
  exit 1
fi

systemctl restart pveproxy
echo "Patched $n subscription check(s). Hard-refresh the browser (Ctrl+Shift+R)."
