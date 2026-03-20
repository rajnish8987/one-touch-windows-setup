// ── State ────────────────────────────────────────────────────────────────────
let config = null;
let unsavedChanges = false;
let currentItemType = null;
let statusPollInterval = null;
let installedApps = { winget: '', choco: '' };
let renamingCategory = null;

// ── Init ─────────────────────────────────────────────────────────────────────
document.addEventListener('DOMContentLoaded', () => {
    loadConfig();
    setupNavigation();
});

// ── Navigation ───────────────────────────────────────────────────────────────
function setupNavigation() {
    document.querySelectorAll('.nav-item').forEach(item => {
        item.addEventListener('click', () => {
            const page = item.getAttribute('data-page');
            navigateTo(page);
        });
    });
}

function navigateTo(page) {
    document.querySelectorAll('.nav-item').forEach(n => n.classList.remove('active'));
    const navItem = document.querySelector('.nav-item[data-page="' + page + '"]');
    if (navItem) navItem.classList.add('active');

    document.querySelectorAll('.page').forEach(p => p.classList.remove('active'));
    const pageEl = document.getElementById('page-' + page);
    if (pageEl) pageEl.classList.add('active');

    const titles = { dashboard: 'Dashboard', apps: 'Apps', devtools: 'Dev Tools', settings: 'Settings', run: 'Run Setup' };
    document.getElementById('pageTitle').textContent = titles[page] || page;
}

// ── API ──────────────────────────────────────────────────────────────────────
async function loadConfig() {
    try {
        const res = await fetch('/api/config');
        config = await res.json();
        renderAll();
    } catch (err) {
        showToast('Failed to load config: ' + err.message, true);
    }
}

async function saveConfig() {
    if (!config) return;
    try {
        const res = await fetch('/api/config', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify(config, null, 2)
        });
        const data = await res.json();
        if (data.success) {
            unsavedChanges = false;
            showToast('Config saved!');
        } else {
            showToast('Save failed: ' + (data.error || 'Unknown'), true);
        }
    } catch (err) {
        showToast('Save failed: ' + err.message, true);
    }
}

// ── Render All ───────────────────────────────────────────────────────────────
function renderAll() {
    if (!config) return;
    renderDashboard();
    renderApps();
    renderDevTools();
    renderSettings();
    populateCategoryDropdown();
}

// ── Dashboard ────────────────────────────────────────────────────────────────
function renderDashboard() {
    let totalApps = 0, enabledApps = 0, categories = 0;

    if (config.winget_apps) {
        const cats = Object.keys(config.winget_apps);
        categories = cats.length;
        cats.forEach(cat => {
            const apps = config.winget_apps[cat];
            if (Array.isArray(apps)) {
                totalApps += apps.length;
                apps.forEach(app => { if (app.enabled !== false) enabledApps++; });
            }
        });
    }

    const chocoCount = config.choco_apps ? config.choco_apps.length : 0;
    totalApps += chocoCount;
    config.choco_apps && config.choco_apps.forEach(a => { if (a.enabled !== false) enabledApps++; });

    const extCount = config.vscode_extensions ? config.vscode_extensions.length : 0;

    document.getElementById('statTotalApps').textContent = totalApps;
    document.getElementById('statEnabled').textContent = enabledApps;
    document.getElementById('statCategories').textContent = categories;
    document.getElementById('statExtensions').textContent = extCount;

    // Category overview
    const overview = document.getElementById('categoryOverview');
    overview.innerHTML = '';

    if (config.winget_apps) {
        Object.keys(config.winget_apps).forEach(cat => {
            const apps = config.winget_apps[cat];
            const count = Array.isArray(apps) ? apps.length : 0;
            overview.innerHTML += '<div class="category-card"><span class="category-name">' + formatLabel(cat) + '</span><span class="category-count">' + count + ' apps</span></div>';
        });
    }

    [
        { name: 'Chocolatey', count: config.choco_apps ? config.choco_apps.length : 0 },
        { name: 'npm Packages', count: config.npm_global ? config.npm_global.length : 0 },
        { name: 'pip Packages', count: config.pip_packages ? config.pip_packages.length : 0 },
        { name: 'VS Code Extensions', count: config.vscode_extensions ? config.vscode_extensions.length : 0 },
        { name: 'Fonts', count: config.fonts ? config.fonts.length : 0 }
    ].forEach(e => {
        if (e.count > 0) {
            overview.innerHTML += '<div class="category-card"><span class="category-name">' + e.name + '</span><span class="category-count">' + e.count + ' items</span></div>';
        }
    });
}

// ── Apps Page ────────────────────────────────────────────────────────────────
function renderApps() {
    const container = document.getElementById('appsContainer');
    container.innerHTML = '';

    if (!config.winget_apps) return;

    Object.keys(config.winget_apps).forEach(cat => {
        const apps = config.winget_apps[cat];
        if (!Array.isArray(apps)) return;

        const enabledCount = apps.filter(a => a.enabled !== false).length;

        const section = document.createElement('div');
        section.className = 'app-category';
        section.setAttribute('data-category', cat);

        section.innerHTML =
            '<div class="app-category-header"><div>' +
                '<span class="app-category-title">' + formatLabel(cat) + '</span>' +
                '<span style="color: var(--text-muted); font-size: 12px; margin-left: 8px;">' + enabledCount + '/' + apps.length + ' enabled</span>' +
            '</div><div class="app-category-actions">' +
                '<button class="btn-cat-action" title="Rename" onclick="showRenameCategoryModal(\'' + cat + '\')">&#9998;</button>' +
                '<button class="btn-cat-action danger" title="Delete category" onclick="deleteCategory(\'' + cat + '\')">&#128465;</button>' +
                '<button class="btn-toggle-all" onclick="toggleCategory(\'' + cat + '\', true)">Enable All</button>' +
                '<button class="btn-toggle-all" onclick="toggleCategory(\'' + cat + '\', false)">Disable All</button>' +
            '</div></div>' +
            '<div class="app-grid">' + apps.map(function(app, idx) { return renderAppCard(cat, app, idx); }).join('') + '</div>';

        container.appendChild(section);
    });

    // Choco apps
    if (config.choco_apps && config.choco_apps.length > 0) {
        const section = document.createElement('div');
        section.className = 'app-category';
        section.innerHTML =
            '<div class="app-category-header"><span class="app-category-title">Chocolatey Apps</span></div>' +
            '<div class="app-grid">' + config.choco_apps.map(function(app, idx) {
                var isInstalled = isAppInstalled(app.name, 'choco');
                return '<div class="app-card ' + (app.enabled === false ? 'disabled' : '') + '">' +
                    '<div class="app-info"><div class="app-name">' + escapeHtml(app.description || app.name) + '</div>' +
                    '<div class="app-id">' + escapeHtml(app.name) + '</div></div>' +
                    '<div class="app-actions">' +
                        (isInstalled ? '<span class="badge badge-installed">Installed</span>' : '<span class="badge badge-not-installed">Not installed</span>') +
                        (isInstalled ? '<button class="btn-uninstall" title="Uninstall" onclick="uninstallApp(\'' + app.name + '\', \'choco\')">Uninstall</button>' : '') +
                        '<button class="btn-delete" title="Remove" onclick="removeChocoApp(' + idx + ')">&#10005;</button>' +
                        '<label class="toggle"><input type="checkbox" ' + (app.enabled !== false ? 'checked' : '') + ' onchange="toggleChocoApp(' + idx + ', this.checked)"><span class="toggle-slider"></span></label>' +
                    '</div></div>';
            }).join('') + '</div>';
        container.appendChild(section);
    }
}

function renderAppCard(cat, app, idx) {
    var enabled = app.enabled !== false;
    var isInstalled = isAppInstalled(app.id, 'winget');
    return '<div class="app-card ' + (enabled ? '' : 'disabled') + '">' +
        '<div class="app-info"><div class="app-name">' + escapeHtml(app.name) + '</div>' +
        '<div class="app-id">' + escapeHtml(app.id) + '</div></div>' +
        '<div class="app-actions">' +
            (isInstalled ? '<span class="badge badge-installed">Installed</span>' : '<span class="badge badge-not-installed">Not installed</span>') +
            (isInstalled ? '<button class="btn-uninstall" title="Uninstall" onclick="uninstallApp(\'' + app.id + '\', \'winget\')">Uninstall</button>' : '') +
            '<button class="btn-delete" title="Remove from config" onclick="removeApp(\'' + cat + '\', ' + idx + ')">&#10005;</button>' +
            '<label class="toggle"><input type="checkbox" ' + (enabled ? 'checked' : '') + ' onchange="toggleApp(\'' + cat + '\', ' + idx + ', this.checked)"><span class="toggle-slider"></span></label>' +
        '</div></div>';
}

// ── Installed Status Detection ───────────────────────────────────────────────
function isAppInstalled(appId, source) {
    if (!appId) return false;
    var data = source === 'choco' ? installedApps.choco : installedApps.winget;
    if (!data) return false;
    return data.toLowerCase().indexOf(appId.toLowerCase()) !== -1;
}

async function scanInstalledApps() {
    showToast('Scanning installed apps...');
    try {
        var res = await fetch('/api/installed');
        var data = await res.json();
        installedApps.winget = Array.isArray(data.winget) ? data.winget.join('\n') : (data.winget || '');
        installedApps.choco = Array.isArray(data.choco) ? data.choco.join('\n') : (data.choco || '');
        renderApps();
        showToast('Scan complete!');
    } catch (err) {
        showToast('Scan failed: ' + err.message, true);
    }
}

// ── Uninstall ────────────────────────────────────────────────────────────────
async function uninstallApp(appId, source) {
    if (!confirm('Uninstall "' + appId + '"? This will open an elevated PowerShell window.')) return;
    try {
        var res = await fetch('/api/uninstall', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ id: appId, source: source })
        });
        var data = await res.json();
        if (data.success) {
            showToast('Uninstall started for ' + appId);
        } else {
            showToast('Failed: ' + (data.error || 'Unknown'), true);
        }
    } catch (err) {
        showToast('Uninstall failed: ' + err.message, true);
    }
}

// ── App Toggle/Remove ────────────────────────────────────────────────────────
function toggleApp(cat, idx, enabled) {
    config.winget_apps[cat][idx].enabled = enabled;
    unsavedChanges = true;
    renderApps();
    renderDashboard();
    autoSave();
}

function toggleCategory(cat, enabled) {
    if (config.winget_apps[cat]) {
        config.winget_apps[cat].forEach(function(app) { app.enabled = enabled; });
        unsavedChanges = true;
        renderApps();
        renderDashboard();
        autoSave();
    }
}

function toggleChocoApp(idx, enabled) {
    config.choco_apps[idx].enabled = enabled;
    unsavedChanges = true;
    renderApps();
    autoSave();
}

function removeApp(cat, idx) {
    var app = config.winget_apps[cat][idx];
    if (confirm('Remove "' + app.name + '" from ' + cat + '?')) {
        config.winget_apps[cat].splice(idx, 1);
        unsavedChanges = true;
        renderAll();
        autoSave();
    }
}

function removeChocoApp(idx) {
    var app = config.choco_apps[idx];
    if (confirm('Remove "' + (app.description || app.name) + '"?')) {
        config.choco_apps.splice(idx, 1);
        unsavedChanges = true;
        renderAll();
        autoSave();
    }
}

function filterApps() {
    var query = document.getElementById('appSearch').value.toLowerCase();
    document.querySelectorAll('.app-card').forEach(function(card) {
        var name = card.querySelector('.app-name').textContent.toLowerCase();
        var id = card.querySelector('.app-id').textContent.toLowerCase();
        card.style.display = (name.indexOf(query) !== -1 || id.indexOf(query) !== -1) ? '' : 'none';
    });
}

// ── Add App Modal ────────────────────────────────────────────────────────────
function populateCategoryDropdown() {
    var select = document.getElementById('modalCategory');
    if (!select || !config.winget_apps) return;
    select.innerHTML = '';
    Object.keys(config.winget_apps).forEach(function(cat) {
        var opt = document.createElement('option');
        opt.value = cat;
        opt.textContent = formatLabel(cat);
        select.appendChild(opt);
    });
}

function showAddAppModal() {
    document.getElementById('modalAppId').value = '';
    document.getElementById('modalAppName').value = '';
    document.getElementById('wingetSearchInput').value = '';
    document.getElementById('wingetResults').innerHTML = '';
    populateCategoryDropdown();
    document.getElementById('addAppModal').classList.add('active');
}

function addApp() {
    var cat = document.getElementById('modalCategory').value;
    var id = document.getElementById('modalAppId').value.trim();
    var name = document.getElementById('modalAppName').value.trim();

    if (!id || !name) {
        showToast('Please fill in both Winget ID and Display Name', true);
        return;
    }

    if (!config.winget_apps[cat]) config.winget_apps[cat] = [];
    config.winget_apps[cat].push({ id: id, name: name, enabled: true });
    unsavedChanges = true;
    closeModal('addAppModal');
    renderAll();
    autoSave();
    showToast(name + ' added to ' + formatLabel(cat));
}

// ── Winget Search ────────────────────────────────────────────────────────────
var wingetSearchTimer = null;
function debounceWingetSearch() {
    clearTimeout(wingetSearchTimer);
    wingetSearchTimer = setTimeout(searchWinget, 500);
}

async function searchWinget() {
    var query = document.getElementById('wingetSearchInput').value.trim();
    var container = document.getElementById('wingetResults');

    if (query.length < 2) {
        container.innerHTML = '';
        return;
    }

    container.innerHTML = '<div class="winget-searching">Searching winget...</div>';

    try {
        var res = await fetch('/api/search-winget?q=' + encodeURIComponent(query));
        var data = await res.json();
        var output = data.output || '';

        // Parse winget search output into results
        var lines = output.split('\n');
        var results = [];
        var headerPassed = false;

        for (var i = 0; i < lines.length; i++) {
            var line = lines[i].trim();
            if (line.indexOf('---') !== -1) { headerPassed = true; continue; }
            if (!headerPassed || !line) continue;
            if (line.indexOf('No package found') !== -1) break;

            // Parse columns: Name, Id, Version, etc.
            var parts = line.split(/\s{2,}/);
            if (parts.length >= 2) {
                results.push({ name: parts[0], id: parts[1] });
            }
        }

        if (results.length === 0) {
            container.innerHTML = '<div class="winget-searching">No results found</div>';
            return;
        }

        container.innerHTML = results.slice(0, 10).map(function(r) {
            return '<div class="winget-result-item" onclick="selectWingetResult(\'' + escapeAttr(r.id) + '\', \'' + escapeAttr(r.name) + '\')">' +
                '<span class="winget-result-name">' + escapeHtml(r.name) + '</span>' +
                '<span class="winget-result-id">' + escapeHtml(r.id) + '</span></div>';
        }).join('');
    } catch (err) {
        container.innerHTML = '<div class="winget-searching">Search failed</div>';
    }
}

function selectWingetResult(id, name) {
    document.getElementById('modalAppId').value = id;
    document.getElementById('modalAppName').value = name;
    document.getElementById('wingetResults').innerHTML = '';
    document.getElementById('wingetSearchInput').value = '';
}

// ── Category Management ──────────────────────────────────────────────────────
function showAddCategoryModal() {
    document.getElementById('newCategoryName').value = '';
    document.getElementById('addCategoryModal').classList.add('active');
}

function addCategory() {
    var name = document.getElementById('newCategoryName').value.trim().toLowerCase().replace(/\s+/g, '_');
    if (!name) {
        showToast('Please enter a category name', true);
        return;
    }
    if (config.winget_apps[name]) {
        showToast('Category "' + name + '" already exists', true);
        return;
    }
    config.winget_apps[name] = [];
    unsavedChanges = true;
    closeModal('addCategoryModal');
    renderAll();
    autoSave();
    showToast('Category "' + formatLabel(name) + '" created');
}

function showRenameCategoryModal(cat) {
    renamingCategory = cat;
    document.getElementById('renameCategoryInput').value = cat;
    document.getElementById('renameCategoryModal').classList.add('active');
}

