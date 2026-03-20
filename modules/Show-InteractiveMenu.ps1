<#
.SYNOPSIS
    Interactive menu system for selecting what to install
    Compatible with Windows PowerShell 5.1+
#>

function Show-MainMenu {
    <#
    .DESCRIPTION
        Shows the main menu and returns the user's choice:
        1 = Install Everything
        2 = Interactive Selection
        3 = Force Reinstall Everything
        4 = Dry Run (preview)
        5 = Exit
    #>
    Clear-Host
    Write-Host ""
    Write-Host "  =======================================================" -ForegroundColor Cyan
    Write-Host "  |                                                       |" -ForegroundColor Cyan
    Write-Host "  |         ONE-TOUCH WINDOWS SETUP                       |" -ForegroundColor Cyan
    Write-Host "  |                                                       |" -ForegroundColor Cyan
    Write-Host "  =======================================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  Choose a setup mode:" -ForegroundColor White
    Write-Host ""
    Write-Host "    [1]  Install Everything          " -ForegroundColor Green -NoNewline
    Write-Host "(all apps, tools, settings)" -ForegroundColor DarkGray
    Write-Host "    [2]  Choose What to Install      " -ForegroundColor Yellow -NoNewline
    Write-Host "(pick and choose interactively)" -ForegroundColor DarkGray
    Write-Host "    [3]  Force Reinstall Everything  " -ForegroundColor Magenta -NoNewline
    Write-Host "(reinstall even if present)" -ForegroundColor DarkGray
    Write-Host "    [4]  Dry Run (Preview Only)      " -ForegroundColor DarkCyan -NoNewline
    Write-Host "(see what would happen)" -ForegroundColor DarkGray
    Write-Host "    [5]  Exit" -ForegroundColor Red
    Write-Host ""

    do {
        $choice = Read-Host "  Enter your choice (1-5)"
    } while ($choice -notin @('1','2','3','4','5'))

    return [int]$choice
}

function Show-CategoryMenu {
    <#
    .DESCRIPTION
        Shows categories and lets user toggle them on/off.
        Returns a hashtable of selected categories.
    #>
    param(
        [Parameter(Mandatory=$true)][PSCustomObject]$Config
    )

    # Build a list of all categories with their items
    $categories = New-Object System.Collections.Specialized.OrderedDictionary
    $index = 1

    # Winget categories
    if ($Config.winget_apps) {
        foreach ($prop in $Config.winget_apps.PSObject.Properties) {
            $count = @($prop.Value).Count
            $categories["winget_$($prop.Name)"] = @{
                Index    = $index
                Label    = "Winget - $($prop.Name)"
                Count    = $count
                Selected = $true
                Type     = "winget"
                Category = $prop.Name
            }
            $index++
        }
    }

    # Choco apps
    if ($Config.choco_apps -and @($Config.choco_apps).Count -gt 0) {
        $categories["choco"] = @{
            Index    = $index
            Label    = "Chocolatey Apps"
            Count    = @($Config.choco_apps).Count
            Selected = $true
            Type     = "choco"
            Category = "choco"
        }
        $index++
    }

    # npm packages
    if ($Config.npm_global -and @($Config.npm_global).Count -gt 0) {
        $categories["npm"] = @{
            Index    = $index
            Label    = "npm Global Packages"
            Count    = @($Config.npm_global).Count
            Selected = $true
            Type     = "npm"
            Category = "npm"
        }
        $index++
    }

    # pip packages
    if ($Config.pip_packages -and @($Config.pip_packages).Count -gt 0) {
        $categories["pip"] = @{
            Index    = $index
            Label    = "pip Packages"
            Count    = @($Config.pip_packages).Count
            Selected = $true
            Type     = "pip"
            Category = "pip"
        }
        $index++
    }

    # VS Code extensions
    if ($Config.vscode_extensions -and @($Config.vscode_extensions).Count -gt 0) {
        $categories["vscode"] = @{
            Index    = $index
            Label    = "VS Code Extensions"
            Count    = @($Config.vscode_extensions).Count
            Selected = $true
            Type     = "vscode"
            Category = "vscode"
        }
        $index++
    }

    # Fonts
    if ($Config.fonts -and @($Config.fonts).Count -gt 0) {
        $categories["fonts"] = @{
            Index    = $index
            Label    = "Fonts"
            Count    = @($Config.fonts).Count
            Selected = $true
            Type     = "fonts"
            Category = "fonts"
        }
        $index++
    }

    # Windows Settings
    if ($Config.windows_settings) {
        $categories["settings"] = @{
            Index    = $index
            Label    = "Windows Settings and Tweaks"
            Count    = 0
            Selected = $true
            Type     = "settings"
            Category = "settings"
        }
        $index++
    }

    # Git config
    if ($Config.git_config) {
        $categories["git"] = @{
            Index    = $index
            Label    = "Git Configuration"
            Count    = 0
            Selected = $true
            Type     = "git"
            Category = "git"
        }
        $index++
    }

    # Interactive loop
    $done = $false
    while (-not $done) {
        Clear-Host
        Write-Host ""
        Write-Host "  ---------------------------------------------------------------" -ForegroundColor Cyan
        Write-Host "    SELECT CATEGORIES TO INSTALL" -ForegroundColor Cyan
        Write-Host "    Toggle items with their number. Press ENTER when done." -ForegroundColor DarkGray
        Write-Host "  ---------------------------------------------------------------" -ForegroundColor Cyan
        Write-Host ""

        foreach ($key in $categories.Keys) {
            $cat = $categories[$key]
            if ($cat.Selected) {
                $check = "[X]"
                $color = "Green"
            } else {
                $check = "[ ]"
                $color = "DarkGray"
            }
            if ($cat.Count -gt 0) {
                $countStr = " ($($cat.Count) items)"
            } else {
                $countStr = ""
            }

            $indexStr = "{0,3}" -f $cat.Index
            Write-Host "    $indexStr  $check $($cat.Label)$countStr" -ForegroundColor $color
        }

        Write-Host ""
        Write-Host "    Commands:  [A] Select All   [N] Select None   [D] Drill into category   [ENTER] Continue" -ForegroundColor DarkGray
        Write-Host ""

        $userInput = Read-Host "  Enter number, command, or ENTER to continue"

        if ([string]::IsNullOrWhiteSpace($userInput)) {
            $done = $true
        }
        elseif ($userInput -eq 'A' -or $userInput -eq 'a') {
            foreach ($key in $categories.Keys) { $categories[$key].Selected = $true }
        }
        elseif ($userInput -eq 'N' -or $userInput -eq 'n') {
            foreach ($key in $categories.Keys) { $categories[$key].Selected = $false }
        }
        elseif ($userInput -eq 'D' -or $userInput -eq 'd') {
            $drillNum = Read-Host "  Enter category number to drill into"
            if ($drillNum -match '^\d+$') {
                $drillInt = [int]$drillNum
                $targetKey = $null
                foreach ($k in $categories.Keys) {
                    if ($categories[$k].Index -eq $drillInt) {
                        $targetKey = $k
                        break
                    }
                }
                if ($targetKey) {
                    $drillResult = Show-ItemMenu -Config $Config -CategoryKey $targetKey -CategoryInfo $categories[$targetKey]
                    if ($null -ne $drillResult) {
                        $categories[$targetKey]._SelectedItems = $drillResult
                    }
                }
            }
        }
        elseif ($userInput -match '^\d+$') {
            $num = [int]$userInput
            $toggleKey = $null
            foreach ($k in $categories.Keys) {
                if ($categories[$k].Index -eq $num) {
                    $toggleKey = $k
                    break
                }
            }
            if ($toggleKey) {
                $categories[$toggleKey].Selected = -not $categories[$toggleKey].Selected
            }
        }
    }

    return $categories
}

