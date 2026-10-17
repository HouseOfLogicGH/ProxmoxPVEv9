# Proxmox VE 9 without a subscription

Without a subscription, `apt-get update` fails with `401 Unauthorized` (exit code 100) because a fresh install uses the enterprise repositories. These scripts switch to the no-subscription repository and optionally remove the login pop-up. Run them as root on the host. Tested on Proxmox VE 9.2.

## 1. Repositories

```bash
wget https://raw.githubusercontent.com/HouseOfLogicGH/ProxmoxPVEv9/main/NoSubscriptionSetup/disable-enterprise-repos.sh
bash disable-enterprise-repos.sh
```

Or by hand:

```bash
cat > /etc/apt/sources.list.d/proxmox.sources <<'EOF'
Types: deb
URIs: http://download.proxmox.com/debian/pve
Suites: trixie
Components: pve-no-subscription
Signed-By: /usr/share/keyrings/proxmox-archive-keyring.gpg
EOF
echo 'Enabled: no' >> /etc/apt/sources.list.d/pve-enterprise.sources
echo 'Enabled: no' >> /etc/apt/sources.list.d/ceph.sources
apt-get update
```

In the web UI: **Updates → Repositories → Add → No-Subscription**, then disable the enterprise entries.

## 2. Subscription pop-up (optional, unsupported)

```bash
wget https://raw.githubusercontent.com/HouseOfLogicGH/ProxmoxPVEv9/main/NoSubscriptionSetup/remove-subscription-popup.sh
bash remove-subscription-popup.sh
```

Hard-refresh the browser (Ctrl+Shift+R). Run it again after `proxmox-widget-toolkit` updates. Undo with `bash remove-subscription-popup.sh --undo`.
