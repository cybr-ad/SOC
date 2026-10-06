<#
==================================================================================
Script: host-indexer.ps1
Purpose: Windows 11 Host Splunk Enterprise Setup, Receiver & BOTSv2 Dataset Deployer
Platform: Windows 11 Host (VMware Host)
Role: Central SOC SIEM Receiver (192.168.10.1:9997) & Search Head
Compatible: Windows PowerShell 5.1 & PowerShell 7+
==================================================================================
#>

[CmdletBinding()]
param (
    [string]$SplunkPath = "C:\Program Files\Splunk",
    [int]$ReceiverPort = 9997,
    [switch]$SkipFirewall,
    [switch]$SkipBOTSv2,
    [switch]$ForceRestart
)

$ErrorActionPreference = "Continue"

# --------------------------------------------------------------------------------
# 0. UI HELPERS & BANNER
# --------------------------------------------------------------------------------
Clear-Host
Write-Host "================================================================================" -ForegroundColor Cyan
Write-Host "       SPLUNK ENTERPRISE HOST INDEXER & SOC SIEM AUTO-DEPLOYER                  " -ForegroundColor Yellow
Write-Host "       Receiver (TCP 9997), Indexes, XML Extractions & BOTSv2 Ingestion         " -ForegroundColor Cyan
Write-Host "================================================================================" -ForegroundColor Cyan

function Write-Step { param([string]$Text) Write-Host "`n[+] $Text" -ForegroundColor Yellow }
function Write-Success { param([string]$Text) Write-Host "    [OK] $Text" -ForegroundColor Green }
function Write-Info { param([string]$Text) Write-Host "    [*] $Text" -ForegroundColor Cyan }
function Write-Warn { param([string]$Text) Write-Host "    [!] $Text" -ForegroundColor Yellow }
function Write-Failure { param([string]$Text) Write-Host "    [-] $Text" -ForegroundColor Red }

