@echo off
title One-Touch Windows Setup
color 0A

echo ============================================================
echo        ONE-TOUCH WINDOWS SETUP
echo        Setting up your machine...
echo ============================================================
echo.

:: Check for admin privileges
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo [!] Requesting Administrator privileges...
    echo.
    powershell -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)

echo [OK] Running as Administrator
echo.

:: Set execution policy and launch PowerShell script
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0setup.ps1"

echo.
echo ============================================================
echo        SETUP COMPLETE! Check the log file for details.
echo ============================================================
echo.
pause
