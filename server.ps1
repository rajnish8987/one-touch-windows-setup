<#
.SYNOPSIS
    PowerShell HTTP server for the One-Touch Windows Setup Web UI
.DESCRIPTION
    Serves the web frontend and provides REST API endpoints
    to read/write config.json and trigger the setup script.
#>

$ScriptRoot = $PSScriptRoot
$Port = 8080
$Prefix = "http://localhost:$Port/"
$WebRoot = Join-Path $ScriptRoot "web"
$ConfigPath = Join-Path $ScriptRoot "config.json"
$SetupScript = Join-Path $ScriptRoot "setup.ps1"

# Track running setup process
$script:SetupProcess = $null
$script:SetupLogFile = $null

# ── MIME Types ───────────────────────────────────────────────────────────────
$MimeTypes = @{
    ".html" = "text/html"
    ".css"  = "text/css"
    ".js"   = "application/javascript"
    ".json" = "application/json"
    ".png"  = "image/png"
    ".jpg"  = "image/jpeg"
    ".svg"  = "image/svg+xml"
    ".ico"  = "image/x-icon"
    ".woff" = "font/woff"
    ".woff2"= "font/woff2"
}

# ── Start Listener ───────────────────────────────────────────────────────────
$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add($Prefix)

try {
    $listener.Start()
} catch {
    Write-Host "ERROR: Could not start server on port $Port." -ForegroundColor Red
    Write-Host "Try running as Administrator or check if port $Port is in use." -ForegroundColor Yellow
    Write-Host $_.Exception.Message -ForegroundColor Red
    pause
    exit 1
}

Write-Host "Server running at $Prefix" -ForegroundColor Green
Write-Host "Press Ctrl+C to stop." -ForegroundColor DarkGray
Write-Host ""

# Open browser
Start-Process $Prefix

# ── Helper ───────────────────────────────────────────────────────────────────
function Send-Response {
    param(
        [System.Net.HttpListenerResponse]$Response,
        [int]$StatusCode,
        [string]$Body,
        [string]$ContentType
    )
    $Response.StatusCode = $StatusCode
    $Response.ContentType = "$ContentType; charset=utf-8"
    $Response.Headers.Add("Access-Control-Allow-Origin", "*")
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Body)
    $Response.ContentLength64 = $bytes.Length
    $Response.OutputStream.Write($bytes, 0, $bytes.Length)
    $Response.OutputStream.Close()
}

