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

    # Timeout in seconds for winget operations
    $ListTimeoutSec = 30
    $InstallTimeoutSec = 600  # 10 minutes per app

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

            # Validate winget ID format (must contain a dot, e.g. "Publisher.Package")
            if ($appId -notmatch '\.') {
                Write-Log "  [SKIP] $appName - invalid winget ID '$appId' (expected format: Publisher.Package)" "WARN"
                $script:Skipped++
                continue
            }

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
                try {
                    # Run winget list with a timeout to prevent hanging
                    $listJob = Start-Job -ScriptBlock {
                        param($id)
                        winget list --id $id --accept-source-agreements 2>&1 | Out-String
                    } -ArgumentList $appId

                    $jobCompleted = $listJob | Wait-Job -Timeout $ListTimeoutSec
                    if ($jobCompleted) {
                        $checkResult = Receive-Job $listJob
                        Remove-Job $listJob -Force
                        if ($checkResult -match [regex]::Escape($appId)) {
                            Write-Log "  [SKIP] $appName ($appId) - already installed" "INFO"
                            $script:Skipped++
                            continue
                        }
                    } else {
                        # Timed out - kill the job and proceed to install
                        Write-Log "  [WARN] Timed out checking if $appName is installed (${ListTimeoutSec}s). Proceeding..." "WARN"
                        Stop-Job $listJob -ErrorAction SilentlyContinue
                        Remove-Job $listJob -Force -ErrorAction SilentlyContinue
                    }
                } catch {
                    Write-Log "  [WARN] Error checking $appName status: $_. Proceeding..." "WARN"
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
                $wingetArgs = @("install", "--id", $appId, "--accept-source-agreements", "--accept-package-agreements", "--silent")
                if ($ForceReinstall) { $wingetArgs += "--force" }

                # Run winget install with a timeout to prevent hanging
                $installJob = Start-Job -ScriptBlock {
                    param($wArgs)
                    $result = & winget @wArgs 2>&1 | Out-String
                    return @{ Output = $result; ExitCode = $LASTEXITCODE }
                } -ArgumentList (,$wingetArgs)

                $jobCompleted = $installJob | Wait-Job -Timeout $InstallTimeoutSec
                if ($jobCompleted) {
                    $jobResult = Receive-Job $installJob
                    Remove-Job $installJob -Force

                    $exitCode = $jobResult.ExitCode
                    $output = $jobResult.Output

                    if ($exitCode -eq 0 -or $output -match "Successfully installed") {
                        Write-Log "  [OK] $appName installed" "SUCCESS"
                        $script:Installed++
                    } else {
                        Write-Log "  [FAIL] $appName - exit code: $exitCode" "ERROR"
                        if ($output) { Write-Log "         $($output.Substring(0, [Math]::Min(200, $output.Length)))" "ERROR" }
                        $script:Failed++
                    }
                } else {
                    # Installation timed out
                    Write-Log "  [FAIL] $appName - installation timed out after ${InstallTimeoutSec}s" "ERROR"
                    Stop-Job $installJob -ErrorAction SilentlyContinue
                    Remove-Job $installJob -Force -ErrorAction SilentlyContinue
                    $script:Failed++
                }
            } catch {
                Write-Log "  [FAIL] $appName - $_" "ERROR"
                $script:Failed++
            }
        }
    }
}
