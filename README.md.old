# 🛡️ Enterprise SOC Lab Automation Suite
### Complete Zero-to-Hero Telemetry Ingestion, Splunk SIEM & Threat Hunting Pipeline

[![Splunk](https://img.shields.io/badge/Splunk-Enterprise_9.x-black?style=for-the-badge&logo=splunk)](https://www.splunk.com/)
[![Windows Server](https://img.shields.io/badge/Windows_Server-2022_Datacenter-0078D6?style=for-the-badge&logo=windows)](https://microsoft.com)
[![Ubuntu](https://img.shields.io/badge/Ubuntu-22.04_LTS-E95420?style=for-the-badge&logo=ubuntu)](https://ubuntu.com)
[![PowerShell](https://img.shields.io/badge/PowerShell-5.1_%7C_7+-5391FE?style=for-the-badge&logo=powershell)](https://github.com/PowerShell/PowerShell)
[![Bash](https://img.shields.io/badge/Bash-Shell_Script-4EAA25?style=for-the-badge&logo=gnu-bash)](https://gnu.org)

An intelligent, path-independent, and self-healing automation suite built for **SOC Class 02**. It deploys and unifies **Windows Server 2022 (Active Directory + Sysmon)**, **Ubuntu Linux Server (auditd)**, and the **Wayne Enterprises BOTSv2 Challenge Dataset** into a central **Splunk Enterprise SIEM Indexer**.

---

## 📐 Network & Telemetry Architecture

All communication takes place across the isolated VMware NAT subnet (**VMnet8**):

```
+-----------------------------------------------------------------------------------------------+
|                                VMware Workstation NAT (VMnet8)                                |
|                         Subnet: 192.168.10.0/24  |  Gateway: 192.168.10.2                     |
+-----------------------------------------------------------------------------------------------+
           │                                      │                                      │
           │ TCP 9997                             │ TCP 9997                             │ Web 8000
           ▼                                      ▼                                      ▼
+─────────────────────────────+        +─────────────────────────────+        +─────────────────────────────+
|   Windows Server 2022 VM    |        |       Ubuntu Linux VM       |        |    Windows 11 (Host PC)     |
|         DC01-CORP           |        |         srv-linux-01        |        |       SIEM Indexer          |
|       192.168.10.20         |        |        192.168.10.30        |        |        192.168.10.1         |
+─────────────────────────────+        +─────────────────────────────+        +─────────────────────────────+
| • Event 4688 CLI Auditing   |        | • High-Fidelity auditd Rules|        | • Ingestion Port: TCP 9997  |
| • Sysmon Events 1, 3, 10, 22|        | • OpenSSH / auth.log        |        | • Web Search Head: HTTP 8000|
| • PowerShell Script Blocks  |        | • System Logs (syslog)      |        | • BOTSv2 Wayne Enterprises  |
| • Universal Forwarder       |        | • Universal Forwarder       |        |   Pre-Indexed Dataset App   |
+─────────────────────────────+        +─────────────────────────────+        +─────────────────────────────+
           │                                      │                                      │
           ▼                                      ▼                                      ▼
     index=win_logs                         index=linux_logs                        index=botsv2
      index=sysmon                                                                 (3.4 GB Scenario)
```

---

## ⚡ 3-Step "Zero-to-Hero" Execution Flow

Deploy the lab by executing exactly one script per machine in the following order:

```
  [ STEP 1 ] ──▶ Windows 11 Host (Splunk Receiver + BOTSv2)
        │
  [ STEP 2 ] ──▶ Windows Server 2022 VM (DC01-CORP Telemetry)
        │
  [ STEP 3 ] ──▶ Ubuntu Linux VM (srv-linux-01 auditd Telemetry)
```

---

### Step 1: Windows 11 Host Indexer (`host-indexer.ps1`)
> **Where to run:** On your physical Windows 11 machine hosting VMware Workstation.

1. Open **PowerShell** as **Administrator**.
2. Navigate to this folder and execute:
   ```powershell
   cd "C:\Users\MSI Laptop\Downloads\SOC_DEATH-Anti\output"
   .\host-indexer.ps1
   ```

**Automated Tasks Performed:**
- ✅ Auto-elevates to Administrator via UAC.
- ✅ Creates Windows Defender Firewall inbound rules for TCP **9997** (Ingestion) & **8000** (Web UI).
- ✅ Non-destructively enables `[splunktcp://9997]` in `inputs.conf`.
- ✅ Adds custom index definitions (`win_logs`, `sysmon`, `linux_logs`, `botsv2`) to `indexes.conf`.
- ✅ Deploys Sysmon XML search-time field extractions & aliases to `props.conf`.
- ✅ Automatically mirrors the **3.4 GB Wayne Enterprises BOTSv2 dataset** into `Splunk\etc\apps\botsv2_data_set` and maps database buckets.
- ✅ Restarts the `Splunkd` Windows service and confirms the port 9997 listener.

---

### Step 2: Windows Server 2022 VM (`Ultimate-win_2022-forwarder.ps1`)
> **Where to run:** Inside the `DC01-CORP` Windows Server VM in VMware.

1. Copy `Ultimate-win_2022-forwarder.ps1` into the VM (e.g. `C:\Users\Administrator\Desktop` or `C:\SOC_Lab`).
2. Open **PowerShell** as **Administrator** inside the VM.
3. Execute:
   ```powershell
   Set-ExecutionPolicy Bypass -Scope Process -Force
   .\Ultimate-win_2022-forwarder.ps1
   ```

**Automated Tasks Performed:**
- ✅ **Gateway Self-Healing:** Detects and repairs the `192.168.10.1` vs `192.168.10.2` gateway conflict so VM internet and ping work without freezing.
- ✅ **Audit Policies:** Enables **Event 4688 Process Creation with Command-Line** inclusion and PowerShell Script Block Logging (Event 4104).
- ✅ **Sysmon Automation:** Locates local binary/config or auto-downloads from Microsoft Sysinternals and SwiftOnSecurity. Sets service to Automatic.
- ✅ **Forwarder Ingestion:** Configures inputs to stream Security, System, App, PowerShell, Sysmon, and simulation attack logs to `192.168.10.1:9997`.

---

### Step 3: Ubuntu Linux Server VM (`Ultimate-for-set-Linux.sh`)
> **Where to run:** Inside the `srv-linux-01` Ubuntu Server VM in VMware.

1. Copy `Ultimate-for-set-Linux.sh` into the VM (e.g. `/home/socadmin/`).
2. Open **Terminal** inside the VM and run with `sudo`:
   ```bash
   sudo bash Ultimate-for-set-Linux.sh
   ```

**Automated Tasks Performed:**
- ✅ Installs `auditd`, `audispd-plugins`, `rsyslog`, `acl`, and network utilities.
- ✅ Deploys high-fidelity SOC audit rules (`/etc/audit/rules.d/soc-audit.rules`) covering identity files (`/etc/passwd`, `/etc/shadow`), sudoers, network configs, and root execution.
- ✅ Installs Splunk Universal Forwarder from local `.deb` or official Splunk CDN.
- ✅ **Permission Self-Healing:** Applies POSIX ACLs (`setfacl -m u:splunk:r /var/log/audit/audit.log`) so Splunk can ingest audit logs without violating security.
- ✅ Configures forwarding to `192.168.10.1:9997` and enables system boot-start.

---

## 🔎 Splunk Search & Threat Hunting Cheat Sheet

Open your browser: **`http://localhost:8000`** -> **Search & Reporting**.

> [!IMPORTANT]
> **Always set the Time Picker (top right) to "All time"** or prefix queries with `earliest=0` to ensure historical simulation and BOTSv2 events are returned.

### 1. Ingestion Health Check (All Indexes)
```spl
| tstats count where index=* by index, host, sourcetype
```
*Expected: See `DC01-CORP` under `win_logs` & `sysmon`, and `srv-linux-01` under `linux_logs`.*

---

### 2. Windows Active Directory Security (`index=win_logs`)
- **Brute Force / Failed Logons (EventCode 4625):**
  ```spl
  index=win_logs EventCode=4625 earliest=0
  | stats count by TargetUserName, WorkstationName, IpAddress
  | sort -count
  ```
- **New Domain User Account Created (EventCode 4720):**
  ```spl
  index=win_logs EventCode=4720 earliest=0
  | table _time, SubjectUserName, TargetUserName, SAMAccountName
  ```

---

### 3. Microsoft Sysmon Telemetry (`index=sysmon`)
- **Process Creation with Command-Line Inspection (EventCode 1):**
  ```spl
  index=sysmon EventCode=1 earliest=0
  | table _time, host, User, ParentImage, Image, CommandLine
  ```
- **Credential Dumping / LSASS Memory Access (EventCode 10):**
  ```spl
  index=sysmon EventCode=10 TargetImage="*lsass.exe" earliest=0
  | table _time, host, SourceImage, TargetImage, GrantedAccess
  ```

---

### 4. Linux Server Telemetry (`index=linux_logs`)
- **SSH Authentication Failures:**
  ```spl
  index=linux_logs sourcetype=linux_secure "Failed password" earliest=0
  | stats count by src_ip, user
  | sort -count
  ```
- **Auditd Modifications to Sensitive Identity Files:**
  ```spl
  index=linux_logs sourcetype=linux_audit key="identity_changes" earliest=0
  | table _time, name, ouid, proctitle
  ```

---

### 5. Wayne Enterprises Threat Hunting (`index=botsv2`)
- **Verify Wayne Enterprises Attack Telemetry:**
  ```spl
  index=botsv2 earliest=0
  | stats count by sourcetype
  ```
- **Investigate Web & Linux Telemetry inside BOTSv2:**
  ```spl
  index=botsv2 (sourcetype="osquery*" OR sourcetype="top" OR sourcetype="iis") earliest=0
  | stats count by sourcetype, host
  ```

---

## 🛠️ Troubleshooting & Knowledge Base

### 1. Querying Multiple Indexes: Use `OR`, Never `AND`
- ❌ **Wrong:** `index=linux_logs AND index=botsv2` ➔ **Returns 0 events** because an individual log event can only belong to *one* index at a time.
- ✅ **Correct:** `(index=linux_logs OR index=botsv2) earliest=0` ➔ Returns events from both indexes.

### 2. Why BOTSv2 is NOT forwarded from the VM
- **BOTSv2 is a pre-indexed database package:** It contains compiled binary index files (`.tsidx`) and compressed database buckets (`journal.gz`) recorded during the Boss of the SOC competition.
- **Universal Forwarders only tail plain text logs:** If a forwarder tries to read `.tsidx` files, it corrupts the timestamps, generates unreadable garbage strings, and crashes the Splunk license.
- **Correct Method:** Deploy it as a Splunk App on the **Host Indexer** using `host-indexer.ps1`.

### 3. VMware NAT Gateway Conflict (`ping 8.8.8.8` Hangs)
- **Problem:** If a VM's default gateway is set to `192.168.10.1`, traffic routes to the Host PC virtual adapter (which does not forward packets), causing internet pings to hang.
- **Solution:** The gateway must be `192.168.10.2` (the VMware NAT daemon). The scripts configure this automatically.

### 4. Linux `audit.log` Permission Denied
- **Problem:** Linux defaults `/var/log/audit` to `0700` (root only), preventing the `splunk` user from reading the log.
- **Solution:** The script applies POSIX Access Control Lists: `setfacl -m u:splunk:r /var/log/audit/audit.log`.

---

## 📦 Directory Manifest

```text
output/
├── host-indexer.ps1                # Step 1: Windows 11 Host Splunk Receiver & BOTSv2 Deployer
├── Ultimate-win_2022-forwarder.ps1 # Step 2: Windows Server 2022 VM Forwarder & Sysmon Deployer
├── Ultimate-for-set-Linux.sh       # Step 3: Ubuntu Linux VM Forwarder & auditd Deployer
└── README.md                       # Comprehensive Guide & Threat Hunting Manual
```

---

## 🎯 Course & Lab Details
- **Course:** SOC Class 02 - Enterprise Monitoring & Threat Detection
- **Target Role:** SOC Analyst L1/L2, Threat Hunter, SIEM Engineer
- **Environment:** VMware Workstation VMnet8 + Windows Server 2022 + Ubuntu 22.04 + Splunk Enterprise 9.x
- **License:** CC0 Public Domain / Educational Training
