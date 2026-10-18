<# : batch part first, PowerShell part below
@echo off
rem Tunes an old Windows 10/11 laptop (dual or quad core, 4 to 8 GB RAM,
rem Intel graphics with or without a small NVIDIA chip) for light gaming and
rem everyday use: less background load and fewer redraws, while sound, webcam,
rem Bluetooth, Wi-Fi, printing and Windows Update keep working.
rem Run as administrator, then restart Windows.
net session >nul 2>&1
if errorlevel 1 (
    echo Asking for administrator rights...
    powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)
powershell -NoProfile -ExecutionPolicy Bypass -Command "iex ([IO.File]::ReadAllText('%~f0'))"
echo.
pause
exit /b
#>

# ---------------------------------------------------------------------------
# Settings
# ---------------------------------------------------------------------------

# Windows Search indexing: 'auto' turns it off only when Windows runs from a
# hard disk, where indexing competes with games for disk time. Start menu
# search still finds apps and settings without it. $true or $false to force.
$DisableWindowsSearch = 'auto'

# High performance power plan: faster, but hotter and shorter on battery.
# Default $false keeps Balanced; switch plans by hand when gaming on the charger.
$UseHighPerformancePlan = $false

# WSL 2 memory cap in GB. WSL 2 takes up to half of RAM by default, which
# starves Windows on a small laptop. 0 means a quarter of RAM, at least 1 GB.
# Only written when %USERPROFILE%\.wslconfig does not exist yet.
$WslMemoryGB = 0

# ---------------------------------------------------------------------------

$ErrorActionPreference = 'Stop'
$restartNeeded = $false

function Step($name, [scriptblock]$action) {
    try {
        $result = & $action
        if ($result -is [string]) {
            Write-Host "[SKIP] ${name}: $result" -ForegroundColor Yellow
        }
        else {
            Write-Host "[ OK ] $name" -ForegroundColor Green
        }
    }
    catch {
        Write-Host "[FAIL] ${name}: $($_.Exception.Message)" -ForegroundColor Red
    }
}

function Set-Dword($path, $name, $value) {
    if (-not (Test-Path $path)) {
        New-Item -Path $path -Force | Out-Null
    }
    New-ItemProperty -Path $path -Name $name -Value $value -PropertyType DWord -Force | Out-Null
}

function Set-String($path, $name, $value) {
    if (-not (Test-Path $path)) {
        New-Item -Path $path -Force | Out-Null
    }
    New-ItemProperty -Path $path -Name $name -Value $value -PropertyType String -Force | Out-Null
}

$os = Get-CimInstance Win32_OperatingSystem
$isWindows11 = [int]$os.BuildNumber -ge 22000
$ramGB = [math]::Round($os.TotalVisibleMemorySize / 1MB, 1)
try {
    $systemDisk = Get-Partition -DriveLetter $env:SystemDrive.Substring(0, 1) | Get-Disk
    $mediaType = (Get-PhysicalDisk | Where-Object { $_.DeviceId -eq [string]$systemDisk.Number }).MediaType
}
catch {
    $mediaType = $null
}
$onHdd = $mediaType -eq 'HDD'