function Show-ItemMenu {
    <#
    .DESCRIPTION
        Shows individual items within a category for granular selection.
        Returns an array of selected item names/IDs, or $null if cancelled.
    #>
    param(
        [Parameter(Mandatory=$true)][PSCustomObject]$Config,
        [Parameter(Mandatory=$true)][string]$CategoryKey,
        [Parameter(Mandatory=$true)][hashtable]$CategoryInfo
    )

    # Get items based on category type
    $items = @()
    switch ($CategoryInfo.Type) {
        "winget" {
            $catName = $CategoryInfo.Category
            $items = @($Config.winget_apps.$catName) | ForEach-Object {
                @{ Id = $_.id; Name = $_.name; Selected = $true }
            }
        }
        "choco" {
            $items = @($Config.choco_apps) | ForEach-Object {
                @{ Id = $_.name; Name = "$($_.name) - $($_.description)"; Selected = $true }
            }
        }
        "npm" {
            $items = @($Config.npm_global) | ForEach-Object {
                @{ Id = $_.name; Name = "$($_.name) - $($_.description)"; Selected = $true }
            }
        }
        "pip" {
            $items = @($Config.pip_packages) | ForEach-Object {
                @{ Id = $_.name; Name = "$($_.name) - $($_.description)"; Selected = $true }
            }
        }
        "vscode" {
            $items = @($Config.vscode_extensions) | ForEach-Object {
                @{ Id = $_.id; Name = "$($_.name) - $($_.id)"; Selected = $true }
            }
        }
        "fonts" {
            $items = @($Config.fonts) | ForEach-Object {
                if ($_.name) { $fn = $_.name } else { $fn = $_.description }
                @{ Id = $fn; Name = $fn; Selected = $true }
            }
        }
        default {
            Write-Host "  This category cannot be drilled into." -ForegroundColor DarkGray
            Start-Sleep -Seconds 1
            return $null
        }
    }

    if ($items.Count -eq 0) { return $null }

    # Load previously selected items if any
    if ($CategoryInfo._SelectedItems) {
        foreach ($item in $items) {
            $item.Selected = $item.Id -in $CategoryInfo._SelectedItems
        }
    }

    $done = $false
    while (-not $done) {
        Clear-Host
        Write-Host ""
        Write-Host "  ---------------------------------------------------------------" -ForegroundColor Yellow
        Write-Host "    $($CategoryInfo.Label) - Select Items" -ForegroundColor Yellow
        Write-Host "  ---------------------------------------------------------------" -ForegroundColor Yellow
        Write-Host ""

        for ($i = 0; $i -lt $items.Count; $i++) {
            $item = $items[$i]
            if ($item.Selected) {
                $check = "[X]"
                $color = "Green"
            } else {
                $check = "[ ]"
                $color = "DarkGray"
            }

            $indexStr = "{0,3}" -f ($i + 1)
            Write-Host "    $indexStr  $check $($item.Name)" -ForegroundColor $color
        }

        Write-Host ""
        Write-Host "    Commands:  [A] All   [N] None   [ENTER] Done" -ForegroundColor DarkGray
        Write-Host ""

        $userInput = Read-Host "  Toggle number or ENTER to go back"

        if ([string]::IsNullOrWhiteSpace($userInput)) {
            $done = $true
        }
        elseif ($userInput -eq 'A' -or $userInput -eq 'a') {
            foreach ($item in $items) { $item.Selected = $true }
        }
        elseif ($userInput -eq 'N' -or $userInput -eq 'n') {
            foreach ($item in $items) { $item.Selected = $false }
        }
        elseif ($userInput -match '^\d+$') {
            $num = [int]$userInput
            if ($num -ge 1 -and $num -le $items.Count) {
                $items[$num - 1].Selected = -not $items[$num - 1].Selected
            }
        }
    }

    # Return selected item IDs
    return @($items | Where-Object { $_.Selected } | ForEach-Object { $_.Id })
}

