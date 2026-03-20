@echo off
title One-Touch Windows Setup - Web UI
color 0A

echo ============================================================
echo        ONE-TOUCH WINDOWS SETUP - WEB UI
echo ============================================================
echo.
echo Starting web server on http://localhost:8080 ...
echo Press Ctrl+C to stop the server.
echo.

cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0server.ps1"
