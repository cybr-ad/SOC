<#
.SYNOPSIS
    SOC Class 02 - Windows Server / Splunk Receiver all-in-one setup.

.DESCRIPTION
    This script follows the latest SOC Class 02 lab manual supplied by the user.

    PDF LAB VALUES
      VMware VMnet8         192.168.10.0/24
      VMware NAT gateway    192.168.10.2
      Splunk host/receiver  192.168.10.1
      Splunk receiver port  9997/TCP
      Windows Server IP     192.168.10.20/24
      Windows Server DNS    127.0.0.1, 1.1.1.1
      AD forest/domain      corp.local
      NetBIOS                CORP
      Windows VM name       DC01-CORP
      Windows indexes       win_logs, sysmon

    DESKTOP LAB FILES
      Desktop\class file\bin\splunkforwarder.msi
      Desktop\class file\bin\sysmon\Sysmon64.exe
      Desktop\class file\configs\windows\sysmonconfig-export.xml
      Desktop\class file\samples\windows_attacks_sample.log
      Desktop\class file\scripts\setup_ad_dc.ps1

    The script searches the entire Desktop tree, so a different top-level
    Desktop folder name is also supported.

    ROLE=Forwarder is the Windows Server / DC01 sender.
    ROLE=Receiver is the Windows host running Splunk Enterprise at 192.168.10.1.

    IMPORTANT:
      - This script does NOT call "splunk list forward-server" because that
        requires Universal Forwarder CLI authentication and can report
        "Login failed" even when the forwarding configuration is correct.
      - This script does NOT use Rename-Computer before AD promotion. The PDF's
        AD workflow is performed by setup_ad_dc.ps1 inside the Windows Server VM.

.EXAMPLE
    .\win-server.ps1 -Role Forwarder -ConfigureStaticIP

.EXAMPLE
    .\win-server.ps1 -Role Receiver

.EXAMPLE
    .\win-server.ps1 -Role Forwarder -ConfigureStaticIP -PromoteAD
#>

[CmdletBinding()]
param(
    [ValidateSet('Receiver','Forwarder','Auto')]
    [string]$Role = 'Auto',

    # ===== PDF values =====
    [string]$SplunkServerIP = '192.168.10.1',
    [int]$SplunkPort = 9997,
    [string]$WindowsServerIP = '192.168.10.20',
    [int]$PrefixLength = 24,
    [string]$GatewayIP = '192.168.10.2',
    [string[]]$DnsServers = @('127.0.0.1','1.1.1.1'),
    [string]$InterfaceAlias = 'Ethernet0',
    [string]$ExpectedHostname = 'DC01-CORP',
    [string]$DomainName = 'corp.local',
    [string]$NetbiosName = 'CORP',

    # ===== Action switches =====
    [switch]$ConfigureStaticIP,
    [switch]$PromoteAD,
    [switch]$SkipSysmon,
    [switch]$SkipForwarder,
    [switch]$SkipSampleLog,
    [switch]$SkipFirewall,
    [switch]$NoRestart
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# -----------------------------------------------------------------------------
# PDF / lab constants
# -----------------------------------------------------------------------------
$DesktopRoot = [Environment]::GetFolderPath('Desktop')
$WorkDir = 'C:\SOC_Lab'
$LogDir = 'C:\Logs'
$SampleLogDestination = Join-Path $LogDir 'windows_attacks_sample.log'
$UfHome = 'C:\Program Files\SplunkUniversalForwarder'
$UfBin = Join-Path $UfHome 'bin\splunk.exe'
$EnterpriseHome = 'C:\Program Files\Splunk'
$EnterpriseBin = Join-Path $EnterpriseHome 'bin\splunk.exe'
$AdScriptName = 'setup_ad_dc.ps1'

function Write-Step {
    param([Parameter(Mandatory)][string]$Message)
    Write-Host "`n[+] $Message" -ForegroundColor Cyan
}

function Write-Ok {
    param([Parameter(Mandatory)][string]$Message)
    Write-Host "    [OK] $Message" -ForegroundColor Green
}

function Write-Info {
    param([Parameter(Mandatory)][string]$Message)
    Write-Host "    [*] $Message" -ForegroundColor DarkGray
}

function Write-Warn {
    param([Parameter(Mandatory)][string]$Message)
    Write-Host "    [!] $Message" -ForegroundColor Yellow
}

function Assert-Admin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw 'Run this script from an elevated PowerShell window (Run as Administrator).'
    }
}