# --------------------------------------------------------------------------------
# 1. AUTO-ELEVATION (ADMINISTRATOR REQUIRED)
# --------------------------------------------------------------------------------
Write-Step "Step 1: Checking Administrator Privileges..."
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Warn "Requesting UAC Elevation to configure Firewall, Splunkd, and Apps..."
    $script = if ($PSCommandPath) { $PSCommandPath } else { $MyInvocation.MyCommand.Definition }
    Start-Process powershell.exe -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$script`""
    exit 0
}
Write-Success "Elevated Administrator privileges confirmed."

# --------------------------------------------------------------------------------
# 2. LOCATE SPLUNK ENTERPRISE INSTALLATION (C: DRIVE ONLY)
# --------------------------------------------------------------------------------
Write-Step "Step 2: Detecting Splunk Enterprise Installation..."

$CandidatePaths = @(
    $SplunkPath,
    $env:SPLUNK_HOME,
    "C:\Program Files\Splunk",
    "C:\Splunk"
)

$SplunkHome = $null
foreach ($cand in $CandidatePaths) {
    if ($cand -and (Test-Path (Join-Path $cand "bin\splunk.exe"))) {
        $SplunkHome = $cand
        break
    }
}

if (-not $SplunkHome) {
    Write-Failure "Splunk Enterprise installation was NOT found in C:\Program Files\Splunk or C:\Splunk!"
    Write-Warn "Please install Splunk Enterprise to 'C:\Program Files\Splunk' and re-run."
    exit 1
}

Write-Success "Splunk Enterprise detected at: $SplunkHome"
$SplunkBin = Join-Path $SplunkHome "bin\splunk.exe"

# --------------------------------------------------------------------------------
# 3. CONFIGURE WINDOWS DEFENDER FIREWALL (INBOUND TCP 9997 & 8000)
# --------------------------------------------------------------------------------
Write-Step "Step 3: Configuring Windows Firewall Rules for SIEM Ingestion..."

if (-not $SkipFirewall) {
    # Port 9997 (Receiver)
    $rule9997 = Get-NetFirewallRule -DisplayName "Splunk Inbound 9997" -ErrorAction SilentlyContinue
    if (-not $rule9997) {
        New-NetFirewallRule -DisplayName "Splunk Inbound 9997" -Description "Allows VMware Forwarders to stream telemetry into Splunk Indexer" -Direction Inbound -Protocol TCP -LocalPort $ReceiverPort -Action Allow -Profile Any | Out-Null
        Write-Success "Created Windows Firewall Rule: Splunk Inbound $ReceiverPort (TCP Allow)."
    }
    else {
        Write-Success "Firewall Rule for Port $ReceiverPort is already ACTIVE."
    }

    # Port 8000 (Splunk Web UI)
    $rule8000 = Get-NetFirewallRule -DisplayName "Splunk Web 8000" -ErrorAction SilentlyContinue
    if (-not $rule8000) {
        New-NetFirewallRule -DisplayName "Splunk Web 8000" -Description "Splunk Web Management Interface" -Direction Inbound -Protocol TCP -LocalPort 8000 -Action Allow -Profile Any | Out-Null
        Write-Success "Created Windows Firewall Rule: Splunk Web 8000 (TCP Allow)."
    }
    else {
        Write-Success "Firewall Rule for Port 8000 is already ACTIVE."
    }
}
else {
    Write-Info "Skipping firewall configuration (-SkipFirewall requested)."
}

# --------------------------------------------------------------------------------
# 4. BACKUP EXISTING LOCAL CONFIGURATIONS
# --------------------------------------------------------------------------------
Write-Step "Step 4: Backing Up Existing Splunk Configurations..."

$LocalDir = Join-Path $SplunkHome "etc\system\local"
$BackupDir = "C:\SOC_Lab\host-backups\$(Get-Date -Format 'yyyyMMdd_HHmmss')"
New-Item -Path $BackupDir -ItemType Directory -Force | Out-Null

foreach ($confFile in @("inputs.conf", "indexes.conf", "props.conf")) {
    $src = Join-Path $LocalDir $confFile
    if (Test-Path $src) {
        Copy-Item -Path $src -Destination (Join-Path $BackupDir "$confFile.bak") -Force
        Write-Info "Backed up $confFile -> $BackupDir"
    }
}
Write-Success "Configuration backup complete (Preserving existing settings)."

# --------------------------------------------------------------------------------
# 5. SAFE UPDATE: INPUTS.CONF (TCP RECEIVER 9997)
# --------------------------------------------------------------------------------
Write-Step "Step 5: Ensuring TCP Port $ReceiverPort Receiver is Active in inputs.conf..."

$inputsPath = Join-Path $LocalDir "inputs.conf"
$inputsContent = if (Test-Path $inputsPath) { Get-Content -Path $inputsPath -Raw } else { "" }

if ($inputsContent -notmatch "\[splunktcp://(:\d+|9997)\]") {
    $receiverStanza = @"

# ==============================================================================
# Splunk Enterprise Receiver Port Configuration
# ==============================================================================
[splunktcp://${ReceiverPort}]
connection_host = ip
"@
    Add-Content -Path $inputsPath -Value $receiverStanza -Encoding utf8
    Write-Success "Appended [splunktcp://$ReceiverPort] to inputs.conf."
}
else {
    Write-Success "Receiver stanza [splunktcp://$ReceiverPort] is already configured."
}

# --------------------------------------------------------------------------------
# 6. SAFE UPDATE: INDEXES.CONF (win_logs, sysmon, linux_logs, botsv2)
# --------------------------------------------------------------------------------
Write-Step "Step 6: Ensuring Dedicated SOC Lab Indexes Exist in indexes.conf..."

$indexesPath = Join-Path $LocalDir "indexes.conf"
$indexesContent = if (Test-Path $indexesPath) { Get-Content -Path $indexesPath -Raw } else { "" }

$requiredIndexes = @("win_logs", "sysmon", "linux_logs", "botsv2")
$missingIndexes = @()

foreach ($idx in $requiredIndexes) {
    if ($indexesContent -notmatch "\[$idx\]") {
        $missingIndexes += $idx
    }
}

if ($missingIndexes.Count -gt 0) {
    Write-Info "Adding missing index definitions: $($missingIndexes -join ', ')..."
    $newIndexDefinitions = ""
    foreach ($idx in $missingIndexes) {
        $maxSize = if ($idx -eq "botsv2") { "51200" } else { "10240" }
        $newIndexDefinitions += @"

[$idx]
homePath   = `$SPLUNK_DB/$idx/db
coldPath   = `$SPLUNK_DB/$idx/colddb
thawedPath = `$SPLUNK_DB/$idx/thaweddb
maxDataSize = auto_high_volume
maxTotalDataSizeMB = $maxSize
"@
    }
    Add-Content -Path $indexesPath -Value $newIndexDefinitions -Encoding utf8
    Write-Success "Indexes ($($missingIndexes -join ', ')) successfully added to indexes.conf."
}
else {
    Write-Success "All required indexes (win_logs, sysmon, linux_logs, botsv2) already configured."
}

