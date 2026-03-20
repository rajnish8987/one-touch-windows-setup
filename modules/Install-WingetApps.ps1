<#
.SYNOPSIS
    Install apps via winget with optional filtering and force reinstall
#>

function Install-WingetApps {
    param(
        [Parameter(Mandatory)][PSCustomObject]$Config,
        [switch]$DryRun,
        [switch]$ForceReinstall,
        [hashtable]$Filter = $null
    )

    $categories = $Config.winget_apps.PSObject.Properties

    foreach ($category in $categories) {
        $catName = $category.Name

        # If filter is active, check if this category is selected
        if ($Filter -and -not $Filter.ContainsKey($catName)) {
            Write-Log "  [SKIP] Category: $catName (not selected)" "INFO"
            continue
        }

        # Get the item-level filter for this category (if any)
        $allowedItems = if ($Filter -and $Filter[$catName]) { $Filter[$catName] } else { $null }

        Write-Log "Category: $catName" "HEADER"

        foreach ($app in $category.Value) {
            $appId   = $app.id
            $appName = $app.name

            # Check if app is disabled in config
            if ($app.enabled -eq $false) {
                Write-Log "  [SKIP] $appName ($appId) - disabled" "INFO"
                $script:Skipped++
                continue
            }
            # Check item-level filter
            if ($allowedItems -and ($appId -notin $allowedItems)) {
                Write-Log "  [SKIP] $appName ($appId) - not selected" "INFO"
                $script:Skipped++
                continue
            }

            # Check if already installed (skip only if not force reinstalling)
            if (-not $ForceReinstall) {
                $checkResult = winget list --id $appId 2>&1 | Out-String
                if ($checkResult -match [regex]::Escape($appId)) {
                    Write-Log "  [SKIP] $appName ($appId) - already installed" "INFO"
                    $script:Skipped++
                    continue
                }
            }

            if ($DryRun) {
                $action = if ($ForceReinstall) { "Would force reinstall" } else { "Would install" }
                Write-Log "  [DRY RUN] $action`: $appName ($appId)" "WARN"
                continue
            }

            $action = if ($ForceReinstall) { "Force installing" } else { "Installing" }
            Write-Log "  $action`: $appName ($appId)..." "INFO"
            try {
                $args = @("install", "--id", $appId, "--accept-source-agreements", "--accept-package-agreements", "--silent")
                if ($ForceReinstall) { $args += "--force" }

                $result = & winget @args 2>&1 | Out-String

                if ($LASTEXITCODE -eq 0 -or $result -match "Successfully installed") {
                    Write-Log "  [OK] $appName installed" "SUCCESS"
                    $script:Installed++
                } else {
                    Write-Log "  [FAIL] $appName - exit code: $LASTEXITCODE" "ERROR"
                    $script:Failed++
                }
            } catch {
                Write-Log "  [FAIL] $appName - $_" "ERROR"
                $script:Failed++
            }
        }
    }
}