Write-Host ("Tuning {0} (build {1}), {2} GB RAM, system disk: {3}" -f `
    $os.Caption, $os.BuildNumber, $ramGB, $(if ($mediaType) { $mediaType } else { 'unknown type' }))
Write-Host ""

# Memory compression only works when RAM runs short: it squeezes idle pages in
# RAM instead of writing them to the page file. Reading a page back from a hard
# disk takes milliseconds; decompressing it takes microseconds of CPU. On a small
# laptop that trade favours compression, games included.
Step "Memory compression on" {
    if ((Get-MMAgent).MemoryCompression) {
        return 'already on'
    }
    Enable-MMAgent -MemoryCompression
    $global:restartNeeded = $true
}

Step "Page file managed by Windows" {
    $computer = Get-CimInstance Win32_ComputerSystem
    if ($computer.AutomaticManagedPagefile -or @(Get-CimInstance Win32_PageFileSetting).Count) {
        return 'a page file is already set up'
    }
    Set-CimInstance -InputObject $computer -Property @{ AutomaticManagedPagefile = $true }
    $global:restartNeeded = $true
}

Step "Game Mode on; Game Bar background recording off" {
    Set-Dword 'HKCU:\Software\Microsoft\GameBar' AutoGameModeEnabled 1
    Set-Dword 'HKCU:\System\GameConfigStore' GameDVR_Enabled 0
    Set-Dword 'HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR' AppCaptureEnabled 0
    Set-Dword 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR' AllowGameDVR 0
}

Step "No window animations or transparency (fewer redraws on the Intel GPU)" {
    Set-String 'HKCU:\Control Panel\Desktop\WindowMetrics' MinAnimate '0'
    Set-Dword 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' TaskbarAnimations 0
    Set-Dword 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' EnableTransparency 0
}

Step "Store apps do not run in the background" {
    Set-Dword 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy' LetAppsRunInBackground 2
}

Step "No suggested apps, tips or web results in Start" {
    $cdm = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'
    Set-Dword $cdm SilentInstalledAppsEnabled 0
    Set-Dword $cdm SystemPaneSuggestionsEnabled 0
    Set-Dword $cdm SoftLandingEnabled 0
    Set-Dword 'HKCU:\Software\Policies\Microsoft\Windows\Explorer' DisableSearchBoxSuggestions 1
}

Step "No news and interests / widgets" {
    if ($isWindows11) {
        Set-Dword 'HKLM:\SOFTWARE\Policies\Microsoft\Dsh' AllowNewsAndInterests 0
    }
    else {
        Set-Dword 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Feeds' EnableFeeds 0
    }
}

Step "Diagnostic data at the required minimum" {
    Set-Dword 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection' AllowTelemetry 1
}

Step "Windows Update does not upload to other PCs" {
    Set-Dword 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization' DODownloadMode 0
}

Step "Defender: scans at low priority, at most 20% CPU" {
    if (-not (Get-Command Set-MpPreference -ErrorAction SilentlyContinue)) {
        return 'Defender is not installed'
    }
    Set-MpPreference -ScanAvgCPULoadFactor 20
    if ((Get-Command Set-MpPreference).Parameters.ContainsKey('EnableLowCpuPriority')) {
        Set-MpPreference -EnableLowCpuPriority $true
    }
}

# Hardware acceleration stays on: unlike a VM, this machine has a real GPU.
Step "Browsers: sleeping tabs / Memory Saver, no running in the background" {
    $edge = 'HKLM:\SOFTWARE\Policies\Microsoft\Edge'
    Set-Dword $edge SleepingTabsEnabled 1
    Set-Dword $edge SleepingTabsTimeout 300
    Set-Dword $edge StartupBoostEnabled 0
    Set-Dword $edge BackgroundModeEnabled 0
    foreach ($chromium in 'HKLM:\SOFTWARE\Policies\Google\Chrome', 'HKLM:\SOFTWARE\Policies\BraveSoftware\Brave') {
        Set-Dword $chromium HighEfficiencyModeEnabled 1
        Set-Dword $chromium BackgroundModeEnabled 0
    }
}

Step "Windows Search indexing off" {
    $off = if ($DisableWindowsSearch -eq 'auto') { $onHdd } else { [bool]$DisableWindowsSearch }
    if (-not $off) {
        return 'kept on (system disk is not a hard disk; see settings at the top)'
    }
    Stop-Service WSearch -Force -ErrorAction SilentlyContinue
    Set-Service WSearch -StartupType Disabled
}

Step "High performance power plan" {
    if (-not $UseHighPerformancePlan) {
        return 'kept Balanced (better on battery; see settings at the top)'
    }
    cmd /c "powercfg /setactive SCHEME_MIN >nul 2>&1"
    if ($LASTEXITCODE) { throw 'powercfg could not switch the plan' }
}

Step "WSL 2 memory cap" {
    if (-not (Get-Command wsl.exe -ErrorAction SilentlyContinue)) {
        return 'WSL is not installed'
    }
    $config = Join-Path $env:USERPROFILE '.wslconfig'
    if (Test-Path $config) {
        return "$config already exists, left as is"
    }
    $gb = if ($WslMemoryGB -gt 0) { $WslMemoryGB } else { [math]::Max(1, [math]::Floor($ramGB / 4)) }
    $lines = @(
        '[wsl2]'
        "memory=${gb}GB"
        ''
        '[experimental]'
        'autoMemoryReclaim=gradual'
    )
    Set-Content -Path $config -Value $lines -Encoding ASCII
    Write-Host "       memory=${gb}GB in $config; applies after: wsl --shutdown"
}

Write-Host ""
Write-Host "Programs that start at logon (turn off what you do not need in"
Write-Host "Task Manager > Startup apps):"
Get-CimInstance Win32_StartupCommand | Sort-Object Name |
    Format-Table Name, User, Location -AutoSize | Out-Host

Write-Host "Largest processes now:"
Get-Process | Sort-Object WorkingSet64 -Descending | Select-Object -First 10 |
    Format-Table Name, @{ n = 'MB'; e = { [int]($_.WorkingSet64 / 1MB) } } -AutoSize | Out-Host

if ($restartNeeded) {
    Write-Host "Restart Windows to apply the page file and memory compression." -ForegroundColor Cyan
}
Write-Host "Sign out and back in for the animation and Start menu settings; restart the browsers."
