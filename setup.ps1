#Requires -RunAsAdministrator
<#
.SYNOPSIS
    One-Touch Windows Setup - Main Orchestrator
.DESCRIPTION
    Reads config.json and orchestrates the entire setup process:
    installs apps, dev tools, fonts, VS Code extensions, and applies Windows settings.
    Supports interactive mode for selective installation.
.NOTES
    Run via setup.bat for automatic admin elevation.
#>

param(
    [switch]$DryRun,
    [switch]$SkipApps,
    [switch]$SkipSettings,
    [switch]$SkipDevTools,
    [switch]$ForceReinstall,
    [switch]$InstallAll,
    [string]$LogFile
)

# ── Globals ──────────────────────────────────────────────────────────────────
$ErrorActionPreference = "Continue"
$ScriptRoot = $PSScriptRoot
$Timestamp  = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
$LogDir     = Join-Path $ScriptRoot "logs"
if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Path $LogDir -Force | Out-Null }
if (-not $LogFile) {
    $LogFile = Join-Path $LogDir "setup-log-$Timestamp.txt"
}

# ── Counters ─────────────────────────────────────────────────────────────────
$script:Installed = 0
$script:Skipped   = 0
$script:Failed    = 0

# ── Logging ──────────────────────────────────────────────────────────────────
function Write-Log {
    param(
        [string]$Message,
        [ValidateSet("INFO","WARN","ERROR","SUCCESS","HEADER")]
        [string]$Level = "INFO"
    )

    $colors = @{
        "INFO"    = "White"
        "WARN"    = "Yellow"
        "ERROR"   = "Red"
        "SUCCESS" = "Green"
        "HEADER"  = "Cyan"
    }

    $prefix = switch ($Level) {
        "INFO"    { "[i]" }
        "WARN"    { "[!]" }
        "ERROR"   { "[X]" }
        "SUCCESS" { "[OK]" }
        "HEADER"  { "[>>]" }
    }

    $logLine = "$(Get-Date -Format 'HH:mm:ss') $prefix $Message"
    Write-Host $logLine -ForegroundColor $colors[$Level]
    Add-Content -Path $LogFile -Value $logLine
}

function Write-Section {
    param([string]$Title)
    $separator = "=" * 60
    Write-Log "" "INFO"
    Write-Log $separator "HEADER"
    Write-Log "  $Title" "HEADER"
    Write-Log $separator "HEADER"
    Write-Log "" "INFO"
}

# ── Load Config ──────────────────────────────────────────────────────────────
$configPath = Join-Path $ScriptRoot "config.json"
if (-not (Test-Path $configPath)) {
    Write-Log "config.json not found at: $configPath" "ERROR"
    exit 1
}

try {
    $config = Get-Content $configPath -Raw | ConvertFrom-Json
} catch {
    Write-Log "Failed to parse config.json: $_" "ERROR"
    exit 1
}

# ── Import Modules ───────────────────────────────────────────────────────────
$modulesDir = Join-Path $ScriptRoot "modules"
$moduleFiles = @(
    "Show-InteractiveMenu.ps1",
    "Install-WingetApps.ps1",
    "Install-ChocoApps.ps1",
    "Install-DevTools.ps1",
    "Install-Fonts.ps1",
    "Set-WindowsSettings.ps1"
)

foreach ($mod in $moduleFiles) {
    $modPath = Join-Path $modulesDir $mod
    if (Test-Path $modPath) {
        . $modPath
    }
}

# ── Interactive Menu or Direct Mode ──────────────────────────────────────────
$filter = $null