function renameCategory() {
    var newName = document.getElementById('renameCategoryInput').value.trim().toLowerCase().replace(/\s+/g, '_');
    if (!newName || !renamingCategory) {
        showToast('Please enter a name', true);
        return;
    }
    if (newName === renamingCategory) {
        closeModal('renameCategoryModal');
        return;
    }
    if (config.winget_apps[newName]) {
        showToast('Category "' + newName + '" already exists', true);
        return;
    }

    config.winget_apps[newName] = config.winget_apps[renamingCategory];
    delete config.winget_apps[renamingCategory];
    renamingCategory = null;
    unsavedChanges = true;
    closeModal('renameCategoryModal');
    renderAll();
    autoSave();
    showToast('Category renamed');
}

function deleteCategory(cat) {
    var count = config.winget_apps[cat] ? config.winget_apps[cat].length : 0;
    if (!confirm('Delete category "' + formatLabel(cat) + '"' + (count > 0 ? ' and its ' + count + ' apps' : '') + '?')) return;
    delete config.winget_apps[cat];
    unsavedChanges = true;
    renderAll();
    autoSave();
    showToast('Category deleted');
}

// ── Dev Tools Page ───────────────────────────────────────────────────────────
function renderDevTools() {
    renderItemList('npmList', config.npm_global || [], 'npm', function(item) { return { name: item.name, desc: item.description || '' }; });
    renderItemList('pipList', config.pip_packages || [], 'pip', function(item) { return { name: item.name, desc: item.description || '' }; });
    renderItemList('vscodeList', config.vscode_extensions || [], 'vscode', function(item) { return { name: item.id, desc: item.name || '' }; });
    renderItemList('fontList', config.fonts || [], 'font', function(item) { return { name: item.name || item.description, desc: 'via ' + (item.source || 'unknown') }; });
}

function renderItemList(containerId, items, type, formatter) {
    var container = document.getElementById(containerId);
    if (!container) return;
    container.innerHTML = items.map(function(item, idx) {
        var f = formatter(item);
        return '<div class="item-row"><div><div class="item-name">' + escapeHtml(f.name) + '</div>' +
            (f.desc ? '<div class="item-desc">' + escapeHtml(f.desc) + '</div>' : '') +
            '</div><button class="btn-delete" title="Remove" onclick="removeItem(\'' + type + '\', ' + idx + ')">&#10005;</button></div>';
    }).join('');
}

function removeItem(type, idx) {
    var list, name;
    if (type === 'npm') { list = config.npm_global; name = list[idx].name; }
    else if (type === 'pip') { list = config.pip_packages; name = list[idx].name; }
    else if (type === 'vscode') { list = config.vscode_extensions; name = list[idx].name || list[idx].id; }
    else if (type === 'font') { list = config.fonts; name = list[idx].name || list[idx].description; }

    if (confirm('Remove "' + name + '"?')) {
        list.splice(idx, 1);
        unsavedChanges = true;
        renderAll();
        autoSave();
    }
}

// ── Add Item Modal ───────────────────────────────────────────────────────────
function showAddItemModal(type) {
    currentItemType = type;
    var titles = { npm: 'Add npm Package', pip: 'Add pip Package', vscode: 'Add VS Code Extension', font: 'Add Font' };
    var labels = { npm: 'Package Name', pip: 'Package Name', vscode: 'Extension ID', font: 'Font Name' };
    var placeholders = { npm: 'e.g. typescript', pip: 'e.g. flask', vscode: 'e.g. ms-python.python', font: 'e.g. firacode' };

    document.getElementById('itemModalTitle').textContent = titles[type] || 'Add Item';
    document.getElementById('itemModalIdLabel').textContent = labels[type] || 'Name';
    document.getElementById('itemModalId').placeholder = placeholders[type] || '';
    document.getElementById('itemModalId').value = '';
    document.getElementById('itemModalDesc').value = '';
    document.getElementById('addItemModal').classList.add('active');
}