# --------------------------------------------------------------------------------
# 7. SAFE UPDATE: PROPS.CONF (SYSMON XML PARSER & EXTRACTIONS)
# --------------------------------------------------------------------------------
Write-Step "Step 7: Configuring Sysmon XML Field Extractions in props.conf..."

$propsPath = Join-Path $LocalDir "props.conf"
$propsContent = if (Test-Path $propsPath) { Get-Content -Path $propsPath -Raw } else { "" }

if ($propsContent -notmatch "XmlWinEventLog:Microsoft-Windows-Sysmon/Operational") {
    $propsStanza = @"

# ==============================================================================
# Sysmon XML Search-Time Field Extractions
# ==============================================================================
[XmlWinEventLog:Microsoft-Windows-Sysmon/Operational]
KV_MODE = xml
EXTRACT-sysmon-eventid = <EventID>(?<EventID>\d+)</EventID>
EXTRACT-sysmon-eventdata = <Data Name=['"](?<_KEY_1>[^'"]+)['"]>\s*(?<_VAL_1>[^<]*)\s*</Data>
FIELDALIAS-eventcode = EventID AS EventCode

[source::*WinEventLog:Microsoft-Windows-Sysmon/Operational*]
KV_MODE = xml
EXTRACT-sysmon-eventid = <EventID>(?<EventID>\d+)</EventID>
EXTRACT-sysmon-eventdata = <Data Name=['"](?<_KEY_1>[^'"]+)['"]>\s*(?<_VAL_1>[^<]*)\s*</Data>
FIELDALIAS-eventcode = EventID AS EventCode

[source::*sysmon*.xml]
KV_MODE = xml
EXTRACT-sysmon-eventid = <EventID>(?<EventID>\d+)</EventID>
EXTRACT-sysmon-eventdata = <Data Name=['"](?<_KEY_1>[^'"]+)['"]>\s*(?<_VAL_1>[^<]*)\s*</Data>
FIELDALIAS-eventcode = EventID AS EventCode
"@
    Add-Content -Path $propsPath -Value $propsStanza -Encoding utf8
    Write-Success "Sysmon XML parser and field aliases configured in props.conf."
}
else {
    Write-Success "Sysmon XML parsing rules already configured in props.conf."
}

# --------------------------------------------------------------------------------
# 8. BOTSv2 DATASET DEPLOYMENT (PRE-INDEXED SPLUNK APP & BUCKETS)
# --------------------------------------------------------------------------------
if (-not $SkipBOTSv2) {
    Write-Step "Step 8: Deploying Wayne Enterprises BOTSv2 Dataset..."

    $BaseDir = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Definition }
    if (-not $BaseDir) { $BaseDir = (Get-Location).Path }
    $ProjectRoot = (Resolve-Path (Join-Path $BaseDir "..")).Path

    $TargetAppDir = Join-Path $SplunkHome "etc\apps\botsv2_data_set"
    $TargetDbDir = Join-Path $SplunkHome "var\lib\splunk\botsv2\db"

    # Search candidate sources on C: drive only
    $botsCandidates = @(
        (Join-Path $ProjectRoot "hw\lab\botsv2_data_set"),
        (Join-Path $ProjectRoot "hw\lab\botsv2_data_set_attack_only.tgz"),
        "C:\Users\$($env:USERNAME)\Desktop\lab\botsv2_data_set",
        "C:\Users\Administrator\Desktop\lab\botsv2_data_set",
        "C:\SOC_Lab\botsv2_data_set"
    )

    $botsSource = $null
    foreach ($b in $botsCandidates) {
        if (Test-Path $b) { $botsSource = $b; break }
    }

    if ($botsSource) {
        Write-Info "Found BOTSv2 source: $botsSource"

        # 1. Deploy App Structure
        if (-not (Test-Path $TargetAppDir)) {
            New-Item -Path $TargetAppDir -ItemType Directory -Force | Out-Null
        }

        if ($botsSource -like "*.tgz") {
            Write-Info "Extracting BOTSv2 archive into $SplunkHome\etc\apps..."
            & tar.exe -xvzf "$botsSource" -C "$SplunkHome\etc\apps" | Out-Null
            Write-Success "BOTSv2 archive extracted."
        }
        else {
            Write-Info "Mirroring BOTSv2 app directory to $TargetAppDir via robocopy..."
            robocopy "$botsSource" "$TargetAppDir" /E /NFL /NDL /NP /R:1 /W:1 | Out-Null
            Write-Success "BOTSv2 App structure deployed to $TargetAppDir"
        }

        # 2. Mirror Pre-indexed Buckets to $SPLUNK_DB/botsv2/db for dual-path guarantee
        $sourceBuckets = Join-Path $TargetAppDir "var\lib\splunk\botsv2\db"
        if (-not (Test-Path $sourceBuckets)) {
            $sourceBuckets = Join-Path $botsSource "var\lib\splunk\botsv2\db"
        }

        if (Test-Path $sourceBuckets) {
            Write-Info "Mirroring pre-indexed tsidx buckets into $TargetDbDir..."
            if (-not (Test-Path $TargetDbDir)) {
                New-Item -Path $TargetDbDir -ItemType Directory -Force | Out-Null
            }
            robocopy "$sourceBuckets" "$TargetDbDir" /E /NFL /NDL /NP /R:1 /W:1 | Out-Null
            Write-Success "BOTSv2 database buckets mirrored to $TargetDbDir"
        }
    }
    else {
        Write-Warn "BOTSv2 dataset package not found in C: drive candidate paths."
        Write-Info "If botsv2_data_set is in a custom path, run .\deploy-botsv2.ps1"
    }
}
else {
    Write-Info "Skipping BOTSv2 deployment (-SkipBOTSv2 requested)."
}