# ── Request Loop ─────────────────────────────────────────────────────────────
try {
    while ($listener.IsListening) {
        $context = $listener.GetContext()
        $request = $context.Request
        $response = $context.Response

        $method = $request.HttpMethod
        $path = $request.Url.LocalPath

        Write-Host "$(Get-Date -Format 'HH:mm:ss') $method $path" -ForegroundColor DarkGray

        try {
            # ── API Routes ───────────────────────────────────────────────
            if ($path -eq "/api/config" -and $method -eq "GET") {
                # Return current config
                $configContent = Get-Content $ConfigPath -Raw -Encoding UTF8
                Send-Response $response 200 $configContent "application/json"
            }
            elseif ($path -eq "/api/config" -and $method -eq "POST") {
                # Save updated config
                $reader = New-Object System.IO.StreamReader($request.InputStream)
                $body = $reader.ReadToEnd()
                $reader.Close()

                # Validate JSON
                try {
                    $null = $body | ConvertFrom-Json
                    [System.IO.File]::WriteAllText($ConfigPath, $body, [System.Text.Encoding]::UTF8)
                    Send-Response $response 200 '{"success": true}' "application/json"
                } catch {
                    Send-Response $response 400 ('{"error": "Invalid JSON: ' + $_.Exception.Message + '"}') "application/json"
                }
            }
            elseif ($path -eq "/api/run" -and $method -eq "POST") {
                # Run setup script
                $reader = New-Object System.IO.StreamReader($request.InputStream)
                $body = $reader.ReadToEnd()
                $reader.Close()

                $options = $body | ConvertFrom-Json

                # Build flags
                $flags = @("-InstallAll")
                if ($options.dryRun) { $flags += "-DryRun" }
                if ($options.forceReinstall) { $flags += "-ForceReinstall" }
                if ($options.skipApps) { $flags += "-SkipApps" }
                if ($options.skipSettings) { $flags += "-SkipSettings" }
                if ($options.skipDevTools) { $flags += "-SkipDevTools" }
                $flagStr = $flags -join " "

                # Create log file path in logs/ folder
                $timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
                $logDir = Join-Path $ScriptRoot "logs"
                if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }
                $script:SetupLogFile = Join-Path $logDir "setup-log-$timestamp.txt"

                # Write initial entry so web UI can read immediately
                Set-Content -Path $script:SetupLogFile -Value "Starting setup at $(Get-Date)..." -Encoding UTF8

                # Write a temporary launcher script (avoids quoting issues with elevated processes)
                $launcherScript = Join-Path $ScriptRoot "_run_setup.ps1"
                $launcherContent = @"
Set-ExecutionPolicy Bypass -Scope Process -Force
`$ErrorActionPreference = 'Continue'
Write-Host 'Starting One-Touch Windows Setup...' -ForegroundColor Cyan
Write-Host ''
& '$SetupScript' $flagStr -LogFile '$($script:SetupLogFile)'
Write-Host ''
Write-Host 'Setup complete. You can close this window.' -ForegroundColor Green
pause
"@
                Set-Content -Path $launcherScript -Value $launcherContent -Encoding UTF8

                # Launch in elevated PowerShell window
                $script:SetupProcess = Start-Process -FilePath "powershell.exe" `
                    -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$launcherScript`"" `
                    -Verb RunAs `
                    -PassThru `
                    -ErrorAction Stop

                $result = @{
                    success = $true
                    message = "Setup started in a new window"
                    pid = $script:SetupProcess.Id
                    logFile = $script:SetupLogFile
                } | ConvertTo-Json

                Send-Response $response 200 $result "application/json"
            }
            elseif ($path -eq "/api/status" -and $method -eq "GET") {
                # Check if setup is running
                $status = @{ running = $false; log = "" }

                if ($script:SetupProcess -and -not $script:SetupProcess.HasExited) {
                    $status.running = $true
                }

                if ($script:SetupLogFile -and (Test-Path $script:SetupLogFile)) {
                    $status.log = Get-Content $script:SetupLogFile -Raw -Encoding UTF8 -ErrorAction SilentlyContinue
                }

                Send-Response $response 200 ($status | ConvertTo-Json) "application/json"
            }
            elseif ($path -eq "/api/search-winget" -and $method -eq "GET") {
                # Search winget for app IDs
                $query = $request.QueryString["q"]
                if ($query) {
                    $searchResult = winget search $query --accept-source-agreements 2>&1 | Out-String
                    $result = @{ output = $searchResult } | ConvertTo-Json
                    Send-Response $response 200 $result "application/json"
                } else {
                    Send-Response $response 400 '{"error": "Missing query parameter q"}' "application/json"
                }
            }
            elseif ($path -eq "/api/installed" -and $method -eq "GET") {
                # Scan installed apps (winget + choco)
                $installed = @{ winget = @(); choco = @() }

                # Winget list
                try {
                    $wingetOutput = winget list --accept-source-agreements 2>&1 | Out-String
                    $installed.winget = @($wingetOutput)
                } catch {
                    $installed.winget = @()
                }

                # Choco list
                try {
                    $chocoOutput = choco list --local-only 2>&1 | Out-String
                    $installed.choco = @($chocoOutput)
                } catch {
                    $installed.choco = @()
                }

                Send-Response $response 200 ($installed | ConvertTo-Json -Depth 3) "application/json"
            }
            elseif ($path -eq "/api/uninstall" -and $method -eq "POST") {
                # Uninstall a specific app
                $reader = New-Object System.IO.StreamReader($request.InputStream)
                $body = $reader.ReadToEnd()
                $reader.Close()

                $opts = $body | ConvertFrom-Json
                $appId = $opts.id
                $source = $opts.source

                if (-not $appId) {
                    Send-Response $response 400 '{"error": "Missing app id"}' "application/json"
                } else {
                    # Write a temp uninstall script to run elevated
                    $uninstallScript = Join-Path $ScriptRoot "_uninstall.ps1"
                    $logFile = Join-Path $ScriptRoot "_uninstall_log.txt"
                    Set-Content -Path $logFile -Value "Uninstalling $appId..." -Encoding UTF8

                    if ($source -eq "choco") {
                        $uninstallContent = @"
Set-ExecutionPolicy Bypass -Scope Process -Force
Write-Host 'Uninstalling $appId via Chocolatey...' -ForegroundColor Cyan
choco uninstall $appId -y 2>&1 | Tee-Object -FilePath '$logFile'
Write-Host ''
Write-Host 'Done. You can close this window.' -ForegroundColor Green
Start-Sleep -Seconds 3
"@
                    } else {
                        $uninstallContent = @"
Set-ExecutionPolicy Bypass -Scope Process -Force
Write-Host 'Uninstalling $appId via Winget...' -ForegroundColor Cyan
winget uninstall --id $appId --silent --accept-source-agreements 2>&1 | Tee-Object -FilePath '$logFile'
Write-Host ''
Write-Host 'Done. You can close this window.' -ForegroundColor Green
Start-Sleep -Seconds 3
"@
                    }
                    Set-Content -Path $uninstallScript -Value $uninstallContent -Encoding UTF8

                    $proc = Start-Process -FilePath "powershell.exe" `
                        -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$uninstallScript`"" `
                        -Verb RunAs `
                        -PassThru `
                        -ErrorAction Stop

                    $result = @{
                        success = $true
                        message = "Uninstall started for $appId"
                        pid = $proc.Id
                    } | ConvertTo-Json
                    Send-Response $response 200 $result "application/json"
                }
            }
            elseif ($path -eq "/api/backup" -and $method -eq "GET") {
                # Export full machine state
                $backup = @{
                    timestamp = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
                    hostname = $env:COMPUTERNAME
                    winget_apps = @()
                    choco_apps = @()
                    npm_global = @()
                    pip_packages = @()
                    vscode_extensions = @()
                }

                # Winget
                try {
                    $backup.winget_apps = @(winget list --accept-source-agreements 2>&1 | Out-String)
                } catch { }

                # Choco
                try {
                    $backup.choco_apps = @(choco list --local-only 2>&1 | Out-String)
                } catch { }

                # npm global
                try {
                    $backup.npm_global = @(npm list -g --depth=0 2>&1 | Out-String)
                } catch { }

                # pip
                try {
                    $backup.pip_packages = @(pip list 2>&1 | Out-String)
                } catch { }

                # VS Code extensions
                try {
                    $backup.vscode_extensions = @(code --list-extensions 2>&1 | Out-String)
                } catch { }

                Send-Response $response 200 ($backup | ConvertTo-Json -Depth 3) "application/json"
            }
            # ── Static Files ─────────────────────────────────────────────
            else {
                if ($path -eq "/") { $path = "/index.html" }
                $filePath = Join-Path $WebRoot ($path -replace "/", "\")

                if (Test-Path $filePath) {
                    $ext = [System.IO.Path]::GetExtension($filePath)
                    $contentType = $MimeTypes[$ext]
                    if (-not $contentType) { $contentType = "application/octet-stream" }

                    $fileBytes = [System.IO.File]::ReadAllBytes($filePath)
                    $response.ContentType = $contentType
                    $response.ContentLength64 = $fileBytes.Length
                    $response.StatusCode = 200
                    $response.OutputStream.Write($fileBytes, 0, $fileBytes.Length)
                    $response.OutputStream.Close()
                } else {
                    Send-Response $response 404 '{"error": "Not found"}' "application/json"
                }
            }
        } catch {
            Write-Host "Error handling request: $($_.Exception.Message)" -ForegroundColor Red
            try {
                Send-Response $response 500 ('{"error": "Internal server error"}') "application/json"
            } catch {
                # Response may already be closed
            }
        }
    }
} finally {
    $listener.Stop()
    Write-Host "Server stopped." -ForegroundColor Yellow
}