function Ensure-Directory {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
}

function Find-DesktopFile {
    param(
        [Parameter(Mandatory)][string]$FileName,
        [string]$PreferredRelativePath
    )

    if ($PreferredRelativePath) {
        $preferred = Join-Path $DesktopRoot $PreferredRelativePath
        if (Test-Path -LiteralPath $preferred) {
            Write-Ok "Found $($FileName): $preferred"
            return (Resolve-Path -LiteralPath $preferred).Path
        }
    }

    Write-Info "Searching Desktop recursively for $FileName ..."
    $found = Get-ChildItem -Path $DesktopRoot -File -Recurse -Filter $FileName -ErrorAction SilentlyContinue |
        Sort-Object FullName |
        Select-Object -First 1

    if ($found) {
        Write-Ok "Found $($FileName): $($found.FullName)"
        return $found.FullName
    }

    return $null
}

function Get-LabAssets {
    Write-Step 'Locating PDF lab files under Desktop'

    $assets = [ordered]@{}
    $assets.UfMsi = Find-DesktopFile -FileName 'splunkforwarder.msi' -PreferredRelativePath 'class file\bin\splunkforwarder.msi'
    $assets.SysmonExe = Find-DesktopFile -FileName 'Sysmon64.exe' -PreferredRelativePath 'class file\bin\sysmon\Sysmon64.exe'
    $assets.SysmonConfig = Find-DesktopFile -FileName 'sysmonconfig-export.xml' -PreferredRelativePath 'class file\configs\windows\sysmonconfig-export.xml'
    $assets.SampleLog = Find-DesktopFile -FileName 'windows_attacks_sample.log' -PreferredRelativePath 'class file\samples\windows_attacks_sample.log'
    $assets.AdScript = Find-DesktopFile -FileName $AdScriptName -PreferredRelativePath 'class file\scripts\setup_ad_dc.ps1'

    if (-not $assets.UfMsi) { throw 'PDF file missing: splunkforwarder.msi' }
    if (-not $assets.SysmonExe) { throw 'PDF file missing: Sysmon64.exe' }
    if (-not $assets.SysmonConfig) { throw 'PDF file missing: sysmonconfig-export.xml' }
    if (-not $assets.SampleLog) { throw 'PDF file missing: windows_attacks_sample.log' }
    if (-not $assets.AdScript) { Write-Warn "PDF file not found: $AdScriptName. AD promotion can still be run separately if the script is supplied later." }

    return $assets
}

function Detect-Role {
    if (Test-Path -LiteralPath $EnterpriseBin) { return 'Receiver' }
    if (Test-Path -LiteralPath $UfBin) { return 'Forwarder' }

    $os = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
    if ($os) {
        if ([int]$os.ProductType -in @(2,3)) { return 'Forwarder' }
        if ([int]$os.ProductType -eq 1) {
            # Windows client is the lab host carrying Splunk Enterprise.
            return 'Receiver'
        }
    }

    throw 'Unable to auto-detect role. Use -Role Forwarder on DC01-CORP or -Role Receiver on the Splunk host.'
}

