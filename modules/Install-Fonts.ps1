<#
.SYNOPSIS
    Install fonts via winget or Chocolatey with optional filtering and force reinstall
#>

function Install-Fonts {
    param(
        [Parameter(Mandatory)][PSCustomObject]$Config,
        [switch]$DryRun,
        [switch]$ForceReinstall,
        [array]$Filter = $null
    )

    foreach ($font in $Config.fonts) {
        $fontName   = if ($font.name) { $font.name } else { $font.description }
        $fontSource = $font.source

        # Check if font is disabled in config
        if ($font.enabled -eq $false) {
            Write-Log "  [SKIP] $fontName - disabled" "INFO"
            $script:Skipped++
            continue
        }
        # Check item-level filter
        if ($Filter -and ($fontName -notin $Filter)) {
            Write-Log "  [SKIP] $fontName - not selected" "INFO"
            $script:Skipped++
            continue
        }

        if ($DryRun) {
            $action = if ($ForceReinstall) { "Would force reinstall" } else { "Would install" }
            Write-Log "  [DRY RUN] $action font: $fontName (via $fontSource)" "WARN"
            continue
        }

        $action = if ($ForceReinstall) { "Force installing" } else { "Installing" }
        Write-Log "  $action font: $fontName (via $fontSource)..." "INFO"

        try {
            switch ($fontSource) {
                "winget" {
                    $fontId = $font.id

                    # Check if already installed (skip only if not force reinstalling)
                    if (-not $ForceReinstall) {
                        $checkResult = winget list --id $fontId 2>&1 | Out-String
                        if ($checkResult -match [regex]::Escape($fontId)) {
                            Write-Log "  [SKIP] $fontName - already installed" "INFO"
                            $script:Skipped++
                            continue
                        }
                    }

                    $wArgs = @("install", "--id", $fontId, "--accept-source-agreements", "--accept-package-agreements", "--silent")
                    if ($ForceReinstall) { $wArgs += "--force" }

                    & winget @wArgs 2>&1 | Out-Null
                    if ($LASTEXITCODE -eq 0) {
                        Write-Log "  [OK] $fontName installed" "SUCCESS"
                        $script:Installed++
                    } else {
                        Write-Log "  [FAIL] $fontName - exit code: $LASTEXITCODE" "ERROR"
                        $script:Failed++
                    }
                }
                "choco" {
                    $pkgName = $font.name
                    $cArgs = @($pkgName, "-y", "--no-progress")
                    if ($ForceReinstall) { $cArgs += "--force" }

                    choco install @cArgs 2>&1 | Out-Null
                    if ($LASTEXITCODE -eq 0) {
                        Write-Log "  [OK] $fontName installed" "SUCCESS"
                        $script:Installed++
                    } else {
                        Write-Log "  [FAIL] $fontName - exit code: $LASTEXITCODE" "ERROR"
                        $script:Failed++
                    }
                }
                default {
                    Write-Log "  [SKIP] Unknown font source: $fontSource" "WARN"
                    $script:Skipped++
                }
            }
        } catch {
            Write-Log "  [FAIL] $fontName - $_" "ERROR"
            $script:Failed++
        }
    }
}
