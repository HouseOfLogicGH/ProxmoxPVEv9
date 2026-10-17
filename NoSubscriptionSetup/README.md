# Proxmox VE 9 without a subscription

A fresh Proxmox VE 9 install uses the **enterprise** repositories, which need a paid subscription. Without one, every update check fails:

```
E: Failed to fetch https://enterprise.proxmox.com/debian/pve/dists/trixie/InRelease  401  Unauthorized
E: The repository 'https://enterprise.proxmox.com/debian/pve trixie InRelease' is not signed.
```

`apt-get update` exits with code 100 and the host gets no Proxmox updates. This folder fixes that, and optionally removes the "No valid subscription" pop-up at login. The two are separate: fixing the repositories does not remove the pop-up.

Tested on Proxmox VE 9.2.

## What changed from Proxmox VE 8

Proxmox VE 9 is based on Debian 13 (trixie), which uses the deb822 format for repository files.

| | Proxmox VE 8 (Debian 12) | Proxmox VE 9 (Debian 13) |
|---|---|---|
| Enterprise repo file | `pve-enterprise.list` | `pve-enterprise.sources` |
| Format | one `deb ...` line | a block of `Types:`, `URIs:`, `Suites:`, `Components:`, `Signed-By:` |
| How to disable | put `#` in front of the line | add `Enabled: no` to the block |

A `#` only comments out one line of a block, so the Proxmox 8 method no longer works.

**Hosts upgraded from 8 to 9:** the upgrade can leave your old, disabled `pve-enterprise.list` as `pve-enterprise.list.bak` and create a new, **enabled** `pve-enterprise.sources`. The enterprise repo you disabled on 8 comes back enabled on 9. The script below handles this.

## Part 1: repositories

A fresh install has three files in `/etc/apt/sources.list.d/`:

- `debian.sources`: Debian's own repositories. Leave it alone.
- `pve-enterprise.sources`: the Proxmox enterprise repository. Disable it.
- `ceph.sources`: the Ceph enterprise repository. Disable it too, even if you don't use Ceph.

There is no no-subscription file to edit. You **create** `proxmox.sources`.

### Option A: web UI

1. Select the node, then **Updates → Repositories**.
2. Click **Add**, choose **No-Subscription**, click **Add**.
3. Select the `enterprise.proxmox.com` entries (PVE and Ceph) and click **Disable**.
4. Go to **Updates** and click **Refresh**.

### Option B: script

Read the script first, then run it as root on the host:

```bash
wget https://raw.githubusercontent.com/HouseOfLogicGH/ProxmoxPVEv9/main/NoSubscriptionSetup/disable-enterprise-repos.sh
bash disable-enterprise-repos.sh
```

[`disable-enterprise-repos.sh`](disable-enterprise-repos.sh):

- adds `Enabled: no` to every `.sources` file that points at `enterprise.proxmox.com`
- comments out enterprise lines in any leftover `.list` files from Proxmox 8
- creates `proxmox.sources` with the no-subscription repository, unless it is already configured
- runs `apt-get update`

It is safe to run more than once.

### Option C: by hand

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

apt-get update; echo "exit=$?"   # expect exit=0
```

Use `>` (create) for `proxmox.sources`, not `>>`: appending twice gives a "configured multiple times" warning.

### Then update

```bash
apt update && apt full-upgrade
```

Reboot if a new kernel was installed. Updates stay within `trixie`; moving to the next major version needs the suite changed by hand.

**Using Ceph?** Instead of disabling `ceph.sources`, change its `URIs:` to `http://download.proxmox.com/debian/ceph-squid` and `Components:` to `no-subscription`.

**Buying a subscription later?** Delete the `Enabled: no` line from `pve-enterprise.sources`.

## Part 2: the subscription pop-up (optional)

The pop-up is harmless: it doesn't block updates or features. Removing it is **not supported by Proxmox**, and any update to the `proxmox-widget-toolkit` package brings it back.

### How it works

At login, the web UI's JavaScript (`/usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js`) asks the API for the node's subscription status and shows the pop-up if it isn't `active`:

```js
if (
    res === null ||
    res === undefined ||
    !res ||
    res.data.status.toLowerCase() !== 'active'
) {
    Ext.Msg.show({
        title: gettext('No valid subscription'),
```

The fix puts `false /* kit */ && ` in front of the status comparison:

```js
    !res ||
    false /* kit */ && res.data.status.toLowerCase() !== 'active'
) {
```

`false && anything` is always false, so the comparison can never trigger the pop-up. The `/* kit */` comment marks the line as patched, so running the fix again changes nothing.

On Proxmox VE 9.2 the same comparison appears **twice**. The second one is on the Repositories page, which will then treat the node as subscribed and change its warnings accordingly.

### Option A: script

```bash
wget https://raw.githubusercontent.com/HouseOfLogicGH/ProxmoxPVEv9/main/NoSubscriptionSetup/remove-subscription-popup.sh
bash remove-subscription-popup.sh
```

Then hard-refresh the browser (Ctrl+Shift+R). After a `proxmox-widget-toolkit` update, run it again.

[`remove-subscription-popup.sh`](remove-subscription-popup.sh):

- saves the unpatched file to `/root/proxmoxlib.js.orig`
- patches every subscription check
- stops with an error if it finds none (Proxmox may have changed the file)
- restarts `pveproxy`

Undo with `bash remove-subscription-popup.sh --undo`.

### Option B: by hand

```bash
f=/usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js
cp -n "$f" /root/proxmoxlib.js.orig
set +H
perl -i -pe "s{(?<!false /\* kit \*/ && )\b(\w+\.data\.status\.toLowerCase\(\) !== 'active')}{false /* kit */ && \$1}g" "$f"
grep -c 'false /\* kit \*/ && ' "$f"    # expect 2
systemctl restart pveproxy
```

`set +H` turns off bash history expansion. Without it, an interactive shell reads `!false` in the command as a history reference and fails with `-bash: !false: event not found`.

The parts of the pattern:

- `(?<!false /\* kit \*/ && )` skips comparisons that are already patched.
- `\b` makes the match start at the beginning of the variable name. Without it, a second run matches mid-word and corrupts the file (`rfalse … es.data…`), which breaks the web UI.

### Check and undo

- `diff /root/proxmoxlib.js.orig "$f"` should show only the two changed lines.
- To undo: `cp /root/proxmoxlib.js.orig "$f" && systemctl restart pveproxy`
- If the web UI breaks for any reason, reinstall the package: `apt-get install --reinstall proxmox-widget-toolkit`