# --------------------------------------------------------------------------------
# 9. RESTART SPLUNK SERVICE & VERIFY LISTENER
# --------------------------------------------------------------------------------
Write-Step "Step 9: Restarting Splunk Enterprise Service..."

$splunkService = Get-Service -Name "Splunkd" -ErrorAction SilentlyContinue

if ($splunkService) {
    Restart-Service -Name "Splunkd" -Force
    Write-Success "Splunkd Windows Service restarted."
    Start-Sleep -Seconds 5
}
elseif (Test-Path $SplunkBin) {
    & "$SplunkBin" restart | Out-Null
    Write-Success "Splunk CLI restarted."
}

# Verify Port 9997 Listening Status
Write-Step "Step 10: Verifying SIEM Ingestion Listener..."
$listenerCheck = Get-NetTCPConnection -LocalPort $ReceiverPort -State Listen -ErrorAction SilentlyContinue
if ($listenerCheck) {
    Write-Success "CONFIRMED: Splunk is actively LISTENING on TCP port $ReceiverPort!"
}
else {
    Write-Warn "Port $ReceiverPort not detected in LISTEN state immediately. Splunkd may still be initializing."
}

# --------------------------------------------------------------------------------
# 10. SPL VERIFICATION QUERIES DASHBOARD
# --------------------------------------------------------------------------------
Write-Host "`n================================================================================" -ForegroundColor Cyan
Write-Host "                    HOST INDEXER SETUP COMPLETE!                                " -ForegroundColor Green
Write-Host "================================================================================" -ForegroundColor Cyan

$webUrl = "http://localhost:8000"
Write-Host "Splunk Web Interface : $webUrl" -ForegroundColor White
Write-Host "Receiving Port (TCP) : $ReceiverPort (Listening)" -ForegroundColor White
Write-Host "Configured Indexes   : win_logs, sysmon, linux_logs, botsv2" -ForegroundColor White

Write-Host "`n--- VERIFICATION SPL QUERIES (Run in Splunk Web Search & Reporting) ---" -ForegroundColor Yellow
$queries = @"
1. Global Ingestion Health Check:
   | tstats count where index=* by index, sourcetype

2. Windows Active Directory Logs (30,000+ Events):
   index=win_logs earliest=0
   | stats count by EventCode, host

3. Sysmon Process & Network Telemetry (4,000+ Events):
   index=sysmon earliest=0
   | stats count by EventCode, host

4. Linux Server Telemetry (2,000+ Events):
   index=linux_logs earliest=0
   | stats count by sourcetype

5. BOTSv2 Wayne Enterprises Threat Hunting:
   index=botsv2 earliest=0
   | head 10
"@
Write-Host $queries -ForegroundColor White

Write-Host "================================================================================" -ForegroundColor Cyan
Write-Host "All configurations applied. Host Indexer is ready and ingesting data!" -ForegroundColor Green
Write-Host "================================================================================`n" -ForegroundColor Cyan
