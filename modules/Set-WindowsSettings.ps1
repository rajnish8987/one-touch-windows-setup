<#
.SYNOPSIS
    Apply Windows settings via registry tweaks and system commands
#>

function Set-WindowsSettings {
    param(
        [Parameter(Mandatory)][PSCustomObject]$Config,
        [switch]$DryRun
    )

    $settings = $Config.windows_settings

    # ── Explorer Settings ────────────────────────────────────────────────────
    if ($settings.explorer) {
        Write-Log "Applying Explorer settings..." "HEADER"
        $explorerPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"

        $explorerTweaks = @()

        if ($settings.explorer.show_file_extensions) {
            $explorerTweaks += @{ Path = $explorerPath; Name = "HideFileExt"; Value = 0; Desc = "Show file extensions" }
        }
        if ($settings.explorer.show_hidden_files) {
            $explorerTweaks += @{ Path = $explorerPath; Name = "Hidden"; Value = 1; Desc = "Show hidden files" }
        }
        if ($settings.explorer.show_full_path_in_title) {
            $explorerTweaks += @{ Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\CabinetState"; Name = "FullPath"; Value = 1; Desc = "Full path in title bar" }
        }
        if ($settings.explorer.open_to_this_pc) {
            $explorerTweaks += @{ Path = $explorerPath; Name = "LaunchTo"; Value = 1; Desc = "Open Explorer to This PC" }
        }
        if ($settings.explorer.disable_recent_files_in_quick_access) {
            $explorerTweaks += @{ Path = $explorerPath; Name = "ShowRecent"; Value = 0; Desc = "Disable recent files in Quick Access" }
        }

        foreach ($tweak in $explorerTweaks) {
            Apply-RegistryTweak @tweak -DryRun:$DryRun
        }
    }

    # ── Taskbar Settings ─────────────────────────────────────────────────────
    if ($settings.taskbar) {
        Write-Log "Applying Taskbar settings..." "HEADER"
        $taskbarPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search"
        $explorerPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"

        $taskbarTweaks = @()

        if ($settings.taskbar.hide_search_box) {
            $taskbarTweaks += @{ Path = $taskbarPath; Name = "SearchboxTaskbarMode"; Value = 0; Desc = "Hide search box" }
        }
        if ($settings.taskbar.hide_task_view_button) {
            $taskbarTweaks += @{ Path = $explorerPath; Name = "ShowTaskViewButton"; Value = 0; Desc = "Hide Task View button" }
        }
        if ($settings.taskbar.hide_widgets) {
            $taskbarTweaks += @{ Path = $explorerPath; Name = "TaskbarDa"; Value = 0; Desc = "Hide Widgets" }
        }
        if ($settings.taskbar.hide_chat) {
            $taskbarTweaks += @{ Path = $explorerPath; Name = "TaskbarMn"; Value = 0; Desc = "Hide Chat" }
        }

        foreach ($tweak in $taskbarTweaks) {
            Apply-RegistryTweak @tweak -DryRun:$DryRun
        }
    }

    # ── System Settings ──────────────────────────────────────────────────────
    if ($settings.system) {
        Write-Log "Applying System settings..." "HEADER"

        if ($settings.system.dark_mode) {
            $themePath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize"
            Apply-RegistryTweak -Path $themePath -Name "AppsUseLightTheme" -Value 0 -Desc "Dark mode for apps" -DryRun:$DryRun
            Apply-RegistryTweak -Path $themePath -Name "SystemUsesLightTheme" -Value 0 -Desc "Dark mode for system" -DryRun:$DryRun
        }

        if ($settings.system.disable_startup_delay) {
            $serializePath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Serialize"
            if (-not (Test-Path $serializePath)) {
                if (-not $DryRun) { New-Item -Path $serializePath -Force | Out-Null }
            }
            Apply-RegistryTweak -Path $serializePath -Name "StartupDelayInMSec" -Value 0 -Desc "Disable startup delay" -DryRun:$DryRun
        }

        if ($settings.system.enable_developer_mode) {
            Apply-RegistryTweak -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock" -Name "AllowDevelopmentWithoutDevLicense" -Value 1 -Desc "Enable Developer Mode" -DryRun:$DryRun
        }

        if ($settings.system.disable_bing_search_in_start_menu) {
            Apply-RegistryTweak -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search" -Name "BingSearchEnabled" -Value 0 -Desc "Disable Bing in Start Menu" -DryRun:$DryRun
        }

        if ($settings.system.set_power_plan_high_performance) {
            if (-not $DryRun) {
                try {
                    powercfg /setactive 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c
                    Write-Log "  [OK] Power plan set to High Performance" "SUCCESS"
                    $script:Installed++
                } catch {
                    Write-Log "  [FAIL] Could not set power plan: $_" "ERROR"
                    $script:Failed++
                }
            } else {
                Write-Log "  [DRY RUN] Would set power plan to High Performance" "WARN"
            }
        }
    }

    # ── Privacy Settings ─────────────────────────────────────────────────────
    if ($settings.privacy) {
        Write-Log "Applying Privacy settings..." "HEADER"

        if ($settings.privacy.disable_telemetry) {
            Apply-RegistryTweak -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection" -Name "AllowTelemetry" -Value 0 -Desc "Disable telemetry" -DryRun:$DryRun
        }
        if ($settings.privacy.disable_activity_history) {
            $actPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System"
            Apply-RegistryTweak -Path $actPath -Name "EnableActivityFeed" -Value 0 -Desc "Disable activity history" -DryRun:$DryRun
            Apply-RegistryTweak -Path $actPath -Name "PublishUserActivities" -Value 0 -Desc "Disable publish user activities" -DryRun:$DryRun
        }
        if ($settings.privacy.disable_advertising_id) {
            Apply-RegistryTweak -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo" -Name "Enabled" -Value 0 -Desc "Disable advertising ID" -DryRun:$DryRun
        }
    }

    # Restart Explorer to apply changes
    if (-not $DryRun) {
        Write-Log "Restarting Explorer to apply visual changes..." "INFO"
        Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
        Start-Process explorer
        Write-Log "Explorer restarted" "SUCCESS"
    }
}

# ── Helper: Apply a single registry tweak ────────────────────────────────────
function Apply-RegistryTweak {
    param(
        [string]$Path,
        [string]$Name,
        [int]$Value,
        [string]$Desc,
        [switch]$DryRun
    )

    if ($DryRun) {
        Write-Log "  [DRY RUN] Would set: $Desc ($Path\$Name = $Value)" "WARN"
        return
    }

    try {
        # Ensure the registry path exists
        if (-not (Test-Path $Path)) {
            New-Item -Path $Path -Force | Out-Null
        }
        Set-ItemProperty -Path $Path -Name $Name -Value $Value -Type DWord -Force
        Write-Log "  [OK] $Desc" "SUCCESS"
        $script:Installed++
    } catch {
        Write-Log "  [FAIL] $Desc - $_" "ERROR"
        $script:Failed++
    }
}
