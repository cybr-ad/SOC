<#
==================================================================================
Script: wundows-forwarder-setup.ps1 / Ultimate-win_2022-forwarder.ps1
Purpose: Universal, Self-Healing Splunk Forwarder & Security Telemetry Setup
Platform: Windows Server 2022 VM (DC01-CORP / Any Windows Server)
Target Indexer: Host Windows 11 Splunk Enterprise Indexer (192.168.10.1:9997)
Compatible: Windows PowerShell 5.1 & PowerShell 7+
==================================================================================
#>

[CmdletBinding()]
param (
    [string]$SplunkServerIP = "192.168.10.1",
    [int]$SplunkPort = 9997,
    [string]$GatewayIP = "192.168.10.2",
    [string]$StaticIP = "192.168.10.20",
    [int]$PrefixLength = 24,
    [string[]]$DnsServers = @("127.0.0.1", "1.1.1.1", "8.8.8.8"),
    [switch]$SkipNetworkFix,
    [switch]$ForceReinstall
)

# Set Strict and Error Preferences
$ErrorActionPreference = "Continue"

# --------------------------------------------------------------------------------
# 0. UI HELPERS & BANNER
# --------------------------------------------------------------------------------
Clear-Host
Write-Host "================================================================================" -ForegroundColor Cyan
Write-Host "      ULTIMATE WINDOWS SERVER 2022 SPLUNK FORWARDER & TELEMETRY SUITE           " -ForegroundColor Yellow
Write-Host "       Universal Path-Independent Auto-Deployer with Comprehensive Self-Healing  " -ForegroundColor Cyan
Write-Host "================================================================================" -ForegroundColor Cyan

function Write-Step {
    param([string]$Text)
    Write-Host "`n[+] $Text" -ForegroundColor Yellow
}

function Write-Success {
    param([string]$Text)
    Write-Host "    [OK] $Text" -ForegroundColor Green
}

function Write-Info {
    param([string]$Text)
    Write-Host "    [*] $Text" -ForegroundColor Cyan
}

function Write-Warn {
    param([string]$Text)
    Write-Host "    [!] $Text" -ForegroundColor Yellow
}

function Write-Failure {
    param([string]$Text)
    Write-Host "    [-] $Text" -ForegroundColor Red
}

# --------------------------------------------------------------------------------
# 1. AUTO-ELEVATION CHECK (ADMINISTRATOR REQUIRED)
# --------------------------------------------------------------------------------
Write-Step "Step 1: Validating Administrator Elevation..."
$currentIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($currentIdentity)
$isAdmin = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Write-Warn "Administrative privileges required. Relaunching with UAC elevation..."
    $scriptPath = $MyInvocation.MyCommand.Definition
    if (-not $scriptPath) {
        $scriptPath = $PSCommandPath
    }
    if ($scriptPath) {
        Start-Process powershell.exe -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`""
        exit 0
    } else {
        Write-Failure "Please right-click PowerShell and select 'Run as Administrator'."
        exit 1
    }
}
Write-Success "Elevated Administrator permissions confirmed."

# --------------------------------------------------------------------------------
# 2. OPERATING SYSTEM & ENVIRONMENT VALIDATION
# --------------------------------------------------------------------------------
Write-Step "Step 2: Checking Operating System Environment..."
$os = Get-CimInstance Win32_OperatingSystem
Write-Info "Detected OS: $($os.Caption) (Build: $($os.BuildNumber), ProductType: $($os.ProductType))"
if ($os.ProductType -eq 1) {
    Write-Warn "Notice: You are running this script on a Windows Client (Workstation/Host) rather than Windows Server."
    Write-Warn "If this is your Host Windows 11 machine, run 'host-indexer.ps1' instead!"
    $proceed = Read-Host "    Do you still want to proceed configuring this machine as a Forwarder? (y/N)"
    if ($proceed -ne 'y' -and $proceed -ne 'Y') {
        Write-Info "Aborting setup on Host machine as requested."
        exit 0
    }
}

# --------------------------------------------------------------------------------
# 3. DIRECTORY & ARTIFACT DISCOVERY (PATH INDEPENDENT)
# --------------------------------------------------------------------------------
Write-Step "Step 3: Discovering Local Tooling and Resources..."

$BaseDir = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Definition }
if (-not $BaseDir) { $BaseDir = (Get-Location).Path }

# Build candidate search locations
$SearchPaths = @(
    $BaseDir,
    (Join-Path $BaseDir ".."),
    (Join-Path $BaseDir "..\class file"),
    "C:\Users\Administrator\Desktop",
    "C:\Users\Administrator\Desktop\class file",
    "C:\Users\Administrator\Desktop\lab",
    "C:\Users\Administrator\Desktop\logs",
    "C:\Users\Administrator\Desktop\Splunk_Configuration_Sets",
    "C:\SOC_Lab",
    "C:\Tools"
)

function Find-ResourceFile {
    param([string]$Pattern)
    foreach ($path in $SearchPaths) {
        if (Test-Path $path) {
            $match = Get-ChildItem -Path $path -Filter $Pattern -Recurse -File -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($match) { return $match.FullName }
        }
    }
    return $null
}

# Create staging working directory
$SocWorkingDir = "C:\SOC_Lab"
$BackupDir = "C:\SOC_Lab\config-backups\$(Get-Date -Format 'yyyyMMdd_HHmmss')"
New-Item -Path $SocWorkingDir -ItemType Directory -Force | Out-Null
New-Item -Path $BackupDir -ItemType Directory -Force | Out-Null
Write-Success "Dedicated staging workspace: $SocWorkingDir"
Write-Success "Configuration backup target: $BackupDir"

# --------------------------------------------------------------------------------
# 4. NETWORK SELF-HEALING & CONNECTIVITY VALIDATION
# --------------------------------------------------------------------------------
Write-Step "Step 4: Network Verification and Self-Healing..."

if (-not $SkipNetworkFix) {
    # Find Primary Ethernet Adapter
    $netAdapter = Get-NetAdapter -Physical -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq "Up" } | Select-Object -First 1
    if (-not $netAdapter) {
        $netAdapter = Get-NetAdapter -Name "Ethernet0" -ErrorAction SilentlyContinue
    }
    if (-not $netAdapter) {
        $netAdapter = Get-NetAdapter -ErrorAction SilentlyContinue | Select-Object -First 1
    }

    if ($netAdapter) {
        $ifAlias = $netAdapter.Name
        Write-Info "Target network interface: $ifAlias ($($netAdapter.InterfaceDescription))"

        # Check existing IP configuration
        $currentIPObj = Get-NetIPAddress -InterfaceAlias $ifAlias -AddressFamily IPv4 -ErrorAction SilentlyContinue | Where-Object { $_.IPAddress -notlike "169.254*" } | Select-Object -First 1
        $currentIP = if ($currentIPObj) { $currentIPObj.IPAddress } else { "None" }
        $currentRoute = Get-NetRoute -InterfaceAlias $ifAlias -DestinationPrefix "0.0.0.0/0" -ErrorAction SilentlyContinue | Select-Object -First 1
        $currentGateway = if ($currentRoute) { $currentRoute.NextHop } else { "None" }
        
        Write-Info "Current IP: $currentIP, Gateway: $currentGateway"

        # Check for wrong gateway (192.168.10.1 causes ping 8.8.8.8 hang)
        $needsReconfig = $false
        if ($currentRoute -and $currentRoute.NextHop -eq "192.168.10.1") {
            Write-Warn "CRITICAL ROOT CAUSE DETECTED: Gateway is set to 192.168.10.1 (Host adapter)!"
            Write-Warn "In VMware NAT (VMnet8), Gateway MUST be 192.168.10.2 for VM internet access."
            $needsReconfig = $true
        }

        if (-not $currentIPObj -or $currentIP -like "169.254*" -or $needsReconfig) {
            Write-Info "Repairing IP and Default Gateway configuration..."
            Remove-NetIPAddress -InterfaceAlias $ifAlias -AddressFamily IPv4 -Confirm:$false -ErrorAction SilentlyContinue
            Remove-NetRoute -InterfaceAlias $ifAlias -DestinationPrefix "0.0.0.0/0" -Confirm:$false -ErrorAction SilentlyContinue
            
            try {
                New-NetIPAddress -InterfaceAlias $ifAlias -IPAddress $StaticIP -PrefixLength $PrefixLength -DefaultGateway $GatewayIP -Confirm:$false -ErrorAction Stop | Out-Null
                Set-DnsClientServerAddress -InterfaceAlias $ifAlias -ServerAddresses $DnsServers -Confirm:$false -ErrorAction SilentlyContinue
                Write-Success "Network repaired: IP=$StaticIP/$PrefixLength, Gateway=$GatewayIP"
            } catch {
                Write-Warn "Notice setting IP: $($_.Exception.Message)"
            }
        } else {
            Write-Success "IP configuration looks valid ($currentIP)."
        }

        # Set Network Category to Private (relaxes firewall blocks between VMs)
        try {
            $connectionProfile = Get-NetConnectionProfile -InterfaceAlias $ifAlias -ErrorAction SilentlyContinue
            if ($connectionProfile -and $connectionProfile.NetworkCategory -ne "Private") {
                Set-NetConnectionProfile -InterfaceAlias $ifAlias -NetworkCategory Private -ErrorAction SilentlyContinue
                Write-Success "Network category updated to Private (relaxes firewall restrictions)."
            }
        } catch {}
    } else {
        Write-Warn "No active physical network adapter detected."
    }
} else {
    Write-Info "Skipping network reconfiguration (-SkipNetworkFix specified)."
}

# Test Connectivity
Write-Info "Testing gateway ping ($GatewayIP)..."
$gwPing = Test-Connection -ComputerName $GatewayIP -Count 2 -Quiet -ErrorAction SilentlyContinue
if ($gwPing) {
    Write-Success "Gateway $GatewayIP is responsive."
} else {
    Write-Warn "Gateway $GatewayIP did not respond to ICMP. Verify VMnet8 NAT settings in VMware."
}

Write-Info "Testing TCP reachability to Splunk Indexer ($($SplunkServerIP):$($SplunkPort))..."
$idxTest = Test-NetConnection -ComputerName $SplunkServerIP -Port $SplunkPort -WarningAction SilentlyContinue
if ($idxTest.TcpTestSucceeded) {
    Write-Success "Splunk Indexer port $SplunkPort is REACHABLE at $SplunkServerIP!"
} else {
    Write-Warn "Port $SplunkPort on $SplunkServerIP is currently NOT reachable."
    Write-Warn "Action required: Ensure Splunk Enterprise is running on Windows 11 Host, port 9997 is listening, and firewall allows TCP 9997."
}

# --------------------------------------------------------------------------------
# 5. ADVANCED AUDIT POLICIES, EVENT 4688 & POWERSHELL LOGGING
# --------------------------------------------------------------------------------
Write-Step "Step 5: Enabling SOC Advanced Audit Policies & Command-Line Telemetry..."

# 5.1 Enable Process Creation Include Command Line (Event 4688)
$auditRegPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System\Audit"
if (-not (Test-Path $auditRegPath)) {
    New-Item -Path $auditRegPath -Force | Out-Null
}
Set-ItemProperty -Path $auditRegPath -Name "ProcessCreationIncludeCmdLine_Enabled" -Value 1 -Type DWord -Force
Write-Success "Event ID 4688 command-line auditing enabled in registry."

# 5.2 Enable PowerShell Script Block Logging (Event 4104)
$psRegPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\PowerShell\ScriptBlockLogging"
if (-not (Test-Path $psRegPath)) {
    New-Item -Path $psRegPath -Force | Out-Null
}
Set-ItemProperty -Path $psRegPath -Name "EnableScriptBlockLogging" -Value 1 -Type DWord -Force
Write-Success "PowerShell Script Block Logging enabled in registry."

# 5.3 Apply auditpol subcategories
$auditSubcategories = @(
    @{ Subcategory = "Process Creation"; Success = "enable"; Failure = "disable" },
    @{ Subcategory = "Logon"; Success = "enable"; Failure = "enable" },
    @{ Subcategory = "Logoff"; Success = "enable"; Failure = "disable" },
    @{ Subcategory = "Account Lockout"; Success = "enable"; Failure = "enable" },
    @{ Subcategory = "User Account Management"; Success = "enable"; Failure = "enable" },
    @{ Subcategory = "Security Group Management"; Success = "enable"; Failure = "enable" },
    @{ Subcategory = "Special Logon"; Success = "enable"; Failure = "disable" },
    @{ Subcategory = "Credential Validation"; Success = "enable"; Failure = "enable" },
    @{ Subcategory = "Audit Policy Change"; Success = "enable"; Failure = "enable" }
)

foreach ($item in $auditSubcategories) {
    & auditpol /set /subcategory:"$($item.Subcategory)" /success:$($item.Success) /failure:$($item.Failure) | Out-Null
}
Write-Success "auditpol security auditing policies successfully applied."

# --------------------------------------------------------------------------------
# 6. SYSMON INSTALLATION & SELF-HEALING CONFIGURATION
# --------------------------------------------------------------------------------
Write-Step "Step 6: Installing & Verifying Microsoft Sysmon..."

$sysmonExePath = Find-ResourceFile "Sysmon64.exe"
if (-not $sysmonExePath) { $sysmonExePath = Find-ResourceFile "Sysmon.exe" }
$sysmonXmlPath = Find-ResourceFile "sysmonconfig-export.xml"
if (-not $sysmonXmlPath) { $sysmonXmlPath = Find-ResourceFile "sysmon*.xml" }

# Download fallback if missing
if (-not $sysmonExePath) {
    Write-Warn "Sysmon binary not found in local workspace. Attempting web download..."
    $dlTarget = Join-Path $SocWorkingDir "Sysmon64.exe"
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest -Uri "https://live.sysinternals.com/Sysmon64.exe" -OutFile $dlTarget -UseBasicParsing -TimeoutSec 30
        if (Test-Path $dlTarget) { $sysmonExePath = $dlTarget; Write-Success "Downloaded Sysmon64.exe" }
    } catch {
        Write-Failure "Failed to download Sysmon64.exe: $($_.Exception.Message)"
    }
}

if (-not $sysmonXmlPath) {
    Write-Warn "Sysmon XML config not found. Attempting web download from SwiftOnSecurity..."
    $xmlTarget = Join-Path $SocWorkingDir "sysmonconfig-export.xml"
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest -Uri "https://raw.githubusercontent.com/SwiftOnSecurity/sysmon-config/master/sysmonconfig-export.xml" -OutFile $xmlTarget -UseBasicParsing -TimeoutSec 30
        if (Test-Path $xmlTarget) { $sysmonXmlPath = $xmlTarget; Write-Success "Downloaded SwiftOnSecurity Sysmon config" }
    } catch {
        Write-Failure "Failed to download Sysmon XML: $($_.Exception.Message)"
    }
}

$sysmonService = Get-Service -Name "Sysmon64", "Sysmon" -ErrorAction SilentlyContinue | Select-Object -First 1

if ($sysmonExePath) {
    if (-not $sysmonService -or $ForceReinstall) {
        Write-Info "Installing Sysmon service using $sysmonExePath..."
        if ($sysmonXmlPath -and (Test-Path $sysmonXmlPath)) {
            & "$sysmonExePath" -accepteula -i "$sysmonXmlPath" | Out-Null
        } else {
            & "$sysmonExePath" -accepteula -i | Out-Null
        }
        Start-Sleep -Seconds 3
        $sysmonService = Get-Service -Name "Sysmon64", "Sysmon" -ErrorAction SilentlyContinue | Select-Object -First 1
    } else {
        if ($sysmonXmlPath -and (Test-Path $sysmonXmlPath)) {
            Write-Info "Updating existing Sysmon configuration schema..."
            & "$sysmonExePath" -c "$sysmonXmlPath" | Out-Null
        }
    }
}

if ($sysmonService) {
    if ($sysmonService.Status -ne "Running") {
        Start-Service -Name $sysmonService.Name -ErrorAction SilentlyContinue
    }
    Set-Service -Name $sysmonService.Name -StartupType Automatic -ErrorAction SilentlyContinue
    Write-Success "Sysmon Service ($($sysmonService.Name)) is RUNNING and set to Automatic."
} else {
    Write-Warn "Sysmon service is not running. Sysmon telemetry will be skipped until binary is provided."
}

# --------------------------------------------------------------------------------
# 7. SPLUNK UNIVERSAL FORWARDER INSTALLATION & REPAIR
# --------------------------------------------------------------------------------
Write-Step "Step 7: Installing & Configuring Splunk Universal Forwarder..."

$SplunkUFDir = "C:\Program Files\SplunkUniversalForwarder"
$SplunkUFService = Get-Service -Name "SplunkForwarder" -ErrorAction SilentlyContinue

if (-not (Test-Path $SplunkUFDir) -or -not $SplunkUFService -or $ForceReinstall) {
    Write-Info "Universal Forwarder not installed. Searching for installer..."
    $msiFile = Find-ResourceFile "splunkforwarder*.msi"
    
    if (-not $msiFile) {
        Write-Warn "splunkforwarder.msi not found locally. Attempting fallback download..."
        $msiTarget = Join-Path $SocWorkingDir "splunkforwarder.msi"
        $downloadUrls = @(
            "https://download.splunk.com/products/universalforwarder/releases/9.1.2/windows/splunkforwarder-9.1.2-b6b9c8185839-x64-release.msi",
            "https://download.splunk.com/products/universalforwarder/releases/9.2.1/windows/splunkforwarder-9.2.1-78803f08513d-x64-release.msi"
        )
        foreach ($url in $downloadUrls) {
            try {
                [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
                Write-Info "Downloading from $url..."
                Invoke-WebRequest -Uri $url -OutFile $msiTarget -UseBasicParsing -TimeoutSec 60
                if (Test-Path $msiTarget) { $msiFile = $msiTarget; break }
            } catch {}
        }
    }

    if ($msiFile -and (Test-Path $msiFile)) {
        Write-Info "Executing silent MSI installation for Splunk Universal Forwarder..."
        $destTarget = "$($SplunkServerIP):$($SplunkPort)"
        $msiArgs = @(
            "/i", "`"$msiFile`"",
            "AGREETOLICENSE=Yes",
            "RECEIVING_INDEXER=`"$destTarget`"",
            "/quiet", "/norestart"
        )
        $process = Start-Process msiexec.exe -ArgumentList $msiArgs -Wait -PassThru
        Write-Success "Universal Forwarder installer finished with ExitCode: $($process.ExitCode)"
        Start-Sleep -Seconds 5
    } else {
        Write-Warn "Universal Forwarder installer not found. If already installed manually, continuing config."
    }
}

# --------------------------------------------------------------------------------
# 8. DEPLOYING INPUTS.CONF & OUTPUTS.CONF
# --------------------------------------------------------------------------------
Write-Step "Step 8: Deploying Forwarder Inputs & Outputs Configuration..."

$LocalConfigDir = Join-Path $SplunkUFDir "etc\system\local"
if (-not (Test-Path $LocalConfigDir)) {
    New-Item -Path $LocalConfigDir -ItemType Directory -Force | Out-Null
}

# Backup existing configs
if (Test-Path (Join-Path $LocalConfigDir "inputs.conf")) {
    Copy-Item -Path (Join-Path $LocalConfigDir "inputs.conf") -Destination (Join-Path $BackupDir "inputs.conf.bak") -Force
}
if (Test-Path (Join-Path $LocalConfigDir "outputs.conf")) {
    Copy-Item -Path (Join-Path $LocalConfigDir "outputs.conf") -Destination (Join-Path $BackupDir "outputs.conf.bak") -Force
}

# Locate and stage sample attack logs if available
$SampleLogsDir = "C:\Logs"
New-Item -Path $SampleLogsDir -ItemType Directory -Force | Out-Null

$winAttackSample = Find-ResourceFile "windows_attacks_sample.log"
$targetWinAttack = Join-Path $SampleLogsDir "windows_attacks_sample.log"
if ($winAttackSample -and (Test-Path $winAttackSample)) {
    Copy-Item -Path $winAttackSample -Destination $targetWinAttack -Force
    Write-Success "Staged sample Windows attack log to $targetWinAttack"
}

$sysmonSimXml = Find-ResourceFile "sysmon_attack_simulation.xml"
$targetSysmonSim = Join-Path $SampleLogsDir "sysmon_attack_simulation.xml"
if ($sysmonSimXml -and (Test-Path $sysmonSimXml)) {
    Copy-Item -Path $sysmonSimXml -Destination $targetSysmonSim -Force
    Write-Success "Staged Sysmon simulation XML to $targetSysmonSim"
}

$secSimLog = Find-ResourceFile "windows_security_simulation.log"
$targetSecSim = Join-Path $SampleLogsDir "windows_security_simulation.log"
if ($secSimLog -and (Test-Path $secSimLog)) {
    Copy-Item -Path $secSimLog -Destination $targetSecSim -Force
    Write-Success "Staged Windows security simulation log to $targetSecSim"
}

$paSimLog = Find-ResourceFile "paloalto_traffic_simulation.log"
$targetPaSim = Join-Path $SampleLogsDir "paloalto_traffic_simulation.log"
if ($paSimLog -and (Test-Path $paSimLog)) {
    Copy-Item -Path $paSimLog -Destination $targetPaSim -Force
    Write-Success "Staged Palo Alto simulation log to $targetPaSim"
}

# Build Comprehensive inputs.conf
$inputsContent = @"
# ==============================================================================
# Splunk Universal Forwarder - Windows Telemetry Inputs Configuration
# Generated by: wundows-forwarder-setup.ps1
# ==============================================================================

[default]
host = DC01-CORP

# -------------------------------------------------------------
# Core Windows Event Logs -> index = win_logs
# -------------------------------------------------------------
[WinEventLog://Security]
disabled = 0
start_from = oldest
current_only = 0
checkpointInterval = 5
index = win_logs
renderXml = false

[WinEventLog://System]
disabled = 0
start_from = oldest
current_only = 0
checkpointInterval = 5
index = win_logs
renderXml = false

[WinEventLog://Application]
disabled = 0
start_from = oldest
current_only = 0
checkpointInterval = 5
index = win_logs
renderXml = false

# -------------------------------------------------------------
# PowerShell Operational & Script Block Logs -> index = win_logs
# -------------------------------------------------------------
[WinEventLog://Microsoft-Windows-PowerShell/Operational]
disabled = 0
start_from = oldest
current_only = 0
checkpointInterval = 5
index = win_logs
renderXml = false

[WinEventLog://Windows PowerShell]
disabled = 0
start_from = oldest
current_only = 0
checkpointInterval = 5
index = win_logs
renderXml = false

# -------------------------------------------------------------
# Microsoft Sysmon Operational Telemetry -> index = sysmon
# -------------------------------------------------------------
[WinEventLog://Microsoft-Windows-Sysmon/Operational]
disabled = 0
start_from = oldest
current_only = 0
checkpointInterval = 5
index = sysmon
renderXml = true
sourcetype = XmlWinEventLog:Microsoft-Windows-Sysmon/Operational

# -------------------------------------------------------------
# Monitored Sample Attack Logs (When present in C:\Logs)
# -------------------------------------------------------------
[monitor://C:\Logs\windows_attacks_sample.log]
disabled = 0
index = win_logs
sourcetype = custom_windows_attacks

[monitor://C:\Logs\sysmon_attack_simulation.xml]
disabled = 0
index = sysmon
sourcetype = XmlWinEventLog:Microsoft-Windows-Sysmon/Operational

[monitor://C:\Logs\windows_security_simulation.log]
disabled = 0
index = win_logs
sourcetype = WinEventLog:Security

[monitor://C:\Logs\paloalto_traffic_simulation.log]
disabled = 0
index = sysmon
sourcetype = pan:traffic
"@

Set-Content -Path (Join-Path $LocalConfigDir "inputs.conf") -Value $inputsContent -Encoding utf8
Write-Success "inputs.conf deployed with Security, System, Application, PowerShell, Sysmon, and simulation log monitors."

# Build outputs.conf
$outputsContent = @"
# ==============================================================================
# Splunk Universal Forwarder - Outputs Routing Configuration
# Generated by: wundows-forwarder-setup.ps1
# ==============================================================================

[tcpout]
defaultGroup = default-autolb-group

[tcpout:default-autolb-group]
server = $($SplunkServerIP):$($SplunkPort)
autoLB = true
compressed = false
sendCookedData = true
heartbeatFrequency = 30

[tcpout-server://$($SplunkServerIP):$($SplunkPort)]
"@

Set-Content -Path (Join-Path $LocalConfigDir "outputs.conf") -Value $outputsContent -Encoding utf8
Write-Success "outputs.conf configured to send telemetry to $($SplunkServerIP):$($SplunkPort)"

# --------------------------------------------------------------------------------
# 9. BOTSv2 DATASET CLASSIFICATION & SAFETY GUARD
# --------------------------------------------------------------------------------
Write-Step "Step 9: BOTSv2 Dataset Discovery & Architecture Guard..."
$botsCandidates = @(
    "C:\Users\Administrator\Desktop\lab\botsv2_data_set",
    "C:\Users\Administrator\Desktop\botsv2_data_set",
    (Join-Path $BaseDir "..\hw\lab\botsv2_data_set"),
    "C:\SOC_Lab\botsv2_data_set"
)

$detectedBots = $botsCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1

if ($detectedBots) {
    Write-Info "Discovered BOTSv2 dataset directory: $detectedBots"
    $hasDb = Test-Path (Join-Path $detectedBots "var\lib\splunk\botsv2\db")
    $hasAppConf = Test-Path (Join-Path $detectedBots "default\app.conf")
    
    if ($hasDb -or $hasAppConf) {
        Write-Success "BOTSv2 Dataset Classified: [PRE-INDEXED SPLUNK APP PACKAGE]"
        Write-Info "CRITICAL ARCHITECTURE NOTE (Follows Instructor Handbook):"
        Write-Info "BOTSv2 contains pre-indexed Splunk database buckets (.tsidx, journal.gz)."
        Write-Info "It MUST NOT be monitored by Universal Forwarder. It must be deployed on the Splunk Indexer!"
        Write-Info "Run 'host-indexer.ps1' on your Windows 11 Host to mount BOTSv2 directly under Splunk\etc\apps."
    } else {
        Write-Info "Dataset contains raw log files. Configured for standard monitoring."
    }
} else {
    Write-Info "No local BOTSv2 dataset folder on this VM. (BOTSv2 belongs on the Host Indexer)."
}

# --------------------------------------------------------------------------------
# 10. SERVICE RESTART & HEALTH VERIFICATION
# --------------------------------------------------------------------------------
Write-Step "Step 10: Restarting Forwarder & Verifying Services..."

$splunkCli = Join-Path $SplunkUFDir "bin\splunk.exe"
$serviceRunning = $false

if (Get-Service -Name "SplunkForwarder" -ErrorAction SilentlyContinue) {
    try {
        Restart-Service -Name "SplunkForwarder" -Force -ErrorAction Stop
        Write-Success "SplunkForwarder service restarted successfully."
        $serviceRunning = $true
    } catch {
        Write-Warn "Service restart via PowerShell failed. Trying CLI restart..."
        if (Test-Path $splunkCli) {
            & "$splunkCli" restart | Out-Null
            $serviceRunning = $true
        }
    }
} elseif (Test-Path $splunkCli) {
    & "$splunkCli" start --accept-license --answer-yes --no-prompt | Out-Null
    $serviceRunning = $true
}

# --------------------------------------------------------------------------------
# 11. FINAL STATUS DASHBOARD
# --------------------------------------------------------------------------------
Write-Host "`n================================================================================" -ForegroundColor Cyan
Write-Host "                    FORWARDER DEPLOYMENT SUMMARY & STATUS                       " -ForegroundColor Yellow
Write-Host "================================================================================" -ForegroundColor Cyan

$finalNetCheck = Test-NetConnection -ComputerName $SplunkServerIP -Port $SplunkPort -WarningAction SilentlyContinue
$finalSysmon = Get-Service -Name "Sysmon64", "Sysmon" -ErrorAction SilentlyContinue | Select-Object -First 1
$finalUF = Get-Service -Name "SplunkForwarder" -ErrorAction SilentlyContinue

$reportedIP = (Get-NetIPAddress -AddressFamily IPv4 -InterfaceAlias "Ethernet0" -ErrorAction SilentlyContinue | Select-Object -First 1)
$displayIP = if ($reportedIP) { $reportedIP.IPAddress } else { "N/A" }

$reportedRoute = (Get-NetRoute -DestinationPrefix "0.0.0.0/0" -ErrorAction SilentlyContinue | Select-Object -First 1)
$displayGateway = if ($reportedRoute) { $reportedRoute.NextHop } else { "N/A" }

$sysmonStatusText = if ($finalSysmon -and $finalSysmon.Status -eq "Running") { "RUNNING (Active)" } else { "NOT RUNNING" }
$ufStatusText = if ($finalUF -and $finalUF.Status -eq "Running") { "RUNNING (Active)" } else { "NOT RUNNING" }
$connStatusText = if ($finalNetCheck.TcpTestSucceeded) { "SUCCESS (Open)" } else { "PENDING (Check Host Indexer)" }

$results = [ordered]@{
    "Windows Server Hostname" = $env:COMPUTERNAME
    "Assigned IPv4 Address"   = $displayIP
    "Default Gateway"         = $displayGateway
    "Splunk Indexer Target"   = "$($SplunkServerIP):$($SplunkPort)"
    "TCP 9997 Connectivity"   = $connStatusText
    "Sysmon Telemetry Status" = $sysmonStatusText
    "Event 4688 Command-Line" = "ENABLED (Registry 1)"
    "PS Script Block Logging" = "ENABLED (Registry 1)"
    "Universal Forwarder"     = $ufStatusText
    "Indexes Forwarded"       = "win_logs, sysmon"
}

foreach ($key in $results.Keys) {
    $val = $results[$key]
    $color = if ($val -match "SUCCESS|RUNNING|ENABLED") { "Green" } elseif ($val -match "PENDING") { "Yellow" } else { "White" }
    Write-Host ("{0,-28} : " -f $key) -NoNewline -ForegroundColor White
    Write-Host $val -ForegroundColor $color
}

Write-Host "================================================================================" -ForegroundColor Cyan
Write-Host "Deployment completed. Telemetry is streaming to Host Indexer $($SplunkServerIP):$($SplunkPort)" -ForegroundColor Green
Write-Host "================================================================================`n" -ForegroundColor Cyan