if (-not $InstallAll -and -not $DryRun -and -not $SkipApps -and -not $SkipSettings -and -not $SkipDevTools -and -not $ForceReinstall) {
    # No flags passed - show interactive menu
    if (Get-Command Show-MainMenu -ErrorAction SilentlyContinue) {
        $menuChoice = Show-MainMenu
    } else {
        Write-Host "" -ForegroundColor Red
        Write-Host "  ERROR: Interactive menu failed to load." -ForegroundColor Red
        Write-Host "  Run with -InstallAll flag to skip the menu, or fix the error above." -ForegroundColor Yellow
        Write-Host ""
        pause
        exit 1
    }

    switch ($menuChoice) {
        1 {
            # Install Everything - no filter needed
            $filter = $null
        }
        2 {
            # Interactive selection
            $categories = Show-CategoryMenu -Config $config
            $confirmed = Show-ConfirmationScreen -Categories $categories
            if (-not $confirmed) {
                Write-Host "  Setup cancelled." -ForegroundColor Yellow
                exit 0
            }
            $filter = Get-SelectionFilter -Categories $categories
        }
        3 {
            # Force reinstall everything
            $ForceReinstall = $true
            $filter = $null
        }
        4 {
            # Dry run
            $DryRun = $true
            $filter = $null
        }
        5 {
            Write-Host "  Goodbye!" -ForegroundColor Cyan
            exit 0
        }
        default {
            Write-Host "  Invalid choice. Exiting." -ForegroundColor Red
            exit 1
        }
    }
}

# ── Begin Setup ──────────────────────────────────────────────────────────────
Write-Section "ONE-TOUCH WINDOWS SETUP"
Write-Log "Starting setup at $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" "INFO"
Write-Log "Log file: $LogFile" "INFO"

if ($DryRun) {
    Write-Log "*** DRY RUN MODE - No changes will be made ***" "WARN"
}
if ($ForceReinstall) {
    Write-Log "*** FORCE REINSTALL MODE - Will reinstall even if already present ***" "WARN"
}
if ($filter -and $filter.Mode -eq "selective") {
    Write-Log "*** SELECTIVE MODE - Installing only chosen items ***" "INFO"
}

Write-Log "Loaded config: $($config.metadata.name) v$($config.metadata.version)" "SUCCESS"

# ── Ensure Winget ────────────────────────────────────────────────────────────
Write-Section "CHECKING PREREQUISITES"

function Ensure-Winget {
    try {
        $wg = Get-Command winget -ErrorAction Stop
        Write-Log "winget found: $($wg.Source)" "SUCCESS"
        return $true
    } catch {
        Write-Log "winget not found. Attempting to install..." "WARN"
        try {
            $progressPreference = 'silentlyContinue'
            $url = "https://aka.ms/getwinget"
            $outFile = Join-Path $env:TEMP "Microsoft.DesktopAppInstaller.msixbundle"
            Invoke-WebRequest -Uri $url -OutFile $outFile
            Add-AppxPackage -Path $outFile
            Write-Log "winget installed successfully" "SUCCESS"
            return $true
        } catch {
            Write-Log "Failed to install winget: $_" "ERROR"
            Write-Log "Please install 'App Installer' from the Microsoft Store" "ERROR"
            return $false
        }
    }
}

$wingetAvailable = Ensure-Winget

# ── Helper: Check if a phase should run ──────────────────────────────────────
function Should-RunPhase {
    param([string]$PhaseType)

    # If SkipApps/SkipSettings/SkipDevTools flags are used
    if ($SkipApps -and $PhaseType -in @("winget","choco","fonts")) { return $false }
    if ($SkipSettings -and $PhaseType -eq "settings") { return $false }
    if ($SkipDevTools -and $PhaseType -in @("npm","pip","vscode")) { return $false }

    # If selective filter is active
    if ($filter -and $filter.Mode -eq "selective") {
        switch ($PhaseType) {
            "winget"   { return $filter.WingetCategories.Count -gt 0 }
            "choco"    { return $filter.ChocoEnabled }
            "npm"      { return $filter.NpmEnabled }
            "pip"      { return $filter.PipEnabled }
            "vscode"   { return $filter.VscodeEnabled }
            "fonts"    { return $filter.FontsEnabled }
            "settings" { return $filter.SettingsEnabled }
            "git"      { return $filter.GitEnabled }
        }
    }

    return $true
}

# ── Execute Setup Phases ─────────────────────────────────────────────────────

# Phase 1: Winget Apps
if ((Should-RunPhase "winget") -and $wingetAvailable -and $config.winget_apps) {
    Write-Section "PHASE 1: INSTALLING APPS (WINGET)"
    $wingetFilter = if ($filter) { $filter.WingetCategories } else { $null }
    Install-WingetApps -Config $config -DryRun:$DryRun -ForceReinstall:$ForceReinstall -Filter $wingetFilter
}

