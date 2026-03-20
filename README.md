# 🚀 One-Touch Windows Setup

Clone this repo on any Windows machine. Double-click `setup.bat`. **Choose what to install** from the interactive menu — or just install everything.

It installs all your apps, dev tools, libraries, fonts, VS Code extensions, and configures Windows settings. You get full control: install everything, pick & choose, force reinstall, or preview with a dry run.

---

## ⚡ Quick Start

```bash
# 1. Clone the repo
git clone https://github.com/YOUR_USERNAME/one-touch-windows-setup.git

# 2. Double-click setup.bat (or run as admin)
cd one-touch-windows-setup
setup.bat
```

That's it. You'll see an interactive menu:

```
╔══════════════════════════════════════════════════════╗
║           🚀  ONE-TOUCH WINDOWS SETUP  🚀           ║
╚══════════════════════════════════════════════════════╝

  [1]  Install Everything           (all apps, tools, settings)
  [2]  Choose What to Install       (pick & choose interactively)
  [3]  Force Reinstall Everything   (reinstall even if present)
  [4]  Dry Run (Preview Only)       (see what would happen)
  [5]  Exit
```

**Option 2** lets you toggle entire categories on/off, and even **drill into** individual apps to pick exactly what you want.

---

## 📦 What's Included

| Category | Count | Examples |
|----------|-------|---------|
| Browsers | 3 | Chrome, Firefox, Brave |
| Dev Tools | 12 | VS Code, Git, Node.js, Python, Docker |
| Utilities | 8 | 7-Zip, PowerToys, Everything, ShareX |
| Media | 6 | VLC, Spotify, OBS, GIMP |
| Communication | 5 | Discord, Zoom, Slack, Telegram, Teams |
| Productivity | 3 | Notion, Obsidian, Adobe Reader |
| Cloud Storage | 2 | Google Drive, Dropbox |
| Gaming | 2 | Steam, Epic Games |
| Choco CLI Tools | 5 | ffmpeg, yt-dlp, wget, curl, adb |
| npm Packages | 8 | typescript, nodemon, prettier, eslint |
| pip Packages | 10 | flask, jupyter, pandas, numpy |
| VS Code Extensions | 15 | Python, GitLens, Copilot, Docker |
| Fonts | 3 | JetBrains Mono, Fira Code, Cascadia Code |
| Windows Tweaks | 15+ | Dark mode, file extensions, privacy |

---

## ✏️ Customize

Edit **`config.json`** to add/remove anything:

```jsonc
// Remove an app — just delete its line
// Add an app — find its winget ID with:
//   winget search "app name"

"winget_apps": {
  "browsers": [
    { "id": "Google.Chrome", "name": "Google Chrome" }
    // add more here
  ]
}
```

**Finding winget IDs:**
```bash
winget search "visual studio"
winget search "spotify"
```

---

## 🎛️ Advanced Usage

```powershell
# Launch interactive menu (default when double-clicking setup.bat)
powershell -ExecutionPolicy Bypass -File setup.ps1

# Install everything without the menu
powershell -ExecutionPolicy Bypass -File setup.ps1 -InstallAll

# Force reinstall everything (even already-installed apps)
powershell -ExecutionPolicy Bypass -File setup.ps1 -InstallAll -ForceReinstall

# Dry run — see what would happen without installing anything
powershell -ExecutionPolicy Bypass -File setup.ps1 -DryRun

# Skip app installs, only apply settings
powershell -ExecutionPolicy Bypass -File setup.ps1 -InstallAll -SkipApps

# Skip settings, only install apps
powershell -ExecutionPolicy Bypass -File setup.ps1 -InstallAll -SkipSettings

# Skip dev tools (npm/pip/vscode extensions)
powershell -ExecutionPolicy Bypass -File setup.ps1 -InstallAll -SkipDevTools
```

---

## 📁 Project Structure

```
one-touch-windows-setup/
├── setup.bat                          # Double-click launcher
├── setup.ps1                          # Main orchestrator
├── config.json                        # Everything you want installed
├── modules/
│   ├── Show-InteractiveMenu.ps1       # Interactive selection menu
│   ├── Install-WingetApps.ps1         # Winget installer
│   ├── Install-ChocoApps.ps1          # Chocolatey installer
│   ├── Install-DevTools.ps1           # npm + pip + VS Code extensions
│   ├── Install-Fonts.ps1              # Font installer
│   └── Set-WindowsSettings.ps1        # Registry & system tweaks
├── README.md
└── .gitignore
```

---

## 📋 Logs

Every run creates a timestamped log file:
```
setup-log-2026-03-16_10-30-00.txt
```

---

## ✅ Features

- **Interactive** — choose what to install with a visual menu
- **Granular** — drill into categories to pick individual apps
- **Force reinstall** — option to reinstall everything from scratch
- **Idempotent** — safe to run multiple times; skips already-installed apps
- **Categorized** — apps organized by category for easy customization
- **Modular** — each installer is a separate module you can extend
- **Dry run** — preview changes before applying
- **Logged** — full output saved to timestamped log files
- **Portable** — just clone and run, no dependencies needed

---

## ⚠️ Notes

- Requires **Windows 10/11** with winget (comes pre-installed)
- **Admin privileges** are needed for some installs and registry changes
- Update `git_config` in `config.json` with your name/email before running
- Some changes (dark mode, registry tweaks) require a **restart** to fully apply
