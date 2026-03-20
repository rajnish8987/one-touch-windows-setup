<#
.SYNOPSIS
    Install dev tools: npm global packages, pip packages, VS Code extensions
    with optional filtering and force reinstall
#>

function Install-DevTools {
    param(
        [Parameter(Mandatory)][PSCustomObject]$Config,
        [switch]$DryRun,
        [switch]$ForceReinstall,
        [hashtable]$Filter = $null
    )

    # Determine which sub-phases to run
    $runNpm    = if ($Filter) { $Filter.NpmEnabled } else { $true }
    $runPip    = if ($Filter) { $Filter.PipEnabled } else { $true }
    $runVscode = if ($Filter) { $Filter.VscodeEnabled } else { $true }

    $npmItems    = if ($Filter) { $Filter.NpmItems } else { $null }
    $pipItems    = if ($Filter) { $Filter.PipItems } else { $null }
    $vscodeItems = if ($Filter) { $Filter.VscodeItems } else { $null }

    # ── NPM Global Packages ─────────────────────────────────────────────────
    if ($runNpm -and $Config.npm_global -and @($Config.npm_global).Count -gt 0) {
        Write-Log "Installing npm global packages..." "HEADER"

        try {
            $npmCmd = Get-Command npm -ErrorAction Stop
            Write-Log "npm found: $($npmCmd.Source)" "SUCCESS"

            foreach ($pkg in $Config.npm_global) {
                $pkgName = $pkg.name

                # Check if disabled in config
                if ($pkg.enabled -eq $false) {
                    Write-Log "  [SKIP] $pkgName - disabled" "INFO"
                    $script:Skipped++
                    continue
                }
                # Check item-level filter
                if ($npmItems -and ($pkgName -notin $npmItems)) {
                    Write-Log "  [SKIP] $pkgName - not selected" "INFO"
                    $script:Skipped++
                    continue
                }

                # Check if already installed
                if (-not $ForceReinstall) {
                    $globalList = npm list -g $pkgName --depth=0 2>&1 | Out-String
                    if ($globalList -match $pkgName -and $globalList -notmatch "empty") {
                        Write-Log "  [SKIP] $pkgName - already installed" "INFO"
                        $script:Skipped++
                        continue
                    }
                }

                if ($DryRun) {
                    $action = if ($ForceReinstall) { "Would force reinstall" } else { "Would install" }
                    Write-Log "  [DRY RUN] $action npm package: $pkgName" "WARN"
                    continue
                }

                $action = if ($ForceReinstall) { "Force installing" } else { "Installing" }
                Write-Log "  $action`: $pkgName..." "INFO"
                try {
                    npm install -g $pkgName 2>&1 | Out-Null
                    if ($LASTEXITCODE -eq 0) {
                        Write-Log "  [OK] $pkgName installed" "SUCCESS"
                        $script:Installed++
                    } else {
                        Write-Log "  [FAIL] $pkgName - exit code: $LASTEXITCODE" "ERROR"
                        $script:Failed++
                    }
                } catch {
                    Write-Log "  [FAIL] $pkgName - $_" "ERROR"
                    $script:Failed++
                }
            }
        } catch {
            Write-Log "npm not found - skipping npm packages. Install Node.js first." "WARN"
        }
    }

    # ── Pip Packages ─────────────────────────────────────────────────────────
    if ($runPip -and $Config.pip_packages -and @($Config.pip_packages).Count -gt 0) {
        Write-Log "Installing pip packages..." "HEADER"

        $pipCmd = $null
        try {
            $pipCmd = Get-Command pip -ErrorAction Stop
        } catch {
            try {
                $pipCmd = Get-Command pip3 -ErrorAction Stop
            } catch {
                Write-Log "pip not found - skipping pip packages. Install Python first." "WARN"
            }
        }

        if ($pipCmd) {
            Write-Log "pip found: $($pipCmd.Source)" "SUCCESS"

            foreach ($pkg in $Config.pip_packages) {
                $pkgName = $pkg.name

                # Check if disabled in config
                if ($pkg.enabled -eq $false) {
                    Write-Log "  [SKIP] $pkgName - disabled" "INFO"
                    $script:Skipped++
                    continue
                }
                # Check item-level filter
                if ($pipItems -and ($pkgName -notin $pipItems)) {
                    Write-Log "  [SKIP] $pkgName - not selected" "INFO"
                    $script:Skipped++
                    continue
                }

                # Check if already installed
                if (-not $ForceReinstall) {
                    $pipList = pip show $pkgName 2>&1 | Out-String
                    if ($pipList -match "Name:") {
                        Write-Log "  [SKIP] $pkgName - already installed" "INFO"
                        $script:Skipped++
                        continue
                    }
                }

                if ($DryRun) {
                    $action = if ($ForceReinstall) { "Would force reinstall" } else { "Would install" }
                    Write-Log "  [DRY RUN] $action pip package: $pkgName" "WARN"
                    continue
                }

                $action = if ($ForceReinstall) { "Force installing" } else { "Installing" }
                Write-Log "  $action`: $pkgName..." "INFO"
                try {
                    $pipArgs = @("install", $pkgName)
                    if ($ForceReinstall) { $pipArgs += "--force-reinstall" }

                    & pip @pipArgs 2>&1 | Out-Null
                    if ($LASTEXITCODE -eq 0) {
                        Write-Log "  [OK] $pkgName installed" "SUCCESS"
                        $script:Installed++
                    } else {
                        Write-Log "  [FAIL] $pkgName - exit code: $LASTEXITCODE" "ERROR"
                        $script:Failed++
                    }
                } catch {
                    Write-Log "  [FAIL] $pkgName - $_" "ERROR"
                    $script:Failed++
                }
            }
        }
    }

    # ── VS Code Extensions ──────────────────────────────────────────────────
    if ($runVscode -and $Config.vscode_extensions -and @($Config.vscode_extensions).Count -gt 0) {
        Write-Log "Installing VS Code extensions..." "HEADER"

        try {
            $codeCmd = Get-Command code -ErrorAction Stop
            Write-Log "VS Code CLI found" "SUCCESS"

            $installedExts = code --list-extensions 2>&1 | Out-String

            foreach ($ext in $Config.vscode_extensions) {
                $extId   = $ext.id
                $extName = $ext.name

                # Check if disabled in config
                if ($ext.enabled -eq $false) {
                    Write-Log "  [SKIP] $extName ($extId) - disabled" "INFO"
                    $script:Skipped++
                    continue
                }
                # Check item-level filter
                if ($vscodeItems -and ($extId -notin $vscodeItems)) {
                    Write-Log "  [SKIP] $extName ($extId) - not selected" "INFO"
                    $script:Skipped++
                    continue
                }

                # Check if already installed
                if (-not $ForceReinstall -and ($installedExts -match [regex]::Escape($extId))) {
                    Write-Log "  [SKIP] $extName ($extId) - already installed" "INFO"
                    $script:Skipped++
                    continue
                }

                if ($DryRun) {
                    $action = if ($ForceReinstall) { "Would force reinstall" } else { "Would install" }
                    Write-Log "  [DRY RUN] $action extension: $extName ($extId)" "WARN"
                    continue
                }

                $action = if ($ForceReinstall) { "Force installing" } else { "Installing" }
                Write-Log "  $action`: $extName ($extId)..." "INFO"
                try {
                    code --install-extension $extId --force 2>&1 | Out-Null
                    Write-Log "  [OK] $extName installed" "SUCCESS"
                    $script:Installed++
                } catch {
                    Write-Log "  [FAIL] $extName - $_" "ERROR"
                    $script:Failed++
                }
            }
        } catch {
            Write-Log "VS Code CLI not found - skipping extensions. Install VS Code first." "WARN"
        }
    }
}