# Phase 2: Chocolatey Apps
if ((Should-RunPhase "choco") -and $config.choco_apps -and @($config.choco_apps).Count -gt 0) {
    Write-Section "PHASE 2: INSTALLING APPS (CHOCOLATEY)"
    $chocoFilter = if ($filter) { $filter.ChocoItems } else { $null }
    Install-ChocoApps -Config $config -DryRun:$DryRun -ForceReinstall:$ForceReinstall -Filter $chocoFilter
}

# Phase 3: Dev Tools (npm, pip, VS Code extensions)
if ((Should-RunPhase "npm") -or (Should-RunPhase "pip") -or (Should-RunPhase "vscode")) {
    Write-Section "PHASE 3: INSTALLING DEV TOOLS AND EXTENSIONS"
    $devFilter = $null
    if ($filter) {
        $devFilter = @{
            NpmEnabled   = $filter.NpmEnabled
            NpmItems     = $filter.NpmItems
            PipEnabled   = $filter.PipEnabled
            PipItems     = $filter.PipItems
            VscodeEnabled = $filter.VscodeEnabled
            VscodeItems  = $filter.VscodeItems
        }
    }
    Install-DevTools -Config $config -DryRun:$DryRun -ForceReinstall:$ForceReinstall -Filter $devFilter
}

# Phase 4: Fonts
if ((Should-RunPhase "fonts") -and $config.fonts -and @($config.fonts).Count -gt 0) {
    Write-Section "PHASE 4: INSTALLING FONTS"
    $fontFilter = if ($filter) { $filter.FontItems } else { $null }
    Install-Fonts -Config $config -DryRun:$DryRun -ForceReinstall:$ForceReinstall -Filter $fontFilter
}

# Phase 5: Windows Settings
if ((Should-RunPhase "settings") -and $config.windows_settings) {
    Write-Section "PHASE 5: APPLYING WINDOWS SETTINGS"
    Set-WindowsSettings -Config $config -DryRun:$DryRun
}

# Phase 6: Git Config
if ((Should-RunPhase "git") -and $config.git_config) {
    Write-Section "PHASE 6: CONFIGURING GIT"
    try {
        $gc = $config.git_config
        if (-not $DryRun) {
            if ($gc.user_name -and $gc.user_name -ne "Your Name") {
                git config --global user.name $gc.user_name
                Write-Log "Git user.name = $($gc.user_name)" "SUCCESS"
            } else {
                Write-Log "Skipping git user.name (placeholder value)" "WARN"
            }
            if ($gc.user_email -and $gc.user_email -ne "your.email@example.com") {
                git config --global user.email $gc.user_email
                Write-Log "Git user.email = $($gc.user_email)" "SUCCESS"
            } else {
                Write-Log "Skipping git user.email (placeholder value)" "WARN"
            }
            if ($gc.default_branch) {
                git config --global init.defaultBranch $gc.default_branch
                Write-Log "Git default branch = $($gc.default_branch)" "SUCCESS"
            }
            if ($gc.credential_helper) {
                git config --global credential.helper $gc.credential_helper
                Write-Log "Git credential helper = $($gc.credential_helper)" "SUCCESS"
            }
            if ($gc.core_autocrlf) {
                git config --global core.autocrlf $gc.core_autocrlf
                Write-Log "Git core.autocrlf = $($gc.core_autocrlf)" "SUCCESS"
            }
            if ($gc.core_editor) {
                git config --global core.editor $gc.core_editor
                Write-Log "Git core.editor = $($gc.core_editor)" "SUCCESS"
            }
        } else {
            Write-Log "[DRY RUN] Would configure git settings" "WARN"
        }
        $script:Installed++
    } catch {
        Write-Log "Failed to configure git: $_" "ERROR"
        $script:Failed++
    }
}

# ── Summary ──────────────────────────────────────────────────────────────────
Write-Section "SETUP COMPLETE"
Write-Log "Results:" "INFO"
Write-Log "  Installed/Applied : $($script:Installed)" "SUCCESS"
Write-Log "  Skipped (existing): $($script:Skipped)" "INFO"
Write-Log "  Failed            : $($script:Failed)" "ERROR"
Write-Log "" "INFO"
Write-Log "Full log saved to: $LogFile" "INFO"
Write-Log "" "INFO"

if ($script:Failed -gt 0) {
    Write-Log "Some items failed. Check the log for details." "WARN"
}

Write-Log "You may need to RESTART your PC for some changes to take effect." "WARN"