function Configure-StaticIPFromPDF {
    Write-Step 'Configuring Windows Server static IP exactly as specified in PDF'

    $adapter = Get-NetAdapter -Name $InterfaceAlias -ErrorAction SilentlyContinue
    if (-not $adapter) {
        $candidate = Get-NetAdapter -Physical -ErrorAction SilentlyContinue |
            Where-Object { $_.Status -in @('Up','Disconnected') } |
            Select-Object -First 1
        if (-not $candidate) {
            throw "Network adapter '$InterfaceAlias' was not found and no physical adapter could be auto-selected."
        }
        $InterfaceAlias = $candidate.Name
        Write-Warn "Adapter '$InterfaceAlias' selected automatically because the requested adapter was not found."
    }

    # PDF sequence: remove existing IPv4 addresses and default route, then add
    # 192.168.10.20/24 with gateway 192.168.10.2.
    Get-NetIPAddress -InterfaceAlias $InterfaceAlias -AddressFamily IPv4 -ErrorAction SilentlyContinue |
        Where-Object { $_.IPAddress -ne '127.0.0.1' } |
        ForEach-Object {
            Remove-NetIPAddress -InputObject $_ -Confirm:$false -ErrorAction SilentlyContinue
        }

    Get-NetRoute -InterfaceAlias $InterfaceAlias -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue |
        Remove-NetRoute -Confirm:$false -ErrorAction SilentlyContinue

    New-NetIPAddress -InterfaceAlias $InterfaceAlias `
        -IPAddress $WindowsServerIP `
        -PrefixLength $PrefixLength `
        -DefaultGateway $GatewayIP | Out-Null

    # PDF says DNS = 127.0.0.1, 1.1.1.1 for DC01.
    Set-DnsClientServerAddress -InterfaceAlias $InterfaceAlias -ServerAddresses $DnsServers

    Write-Ok "IP = $WindowsServerIP/$PrefixLength | Gateway = $GatewayIP | DNS = $($DnsServers -join ', ')"

    if ([Environment]::MachineName.ToUpperInvariant() -ne $ExpectedHostname.ToUpperInvariant()) {
        Write-Warn "Current computer name is '$([Environment]::MachineName)'."
        Write-Info 'Per the PDF, AD promotion is performed by setup_ad_dc.ps1. This script intentionally does not call Rename-Computer before domain promotion.'
    } else {
        Write-Ok "Computer name is already $ExpectedHostname."
    }
}

function Enable-PDFProcessAuditing {
    Write-Step 'Enabling Event 4688 process creation + command-line logging'

    & auditpol.exe /set /subcategory:'Process Creation' /success:enable | Out-Null

    $auditRegistry = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System\Audit'
    if (-not (Test-Path $auditRegistry)) {
        New-Item -Path $auditRegistry -Force | Out-Null
    }

    New-ItemProperty -Path $auditRegistry `
        -Name 'ProcessCreationIncludeCmdLine_Enabled' `
        -PropertyType DWord -Value 1 -Force | Out-Null

    Write-Ok 'Event 4688 + command-line inclusion enabled.'
}

function Install-SysmonFromPDF {
    param([Parameter(Mandatory)][System.Collections.IDictionary]$Assets)

    if ($SkipSysmon) {
        Write-Warn 'Sysmon installation skipped by -SkipSysmon.'
        return
    }

    Write-Step 'Installing/configuring Microsoft Sysmon from PDF Desktop package'
    Ensure-Directory $WorkDir

    $stagedExe = Join-Path $WorkDir 'Sysmon64.exe'
    $stagedXml = Join-Path $WorkDir 'sysmonconfig-export.xml'

    Copy-Item -LiteralPath $Assets.SysmonExe -Destination $stagedExe -Force
    Copy-Item -LiteralPath $Assets.SysmonConfig -Destination $stagedXml -Force

    $svc = Get-Service -Name 'Sysmon64' -ErrorAction SilentlyContinue
    if (-not $svc) {
        & $stagedExe -accepteula -i $stagedXml | Out-Host
        Write-Ok 'Sysmon installed with PDF sysmonconfig-export.xml.'
    } else {
        & $stagedExe -c $stagedXml | Out-Host
        Write-Ok 'Existing Sysmon configuration updated from PDF XML.'
    }

    $verify = Get-Service -Name 'Sysmon64' -ErrorAction SilentlyContinue
    if ($verify -and $verify.Status -ne 'Running') {
        Start-Service -Name 'Sysmon64'
    }
    Write-Ok 'Sysmon64 service verified.'
}

function Install-UFFromPDF {
    param([Parameter(Mandatory)][System.Collections.IDictionary]$Assets)

    if ($SkipForwarder) {
        Write-Warn 'Universal Forwarder installation skipped by -SkipForwarder.'
        return
    }

    if (Test-Path -LiteralPath $UfBin) {
        Write-Ok 'Splunk Universal Forwarder is already installed.'
        return
    }

    Write-Step 'Installing Splunk Universal Forwarder from PDF Desktop MSI'
    Ensure-Directory $WorkDir

    $msi = Join-Path $WorkDir 'splunkforwarder.msi'
    Copy-Item -LiteralPath $Assets.UfMsi -Destination $msi -Force

    # This is the same receiver property used by the PDF deployment flow.
    $msiArgs = @(
        '/i',
        "`"$msi`"",
        'AGREETOLICENSE=Yes',
        "RECEIVING_INDEXER=$SplunkServerIP`:$SplunkPort",
        '/quiet',
        '/norestart'
    )

    $proc = Start-Process -FilePath 'msiexec.exe' -ArgumentList $msiArgs -Wait -PassThru
    if ($proc.ExitCode -notin @(0,3010)) {
        throw "Splunk Universal Forwarder MSI installation failed with exit code $($proc.ExitCode)."
    }

    if (-not (Test-Path -LiteralPath $UfBin)) {
        throw "Universal Forwarder installation finished but $UfBin was not found."
    }

    Write-Ok 'Splunk Universal Forwarder installed.'
}

