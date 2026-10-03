# Proxmox Backup Server Post-Install & Synology iSCSI Setup

A safe, interactive, and fully automated **post-install script for Proxmox Backup Server (PBS)** designed to optimize your system and seamlessly mount high-performance **Synology iSCSI LUNs** for backup storage.

Based on the enterprise best practices from Derek Seaman's storage guides.

---

## 🚀 Key Features

*   **Repository Optimization:** Automatically disables the paid enterprise repositories and configures the official, free `pbs-no-subscription` repository (using secure deb822 API format).
*   **System Upgrades:** Performs a clean, unattended `apt full-upgrade` to patch your kernel and PBS core utilities.
*   **Guided iSCSI Configuration:** Interactive step-by-step assistant to map, verify, and authenticate with your Synology SAN Manager using CHAP.
*   **Smart LUN Inspection:** Scans targeted disks *before* touching them. If an existing PBS datastore is found, it safely re-attaches it without losing a single block of data.
*   **Resilient Mounting:** Sets up robust `/etc/fstab` integration paired with an **automatic 1-minute cron monitor** that transparently recovers mounts if the network drops or the NAS reboots.
*   **Storage Optimization:** Forces automated weekly `fstrim` routines to pass deleted backup blocks back to your Synology (Thin Provisioning space reclamation).
*   **Web UI Quality of Life:** Disables the persistent "No valid subscription" login popup. This patch survives future system updates automatically.

---

## 🛠️ Prerequisites

Before executing the script, ensure you have:
1. A fresh or existing installation of **Proxmox Backup Server** (Root access required and OBS NO LXC - MUST BE DEDICATED VM)
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

## 📸 How It Works (Stepper Architecture)

The installer splits execution into an interactive **Setup** menu and an unattended **Installation** pipeline:

