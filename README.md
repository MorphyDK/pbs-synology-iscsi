# Proxmox Backup Server Post-Install & Synology iSCSI Setup

A safe, interactive, and fully automated **post-install script for Proxmox Backup Server (PBS)** designed to optimize your system and seamlessly mount high-performance **Synology iSCSI LUNs** for backup storage.

Based on the enterprise best practices from Derek Seaman's storage guides. Thanks Derek :)

**Current version: 1.5** — see the [Changelog](#-changelog).

---

## 🚀 Key Features

*   **Repository Optimization:** Automatically disables the paid enterprise repositories and configures the official, free `pbs-no-subscription` repository (using secure deb822 API format).
*   **System Upgrades:** Performs a clean, unattended `apt full-upgrade` to patch your kernel and PBS core utilities.
*   **Guided iSCSI Configuration:** Interactive step-by-step assistant to map, verify, and authenticate with your Synology SAN Manager using CHAP.
*   **Smart LUN Inspection:** Scans targeted disks *before* touching them. If an existing PBS datastore is found, it safely re-attaches it without losing a single block of data.
*   **Resilient Mounting:** Sets up a network-aware `/etc/fstab` entry (`_netdev`, `nofail`, no boot-time fsck) paired with an **automatic 1-minute cron monitor** that transparently reconnects the iSCSI session and restores the mount if the network drops or the NAS reboots. Logins and mounts have timeouts, so an unreachable NAS can never stall the monitor.
*   **Local Disk Protection:** The empty mount directory is made immutable, so PBS can never write backups to the system disk if the LUN is missing.
*   **Storage Optimization:** Forces automated weekly `fstrim` routines to pass deleted backup blocks back to your Synology (Thin Provisioning space reclamation).
*   **Web UI Quality of Life:** Disables the persistent "No valid subscription" login popup. This patch survives future system updates automatically.

---

## 🛠️ Prerequisites

Before executing the script, ensure you have:
1. A fresh or existing installation of **Proxmox Backup Server** with root access. **PBS must run as a dedicated VM — not in an LXC container** (iSCSI does not work inside LXC).
2. A configured **LUN and iSCSI Target** inside your Synology **SAN Manager**.
3. **CHAP Authentication** credentials configured on your NAS target (12-16 characters recommended).
4. Network permissions/masking on the Synology mapping access to this PBS server's Initiator Name.

---

## 💻 Quick Start

Run the following command directly on your Proxmox Backup Server as `root`:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/MorphyDK/pbs-synology-iscsi/refs/heads/main/pbs-post-install.sh)
```

> [!NOTE]
> **Safety First:** The script is completely interactive. It gathers your settings, tests connections, and inspects your hardware **before writing any data** or formatting any disks. You can abort at any point during the questionnaire without changing your system.
<img width="532" height="442" alt="Screeny" src="https://github.com/user-attachments/assets/c32f843e-d814-4bc0-b693-c5c7d8c20b2a" />

<img width="535" height="454" alt="Guide info" src="https://github.com/user-attachments/assets/471b454b-4013-4218-8bd2-be03c11c2d79" />

<img width="589" height="167" alt="Connection" src="https://github.com/user-attachments/assets/ee873bf1-8ae9-4248-a6d0-538bdcdd1d21" />

<img width="559" height="302" alt="ISCSI2" src="https://github.com/user-attachments/assets/bad544d3-cb31-485b-b6f4-5c58c8d03a56" />

<img width="556" height="651" alt="Lun setup" src="https://github.com/user-attachments/assets/2cf7a386-b14c-4bb1-bba8-aaff1c438e28" />

<img width="965" height="650" alt="setup done" src="https://github.com/user-attachments/assets/4c170b02-d217-4d62-ae63-958b12b3f903" />

<img width="1613" height="608" alt="ProxmoxPBS" src="https://github.com/user-attachments/assets/617ba011-9193-439c-b47d-7b02470aca24" />


---

## 🔄 Updating an Existing Installation

Already running an older version? Just run the Quick Start command again — your LUN and backups are not touched.

1. In **Options**, select only **Connect a Synology iSCSI LUN** and **Create a PBS datastore** (untick the rest if you don't need them).
2. Pick your target. The script detects that the LUN is **already mounted** and keeps it exactly as it is.
3. At the datastore question, choose **Keep the existing datastore - skip this step**.

The installer then brings the `/etc/fstab` entry and the iSCSI monitor up to the current version (a backup of `/etc/fstab` is saved first).

Check the result:
```bash
grep /mnt/synology /etc/fstab                                  # should contain _netdev and end with 0 0
grep -n timeout /usr/local/bin/check-iscsi-session-*.sh        # should show the login and mount timeouts
tail -n 20 /var/log/iscsi-monitor.log                          # reconnect history
```

---

## 📸 How It Works (Stepper Architecture)

The installer splits execution into an interactive **Setup** menu and an unattended **Installation** pipeline:

**Setup (interactive — nothing on any disk is changed)**
Welcome › Options › iSCSI tools › Synology guide › Connection test › LUN & filesystem inspection › Mount & datastore › Review of the full plan

**Installation (unattended, with progress bar)**
APT repositories › System upgrade › Connect to iSCSI target › Prepare disk › Mount via `/etc/fstab` › Monitoring & TRIM › PBS datastore › Subscription popup › Finish

Everything is logged to `/var/log/pbs-post-install.log` (CHAP secrets are never written to the log).

---

## 📝 Changelog

### v1.5 — 18/10-2026
*   Re-running on an already mounted LUN now corrects an outdated `/etc/fstab` entry from older versions (adds `_netdev`, disables boot-time fsck).
*   iSCSI monitor: 30 s timeout on login and 60 s timeout on mount, so a hanging attempt against an unreachable NAS can no longer block the reconnects that follow.

### v1.4 — 10/3-2026
*   Previous release.