function addItem() {
    var id = document.getElementById('itemModalId').value.trim();
    var desc = document.getElementById('itemModalDesc').value.trim();
    if (!id) { showToast('Please enter a name/ID', true); return; }

    if (currentItemType === 'npm') {
        if (!config.npm_global) config.npm_global = [];
        config.npm_global.push({ name: id, description: desc });
    } else if (currentItemType === 'pip') {
        if (!config.pip_packages) config.pip_packages = [];
        config.pip_packages.push({ name: id, description: desc });
    } else if (currentItemType === 'vscode') {
        if (!config.vscode_extensions) config.vscode_extensions = [];
        config.vscode_extensions.push({ id: id, name: desc });
    } else if (currentItemType === 'font') {
        if (!config.fonts) config.fonts = [];
        config.fonts.push({ name: id, source: 'choco', description: desc });
    }

    unsavedChanges = true;
    closeModal('addItemModal');
    renderAll();
    autoSave();
    showToast(id + ' added!');
}

// ── Settings Page ────────────────────────────────────────────────────────────
function renderSettings() {
    if (config.windows_settings) {
        renderSettingsGroup('explorerSettings', config.windows_settings.explorer, 'windows_settings.explorer');
        renderSettingsGroup('taskbarSettings', config.windows_settings.taskbar, 'windows_settings.taskbar');
        renderSettingsGroup('systemSettings', config.windows_settings.system, 'windows_settings.system');
        renderSettingsGroup('privacySettings', config.windows_settings.privacy, 'windows_settings.privacy');
    }
    if (config.git_config) renderGitSettings();
}

function renderSettingsGroup(containerId, settings, path) {
    var container = document.getElementById(containerId);
    if (!container || !settings) return;
    container.innerHTML = Object.keys(settings).map(function(key) {
        var val = settings[key];
        if (typeof val === 'boolean') {
            return '<div class="setting-row"><span class="setting-label">' + formatLabel(key) + '</span>' +
                '<label class="toggle"><input type="checkbox" ' + (val ? 'checked' : '') + ' onchange="updateSetting(\'' + path + '\', \'' + key + '\', this.checked)"><span class="toggle-slider"></span></label></div>';
        }
        return '<div class="setting-row"><span class="setting-label">' + formatLabel(key) + '</span>' +
            '<input class="setting-input" type="text" value="' + escapeHtml(String(val)) + '" onchange="updateSetting(\'' + path + '\', \'' + key + '\', this.value)"></div>';
    }).join('');
}

function renderGitSettings() {
    var container = document.getElementById('gitSettings');
    if (!container || !config.git_config) return;
    container.innerHTML = Object.keys(config.git_config).map(function(key) {
        return '<div class="setting-row"><span class="setting-label">' + formatLabel(key) + '</span>' +
            '<input class="setting-input" type="text" value="' + escapeHtml(String(config.git_config[key])) + '" onchange="updateGitConfig(\'' + key + '\', this.value)"></div>';
    }).join('');
}

function updateSetting(path, key, value) {
    var parts = path.split('.');
    var obj = config;
    for (var i = 0; i < parts.length; i++) obj = obj[parts[i]];
    obj[key] = value;
    unsavedChanges = true;
    autoSave();
}

function updateGitConfig(key, value) {
    config.git_config[key] = value;
    unsavedChanges = true;
    autoSave();
}

// ── Export/Import Config ─────────────────────────────────────────────────────
function exportConfig() {
    if (!config) return;
    var blob = new Blob([JSON.stringify(config, null, 2)], { type: 'application/json' });
    var url = URL.createObjectURL(blob);
    var a = document.createElement('a');
    a.href = url;
    a.download = 'onetouch-config-' + new Date().toISOString().slice(0, 10) + '.json';
    a.click();
    URL.revokeObjectURL(url);
    showToast('Config exported!');
}

function importConfig() {
    document.getElementById('importFileInput').click();
}

function handleImportFile(event) {
    var file = event.target.files[0];
    if (!file) return;
    var reader = new FileReader();
    reader.onload = function(e) {
        try {
            var imported = JSON.parse(e.target.result);
            if (!imported.winget_apps) {
                showToast('Invalid config: missing winget_apps', true);
                return;
            }
            config = imported;
            unsavedChanges = true;
            renderAll();
            autoSave();
            showToast('Config imported successfully!');
        } catch (err) {
            showToast('Invalid JSON file: ' + err.message, true);
        }
    };
    reader.readAsText(file);
    event.target.value = '';
}