function Show-ConfirmationScreen {
    <#
    .DESCRIPTION
        Shows a summary of what will be installed and asks for confirmation.
    #>
    param(
        [Parameter(Mandatory=$true)]$Categories
    )

    Clear-Host
    Write-Host ""
    Write-Host "  ---------------------------------------------------------------" -ForegroundColor Green
    Write-Host "    INSTALLATION SUMMARY" -ForegroundColor Green
    Write-Host "  ---------------------------------------------------------------" -ForegroundColor Green
    Write-Host ""

    $totalItems = 0
    foreach ($key in $Categories.Keys) {
        $cat = $Categories[$key]
        if ($cat.Selected) {
            if ($cat._SelectedItems) {
                $itemCount = @($cat._SelectedItems).Count
                $totalItems += $itemCount
                Write-Host "    [YES]  $($cat.Label) ($itemCount of $($cat.Count) items)" -ForegroundColor Green
            } else {
                $totalItems += $cat.Count
                Write-Host "    [YES]  $($cat.Label)" -ForegroundColor Green
            }
        } else {
            Write-Host "    [NO ]  $($cat.Label)" -ForegroundColor DarkGray
        }
    }

    Write-Host ""
    Write-Host "  Total components to process: ~$totalItems" -ForegroundColor Cyan
    Write-Host ""

    $confirm = Read-Host "  Proceed with installation? (Y/n)"
    return ($confirm -eq '' -or $confirm -eq 'Y' -or $confirm -eq 'y')
}

function Get-SelectionFilter {
    <#
    .DESCRIPTION
        Converts the interactive selection into a filter object
        used by the installer modules.
    #>
    param(
        [Parameter(Mandatory=$true)]$Categories
    )

    $filter = @{
        Mode              = "selective"
        WingetCategories  = @{}
        ChocoEnabled      = $false
        ChocoItems        = $null
        NpmEnabled        = $false
        NpmItems          = $null
        PipEnabled        = $false
        PipItems          = $null
        VscodeEnabled     = $false
        VscodeItems       = $null
        FontsEnabled      = $false
        FontItems         = $null
        SettingsEnabled   = $false
        GitEnabled        = $false
    }

    foreach ($key in $Categories.Keys) {
        $cat = $Categories[$key]
        if (-not $cat.Selected) { continue }

        switch ($cat.Type) {
            "winget" {
                if ($cat._SelectedItems) {
                    $filter.WingetCategories[$cat.Category] = $cat._SelectedItems
                } else {
                    $filter.WingetCategories[$cat.Category] = $null
                }
            }
            "choco"    { $filter.ChocoEnabled = $true; $filter.ChocoItems = $cat._SelectedItems }
            "npm"      { $filter.NpmEnabled = $true; $filter.NpmItems = $cat._SelectedItems }
            "pip"      { $filter.PipEnabled = $true; $filter.PipItems = $cat._SelectedItems }
            "vscode"   { $filter.VscodeEnabled = $true; $filter.VscodeItems = $cat._SelectedItems }
            "fonts"    { $filter.FontsEnabled = $true; $filter.FontItems = $cat._SelectedItems }
            "settings" { $filter.SettingsEnabled = $true }
            "git"      { $filter.GitEnabled = $true }
        }
    }

    return $filter
}