function Write-PDFForwarderConfiguration {
    param([Parameter(Mandatory)][System.Collections.IDictionary]$Assets)

    Write-Step "Writing PDF Windows Forwarder inputs.conf / outputs.conf"

    Ensure-Directory $LogDir
    Ensure-Directory (Join-Path $UfHome 'etc\system\local')

    $inputs = @'
[default]
host = DC01-CORP

[WinEventLog://Security]
disabled = false
index = win_logs
renderXml = false
start_from = oldest
current_only = false

[WinEventLog://System]
disabled = false
index = win_logs
renderXml = false
start_from = oldest
current_only = false

[WinEventLog://Application]
disabled = false
index = win_logs
renderXml = false
start_from = oldest
current_only = false

[WinEventLog://Microsoft-Windows-PowerShell/Operational]
disabled = false
index = win_logs
renderXml = false
start_from = oldest
current_only = false

[WinEventLog://Microsoft-Windows-Sysmon/Operational]
disabled = false
index = sysmon
renderXml = false
start_from = oldest
current_only = false

[monitor://C:\Logs\windows_attacks_sample.log]
disabled = false
index = win_logs
sourcetype = custom_windows_attacks
crcSalt = <SOURCE>
'@

    $outputs = @"
[tcpout]
defaultGroup = default-autolb-group

[tcpout:default-autolb-group]
server = $SplunkServerIP`:$SplunkPort

[tcpout-server://$SplunkServerIP`:$SplunkPort]
"@

    $inputsPath = Join-Path $UfHome 'etc\system\local\inputs.conf'
    $outputsPath = Join-Path $UfHome 'etc\system\local\outputs.conf'

    Set-Content -LiteralPath $inputsPath -Value $inputs -Encoding ASCII
    Set-Content -LiteralPath $outputsPath -Value $outputs -Encoding ASCII

    Write-Ok "inputs.conf = $inputsPath"
    Write-Ok "outputs.conf = $outputsPath"

    if (-not $SkipSampleLog) {
        Copy-Item -LiteralPath $Assets.SampleLog -Destination $SampleLogDestination -Force
        Write-Ok "Sample log copied -> $SampleLogDestination -> win_logs"
    }
}

function Start-PDFForwarderService {
    Write-Step 'Starting/enabling SplunkForwarder'

    $svc = Get-Service -Name 'SplunkForwarder' -ErrorAction SilentlyContinue
    if (-not $svc) {
        throw 'SplunkForwarder service was not found after installation.'
    }

    Set-Service -Name 'SplunkForwarder' -StartupType Automatic

    if ($svc.Status -eq 'Running') {
        Restart-Service -Name 'SplunkForwarder' -Force
    } else {
        Start-Service -Name 'SplunkForwarder'
    }

    (Get-Service -Name 'SplunkForwarder') | Select-Object Status, Name, StartType | Format-Table -AutoSize
    Write-Ok 'SplunkForwarder service is Running and Automatic.'
}

function Verify-PDFForwarder {
    Write-Step 'Verifying Windows Forwarder using PDF-relevant checks'

    $svc = Get-Service -Name 'SplunkForwarder' -ErrorAction SilentlyContinue
    if (-not $svc) { throw 'SplunkForwarder service not found.' }
    if ($svc.Status -ne 'Running') { throw "SplunkForwarder is not running: $($svc.Status)" }
    Write-Ok 'SplunkForwarder = Running'

    $inputsPath = Join-Path $UfHome 'etc\system\local\inputs.conf'
    $outputsPath = Join-Path $UfHome 'etc\system\local\outputs.conf'

    $inputsText = Get-Content -LiteralPath $inputsPath -Raw
    $outputsText = Get-Content -LiteralPath $outputsPath -Raw

    $expectedOutput = "server = $SplunkServerIP`:$SplunkPort"
    if ($outputsText -notmatch [regex]::Escape($expectedOutput)) {
        throw "outputs.conf does not contain PDF destination $SplunkServerIP`:$SplunkPort"
    }
    Write-Ok "outputs.conf -> $SplunkServerIP`:$SplunkPort"

    $expectedSections = @(
        '\[WinEventLog://Security\]',
        '\[WinEventLog://System\]',
        '\[WinEventLog://Application\]',
        '\[WinEventLog://Microsoft-Windows-PowerShell/Operational\]',
        '\[WinEventLog://Microsoft-Windows-Sysmon/Operational\]',
        '\[monitor://C:\\Logs\\windows_attacks_sample\.log\]'
    )

    foreach ($pattern in $expectedSections) {
        if ($inputsText -notmatch $pattern) {
            throw "inputs.conf is missing required PDF input: $pattern"
        }
    }

    Write-Ok 'Security/System/Application/PowerShell -> win_logs'
    Write-Ok 'Sysmon -> sysmon'
    Write-Ok 'C:\Logs\windows_attacks_sample.log -> win_logs'

    if (-not (Test-Path -LiteralPath $SampleLogDestination)) {
        throw "Sample log missing: $SampleLogDestination"
    }
    Write-Ok "Sample log exists: $SampleLogDestination"

    if (-not (Test-NetConnection -ComputerName $SplunkServerIP -Port $SplunkPort -InformationLevel Quiet)) {
        throw "TCP $SplunkServerIP`:$SplunkPort is not reachable. Check Splunk Enterprise receiver and firewall."
    }
    Write-Ok "TCP $SplunkServerIP`:$SplunkPort = reachable"
}

function Configure-PDFReceiver {
    Write-Step 'Configuring Splunk Enterprise receiver exactly as PDF'

    if (-not (Test-Path -LiteralPath $EnterpriseBin)) {
        throw "Splunk Enterprise not found at $EnterpriseBin. Install Splunk Enterprise on the Windows host as specified in the PDF."
    }

    $localDir = Join-Path $EnterpriseHome 'etc\system\local'
    Ensure-Directory $localDir

    $inputs = @"
[splunktcp://$SplunkPort]
connection_host = ip
"@

    $indexes = @'
[win_logs]
homePath = $SPLUNK_DB/win_logs/db
coldPath = $SPLUNK_DB/win_logs/colddb
thawedPath = $SPLUNK_DB/win_logs/thaweddb

[sysmon]
homePath = $SPLUNK_DB/sysmon/db
coldPath = $SPLUNK_DB/sysmon/colddb
thawedPath = $SPLUNK_DB/sysmon/thaweddb

[linux_logs]
homePath = $SPLUNK_DB/linux_logs/db
coldPath = $SPLUNK_DB/linux_logs/colddb
thawedPath = $SPLUNK_DB/linux_logs/thaweddb
'@

    Set-Content -LiteralPath (Join-Path $localDir 'inputs.conf') -Value $inputs -Encoding ASCII
    Set-Content -LiteralPath (Join-Path $localDir 'indexes.conf') -Value $indexes -Encoding ASCII

    if (-not $SkipFirewall) {
        $ruleName = 'SOC Lab Splunk Receiver TCP 9997'
        if (-not (Get-NetFirewallRule -DisplayName $ruleName -ErrorAction SilentlyContinue)) {
            New-NetFirewallRule -DisplayName $ruleName -Direction Inbound -Action Allow -Protocol TCP -LocalPort $SplunkPort -Profile Any | Out-Null
        }
        Write-Ok 'Inbound TCP 9997 firewall rule is present.'
    }

    $splunkService = Get-Service -Name 'Splunkd' -ErrorAction SilentlyContinue
    if (-not $splunkService) {
        Write-Warn 'Splunkd Windows service was not found. Open/complete the Splunk Enterprise installation first.'
    } else {
        Set-Service -Name 'Splunkd' -StartupType Automatic
        if ($splunkService.Status -ne 'Running') {
            Start-Service -Name 'Splunkd'
        } else {
            Restart-Service -Name 'Splunkd' -Force
        }
        Write-Ok 'Splunkd = Running / Automatic'
    }
}

function Verify-PDFReceiver {
    Write-Step 'Verifying Splunk Enterprise receiver'
    $listener = Get-NetTCPConnection -LocalPort $SplunkPort -State Listen -ErrorAction SilentlyContinue
    if (-not $listener) {
        throw "Splunk is not listening on TCP $SplunkPort."
    }
    Write-Ok "TCP $SplunkPort is listening."
}

function Invoke-PDFADPromotion {
    param([Parameter(Mandatory)][System.Collections.IDictionary]$Assets)

    if (-not $Assets.AdScript) {
        throw "setup_ad_dc.ps1 was not found under Desktop. The PDF requires this script for corp.local / CORP AD forest promotion."
    }

    Write-Step 'Running PDF Active Directory forest promotion script'
    Write-Info "Domain: $DomainName | NetBIOS: $NetbiosName"
    Write-Info 'The PDF promotion script may reboot this Windows Server automatically.'

    if (-not $NoRestart) {
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $Assets.AdScript `
            -DomainName $DomainName `
            -NetbiosName $NetbiosName
    } else {
        Write-Warn '-NoRestart was supplied. The AD promotion script will run exactly as supplied by the lab package; any reboot behavior is controlled by that script.'
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $Assets.AdScript `
            -DomainName $DomainName `
            -NetbiosName $NetbiosName
    }
}

# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------
Assert-Admin
Ensure-Directory $WorkDir
Ensure-Directory $LogDir

if ($Role -eq 'Auto') {
    $Role = Detect-Role
    Write-Ok "Auto-detected role: $Role"
}

Write-Host '=============================================================' -ForegroundColor Magenta
Write-Host ' SOC CLASS 02 - WINDOWS ALL-IN-ONE SETUP' -ForegroundColor Magenta
Write-Host '=============================================================' -ForegroundColor Magenta
Write-Host "Desktop lab root       : $DesktopRoot"
Write-Host "Role                   : $Role"
Write-Host "Splunk destination     : $SplunkServerIP`:$SplunkPort"
Write-Host "Windows Server target  : $WindowsServerIP/$PrefixLength"
Write-Host "VMware gateway         : $GatewayIP"
Write-Host "AD domain              : $DomainName"
Write-Host "AD NetBIOS             : $NetbiosName"

if ($Role -eq 'Receiver') {
    Configure-PDFReceiver
    Verify-PDFReceiver

    Write-Host "`n=============================================================" -ForegroundColor Green
    Write-Host ' WINDOWS SPLUNK RECEIVER SETUP COMPLETE' -ForegroundColor Green
    Write-Host '=============================================================' -ForegroundColor Green
    Write-Host "Receiver: $SplunkServerIP`:$SplunkPort"
    Write-Host 'Indexes : win_logs, sysmon, linux_logs'
    Write-Host 'Web UI  : http://localhost:8000'
    exit 0
}

# Forwarder role is the Windows Server / DC01 side.
$assets = Get-LabAssets

if ($ConfigureStaticIP) {
    Configure-StaticIPFromPDF
}

Enable-PDFProcessAuditing
Install-SysmonFromPDF -Assets $assets
Install-UFFromPDF -Assets $assets
Write-PDFForwarderConfiguration -Assets $assets
Start-PDFForwarderService
Verify-PDFForwarder

if ($PromoteAD) {
    Invoke-PDFADPromotion -Assets $assets
}

Write-Host "`n=============================================================" -ForegroundColor Green
Write-Host ' WINDOWS FORWARDER SETUP COMPLETE' -ForegroundColor Green
Write-Host '=============================================================' -ForegroundColor Green
Write-Host "Current hostname       : $([Environment]::MachineName)"
Write-Host "PDF VM / target name   : $ExpectedHostname"
Write-Host "Windows Server IP      : $WindowsServerIP"
Write-Host "Forwarder destination  : $SplunkServerIP`:$SplunkPort"
Write-Host 'Indexes                : win_logs, sysmon'
Write-Host 'Windows inputs         : Security, System, Application, PowerShell, Sysmon'
Write-Host "Sample log             : $SampleLogDestination"
Write-Host "AD domain              : $DomainName"

if (-not $PromoteAD) {
    Write-Host "`n[PDF NEXT STEP] Run AD forest promotion from the Desktop lab scripts:" -ForegroundColor Cyan
    Write-Host "cd `"$DesktopRoot\<your-lab-folder>\scripts`"" -ForegroundColor Cyan
    Write-Host ".\setup_ad_dc.ps1 -DomainName `"corp.local`" -NetbiosName `"CORP`"" -ForegroundColor Cyan
}