// ── Backup and Restore ───────────────────────────────────────────────────────
async function backupMachineState() {
    showToast('Scanning machine state... (this may take a minute)');
    try {
        var res = await fetch('/api/backup');
        var data = await res.json();

        var blob = new Blob([JSON.stringify(data, null, 2)], { type: 'application/json' });
        var url = URL.createObjectURL(blob);
        var a = document.createElement('a');
        a.href = url;
        a.download = 'machine-backup-' + (data.hostname || 'unknown') + '-' + new Date().toISOString().slice(0, 10) + '.json';
        a.click();
        URL.revokeObjectURL(url);
        showToast('Machine state backed up!');
    } catch (err) {
        showToast('Backup failed: ' + err.message, true);
    }
}

// ── Run Setup ────────────────────────────────────────────────────────────────
async function runSetup() {
    await saveConfig();
    var options = {
        dryRun: document.getElementById('optDryRun').checked,
        forceReinstall: document.getElementById('optForceReinstall').checked,
        skipApps: document.getElementById('optSkipApps').checked,
        skipSettings: document.getElementById('optSkipSettings').checked,
        skipDevTools: document.getElementById('optSkipDevTools').checked
    };

    try {
        var res = await fetch('/api/run', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(options) });
        var data = await res.json();
        if (data.success) {
            document.getElementById('runStatus').style.display = 'block';
            document.getElementById('statusText').textContent = 'Setup running in elevated PowerShell window...';
            document.getElementById('logOutput').textContent = 'Setup started.\nLog file: ' + (data.logFile || 'N/A');
            document.getElementById('btnRun').disabled = true;
            document.getElementById('btnRun').textContent = 'Running...';
            statusPollInterval = setInterval(pollStatus, 3000);
        } else {
            showToast('Failed: ' + (data.error || 'Unknown'), true);
        }
    } catch (err) {
        showToast('Failed: ' + err.message, true);
    }
}

async function pollStatus() {
    try {
        var res = await fetch('/api/status');
        var data = await res.json();
        if (data.log) {
            document.getElementById('logOutput').textContent = data.log;
            var logEl = document.getElementById('logOutput');
            logEl.scrollTop = logEl.scrollHeight;
        }
        if (!data.running) {
            clearInterval(statusPollInterval);
            document.getElementById('statusText').textContent = 'Setup complete!';
            var spinner = document.querySelector('.spinner');
            if (spinner) spinner.style.display = 'none';
            document.getElementById('btnRun').disabled = false;
            document.getElementById('btnRun').textContent = '\u25B6 Run Setup';
        }
    } catch (err) { /* ignore */ }
}

// ── Modals ───────────────────────────────────────────────────────────────────
function closeModal(id) {
    document.getElementById(id).classList.remove('active');
}

document.addEventListener('click', function(e) {
    if (e.target.classList.contains('modal-overlay')) e.target.classList.remove('active');
});

document.addEventListener('keydown', function(e) {
    if (e.key === 'Escape') {
        document.querySelectorAll('.modal-overlay.active').forEach(function(m) { m.classList.remove('active'); });
    }
});

// ── Auto-save ────────────────────────────────────────────────────────────────
var autoSaveTimer = null;
function autoSave() {
    clearTimeout(autoSaveTimer);
    autoSaveTimer = setTimeout(function() { if (unsavedChanges) saveConfig(); }, 1500);
}

// ── Toast ────────────────────────────────────────────────────────────────────
function showToast(message, isError) {
    var toast = document.getElementById('toast');
    toast.textContent = message;
    toast.className = 'toast show' + (isError ? ' error' : '');
    setTimeout(function() { toast.className = 'toast'; }, 3000);
}

// ── Helpers ──────────────────────────────────────────────────────────────────
function formatLabel(str) {
    return str.replace(/_/g, ' ').replace(/\b\w/g, function(c) { return c.toUpperCase(); });
}

function escapeHtml(str) {
    var div = document.createElement('div');
    div.textContent = str;
    return div.innerHTML;
}

function escapeAttr(str) {
    return str.replace(/'/g, "\\'").replace(/"/g, '\\"');
}
