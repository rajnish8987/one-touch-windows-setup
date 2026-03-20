<#
.SYNOPSIS
    Install apps via Chocolatey with optional filtering and force reinstall
#>

function Install-ChocoApps {
    param(
        [Parameter(Mandatory)][PSCustomObject]$Config,
        [switch]$DryRun,
        [switch]$ForceReinstall,
        [array]$Filter = $null
    )

    # Ensure Chocolatey is installed
    try {
        $chocoCmd = Get-Command choco -ErrorAction Stop
        Write-Log "Chocolatey found: $($chocoCmd.Source)" "SUCCESS"
    } catch {
        Write-Log "Chocolatey not found. Installing..." "INFO"
        if (-not $DryRun) {
            try {
                Set-ExecutionPolicy Bypass -Scope Process -Force
                [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
                Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
                $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")
                Write-Log "Chocolatey installed successfully" "SUCCESS"
            } catch {
                Write-Log "Failed to install Chocolatey: $_" "ERROR"
                $script:Failed++
                return
            }
        } else {
            Write-Log "[DRY RUN] Would install Chocolatey" "WARN"
        }
    }

    foreach ($pkg in $Config.choco_apps) {
        $pkgName = $pkg.name
        $pkgDesc = $pkg.description

        # Check if package is disabled in config
        if ($pkg.enabled -eq $false) {
            Write-Log "  [SKIP] $pkgDesc ($pkgName) - disabled" "INFO"
            $script:Skipped++
            continue
        }

        # Check item-level filter
        if ($Filter -and ($pkgName -notin $Filter)) {
            Write-Log "  [SKIP] $pkgDesc ($pkgName) - not selected" "INFO"
            $script:Skipped++
            continue
        }

        # Check if already installed (skip only if not force reinstalling)
        if (-not $ForceReinstall) {
            $installed = choco list --local-only $pkgName 2>&1 | Out-String
            if ($installed -match $pkgName) {
                $lines = $installed -split "`n" | Where-Object { $_ -match "^$pkgName\s" }
                if ($lines) {
                    Write-Log "  [SKIP] $pkgDesc ($pkgName) - already installed" "INFO"
                    $script:Skipped++
                    continue
                }
            }
        }

        if ($DryRun) {
            $action = if ($ForceReinstall) { "Would force reinstall" } else { "Would install" }
            Write-Log "  [DRY RUN] $action`: $pkgDesc ($pkgName)" "WARN"
            continue
        }

        $action = if ($ForceReinstall) { "Force installing" } else { "Installing" }
        Write-Log "  $action`: $pkgDesc ($pkgName)..." "INFO"
        try {
            $chocoArgs = @($pkgName, "-y", "--no-progress")
            if ($ForceReinstall) { $chocoArgs += "--force" }

            choco install @chocoArgs 2>&1 | Out-Null
            if ($LASTEXITCODE -eq 0) {
                Write-Log "  [OK] $pkgDesc installed" "SUCCESS"
                $script:Installed++
            } else {
                Write-Log "  [FAIL] $pkgDesc - exit code: $LASTEXITCODE" "ERROR"
                $script:Failed++
            }
        } catch {
            Write-Log "  [FAIL] $pkgDesc - $_" "ERROR"
            $script:Failed++
        }
    }
}
