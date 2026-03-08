# Obsidian LiveSync — Connecting Devices

Guide for connecting new devices to the self-hosted CouchDB sync server.

## Prerequisites

- Obsidian installed on the device
- CouchDB server running and accessible at `https://obsidian.qwqw333.work`

## Connection Details

| Parameter | Value |
|-----------|-------|
| **Server URI** | `https://obsidian.qwqw333.work` |
| **Username** | CouchDB admin user (from `vault_couchdb_user`) |
| **Password** | CouchDB admin password (from `vault_couchdb_password`) |
| **Database name** | `obsidian` |
| **E2E Encryption** | Enabled — use the same passphrase on every device |

> **Critical:** Database name and E2E passphrase must be identical across all devices syncing the same vault.

## Setup Steps (All Platforms)

### 1. Install the Plugin

Open Obsidian → **Settings** → **Community plugins** → **Browse** → search **"Self-hosted LiveSync"** → **Install** → **Enable**.

### 2. Configure Remote Database

The plugin will launch a setup wizard on first run. If not — go to **Settings** → **Self-hosted LiveSync** → **Setup wizard**.

1. Enter Server URI, Username, Password, and Database name (see table above)
2. Enable End-to-End Encryption and enter the shared passphrase
3. Click **Test Settings and Continue**

### 3. Choose Scenario

Select **"My remote server is already set up. I want to join this device."** — this fetches existing notes from the server.

### 4. Handle Prompts

| Prompt | Action |
|--------|--------|
| Fetch Remote Configuration Failed | Click **Skip and proceed** |
| Send all chunks before replication? | Click **Yes** |
| All optional features are disabled | Click **OK** |
| Config Doctor | Click **Yes** and accept all recommended fixes |
| Database size notification | Click **No, never warn please** |

### 5. Set Sync Mode

| Platform | Recommended mode | Why |
|----------|-----------------|-----|
| macOS / Linux / Windows (desktop) | **LiveSync** | Real-time sync, always-on power |
| iPhone / Android | **Periodic** or **On events** | Saves battery |

Go to **Settings** → **Self-hosted LiveSync** → Sync Settings tab → enable the desired mode.

### 6. Customization Sync (Optional)

Syncs Obsidian settings (themes, hotkeys, plugin configs) between devices.

1. Go to **Settings** → **Self-hosted LiveSync** → **Customization sync** tab
2. Set a unique **Device name** (e.g. `macbook-pro`, `iphone`, `linux-desktop`, `windows-pc`)
3. Enable **Per-file-saved customization sync**
4. Enable **Enable customization sync**
5. When prompted about settings from another device — choose **Apply settings to this device** to sync config

## Platform-Specific Notes

### macOS

No special steps. Standard setup as described above.

### Linux

No special steps. Install Obsidian via AppImage, Flatpak, or Snap — then follow the standard setup. Case-Sensitive file handling is set to `false` by default for cross-platform compatibility; change to `true` only if all devices run Linux.

### Windows

No special steps. Download Obsidian from [obsidian.md](https://obsidian.md) — then follow the standard setup.

### iPhone / iPad

- Install Obsidian from the App Store
- Community plugins require disabling "Restricted mode" in Settings → Community plugins
- Prefer **Periodic** or **On events** sync mode to conserve battery
- To trigger manual sync: tap the menu icon → type **"Replicate now"**

## Troubleshooting

### Notes Not Syncing

1. Check the status bar at the bottom of Obsidian for sync status or errors
2. Run **Command Palette** → **"Self-hosted LiveSync: Replicate now"**
3. Verify the database name and E2E passphrase match the first device exactly
4. Ensure a sync mode is enabled (LiveSync, Periodic, or On events) — without one, sync won't start

### Configuration Mismatch Detected

If prompted about a config mismatch — click **Apply settings to this device** to align with the remote server config.

### Verify Server Health

```bash
curl -s -u 'USER:PASSWORD' https://obsidian.qwqw333.work/ | python3 -m json.tool
curl -s -u 'USER:PASSWORD' https://obsidian.qwqw333.work/obsidian | python3 -m json.tool
```

The first command should return `{"couchdb":"Welcome",...}`. The second shows database info — check `doc_count` for the number of synced documents.

## Security Model

Traffic is encrypted at every layer:

1. **Cloudflare edge** — TLS between client and Cloudflare
2. **Origin Certificate** — TLS between Cloudflare and Caddy
3. **CouchDB auth** — `require_valid_user = true`, Basic Auth
4. **E2E Encryption** — data encrypted with passphrase before leaving the device
