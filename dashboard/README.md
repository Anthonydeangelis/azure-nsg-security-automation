# NSG findings dashboard

A small, buildless HTML/CSS/JavaScript page served by the existing private Nginx
VM. It requests the same-origin `/api/findings` endpoint. Nginx forwards that
request to the local Python backend, which uses the VM's managed identity to
call the Azure Function. No Azure tokens or function keys belong in these files.

## 1. Backend prerequisites

The demonstrated web VM is in Azure with a system-assigned identity. That caller
must be allowed by the Function App's Entra authentication configuration; it does
not need an Azure management role on the Function App. Preserve both the VM and
Logic App callers in Terraform, not only in the portal.

The reference [backend](backend/app.py) captures the tested Flask proxy behavior,
with the Function URL and scope moved to environment settings for reuse. This
parameterized reference has been checked locally; it has not replaced the
hardcoded configuration installed during the live VM demonstration.

On Ubuntu, install venv support if needed:

```bash
sudo apt update
sudo apt install python3.12-venv
mkdir -p ~/nsg-dashboard
cd ~/nsg-dashboard
python3 -m venv .venv
source .venv/bin/activate
```

Transfer `backend/app.py` and `backend/requirements.txt` into `~/nsg-dashboard/`.
Then install the requirements and configure the target API:

```bash
python -m pip install -r requirements.txt
export FINDINGS_FUNCTION_URL="https://YOUR_FUNCTION_APP.azurewebsites.net/api/findings"
export FINDINGS_API_SCOPE="api://YOUR_API_APP_CLIENT_ID/.default"
gunicorn --bind 127.0.0.1:8000 --timeout 60 app:app
```

Keep that terminal open. From a second session on the same VM:

```bash
curl -i http://127.0.0.1:8000/api/findings
```

Expect 200 and JSON. The token is not returned to the browser or printed by the
backend. A 502 means the proxy could not retrieve valid upstream results; inspect
backend logs for the upstream status.

## 2. Keep the backend running

Stop the manual Gunicorn with Ctrl+C before starting the service; otherwise both
processes will try to use port 8000. Adapt the user/path placeholders in
[`nsg-dashboard.service.example`](deployment/nsg-dashboard.service.example).
Install the adapted unit as `/etc/systemd/system/nsg-dashboard.service`.

Create `/etc/nsg-dashboard.env` with the two non-secret settings:

```ini
FINDINGS_FUNCTION_URL=https://YOUR_FUNCTION_APP.azurewebsites.net/api/findings
FINDINGS_API_SCOPE=api://YOUR_API_APP_CLIENT_ID/.default
```

Use a root-owned file with mode 0600. Do not add tokens or private keys to it.
Then:

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now nsg-dashboard
sudo systemctl status nsg-dashboard --no-pager
```

## 3. Connect Nginx

Back up your existing site before editing it. Insert the
[proxy location](deployment/nginx-findings.conf.example) inside its existing
`server` block. Do not replace the entire site or open port 8000 in an NSG.

```bash
sudo nginx -t
```

Only if that succeeds:

```bash
sudo systemctl reload nginx
curl -i http://127.0.0.1/api/findings
```

Expect 200 with `Server: nginx`. Troubleshooting:

```bash
sudo journalctl -u nsg-dashboard -n 40 --no-pager
```

## 4. Install the static files

Transfer these three files from `dashboard/dist/` to the VM:

- `nsg-dashboard.html`
- `nsg-dashboard.css`
- `nsg-dashboard.js`

For example, from the Mac, using your existing SSH access (replace the host):

```bash
scp dashboard/dist/nsg-dashboard.html dashboard/dist/nsg-dashboard.css dashboard/dist/nsg-dashboard.js AntLabAdmin01@VM_PRIVATE_IP:~/nsg-dashboard/
```

Then on the VM, after checking that these destination filenames do not contain
an existing page you need to preserve:

```bash
sudo install -m 0644 ~/nsg-dashboard/nsg-dashboard.html /var/www/html/nsg-dashboard.html
sudo install -m 0644 ~/nsg-dashboard/nsg-dashboard.css /var/www/html/nsg-dashboard.css
sudo install -m 0644 ~/nsg-dashboard/nsg-dashboard.js /var/www/html/nsg-dashboard.js
```

If you use a jump host, configure a web-VM SSH alias with `ProxyJump` and its
`IdentityFile` entries, then use that alias as the scp destination. Private keys
stay on your Mac; do not copy them onto the jump host. A shell continuation `\`
must be the final character on its line, with no spaces after it.

## 5. Open the private page

With private network/VPN access, open `http://VM_PRIVATE_IP/nsg-dashboard.html`.
Otherwise, from your Mac use the web VM's existing SSH alias:

```bash
ssh -N -L 127.0.0.1:8080:127.0.0.1:80 WEB_VM_SSH_ALIAS
```

Leave the tunnel running and open
`http://localhost:8080/nsg-dashboard.html`. The browser's localhost refers to the
Mac; the forwarded target localhost refers to the VM. The alias handles the
management jump host. No public HTTP rule is required. Ctrl+C closes the tunnel.

The default homepage is not replaced. Static file changes do not require an
Nginx reload. Refresh retrieves saved findings; it does not invoke the checker.

## Behavior and limits

- Loads on page open and when Refresh findings is pressed; no automatic polling.
- Refresh retrieves saved rows, not a new NSG scan.
- Shows individual last-detected timestamps in the browser's local time.
- Reports errors separately from empty results and renders data using
  `textContent`, not HTML interpolation.
- The current API does not supply a last-successful-scan timestamp. Empty results
  do not prove a scan ran or that the network is safe.
- Keep Nginx private. The VM's Azure authentication does not authenticate people
  visiting the page. Do not expose this dashboard publicly without additional
  access controls and HTTPS.

## AI assistance

The HTML, CSS, and JavaScript frontend was created with AI assistance as a tool
for this project. Frontend development was not the portion I focused on learning;
my learning effort focused on the Azure infrastructure, Python NSG checks,
managed identity, storage, and Sentinel automation. The page provides a simple
way to display the results of that work.
