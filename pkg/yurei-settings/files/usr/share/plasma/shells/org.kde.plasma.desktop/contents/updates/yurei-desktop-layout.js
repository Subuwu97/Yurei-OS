// Yūrei desktop layout: a slim top bar and a floating, macOS-style dock.
//
// Plasma runs this once per user when their desktop first starts. It only
// replaces the layout if it is still the stock CachyOS/Plasma bottom panel,
// so anyone who has arranged their own panels keeps them.
//
// `yurei layout dock|classic` runs the same file through Plasma's scripting
// interface with `yureiLayout` set, which applies that layout regardless.
//
//   top bar:  Yūrei menu · global menu ········ date and time ········ tray
//   dock:     apps launcher | (Install Yūrei, on the live ISO) Files Firefox
//             Terminal Settings Discover Steam Discord (running apps appear
//             here too) | Trash

var requested = typeof yureiLayout !== "undefined" ? yureiLayout : "";

// what CachyOS (and stock Plasma) put in the single default bottom panel
var STOCK_PANEL = ["org.kde.plasma.digitalclock", "org.kde.plasma.icontasks",
                   "org.kde.plasma.kickoff", "org.kde.plasma.marginsseparator",
                   "org.kde.plasma.pager", "org.kde.plasma.showdesktop",
                   "org.kde.plasma.systemtray"];

var DOCK_APPS = [
    // only exists on the live ISO, where it's the way to install
    "applications:yurei-install.desktop",
    "preferred://filemanager",
    "preferred://browser",
    "applications:org.kde.konsole.desktop",
    "applications:systemsettings.desktop",
    "applications:org.kde.discover.desktop",
    "applications:steam.desktop",
    "applications:discord.desktop",
];

function widgetTypes(panel) {
    return panel.widgets().map(function (w) { return w.type; }).sort();
}

function isStockLayout() {
    var all = panels();
    if (all.length === 0)
        return true;
    if (all.length !== 1 || all[0].location !== "bottom")
        return false;
    return widgetTypes(all[0]).join(",") === STOCK_PANEL.join(",");
}

function installedApps(launchers) {
    return launchers.filter(function (url) {
        var m = /^applications:(.+)$/.exec(url);
        return !m || applicationExists(m[1]);
    });
}

function configure(widget, group, values) {
    widget.currentConfigGroup = group;
    for (var key in values)
        widget.writeConfig(key, values[key]);
}

function removeAllPanels() {
    panels().forEach(function (p) { p.remove(); });
}

function addTopBar() {
    var bar = new Panel;
    bar.location = "top";
    bar.height = 2 * Math.round(gridUnit * 0.8);  // ~28 px at normal font size
    bar.floating = false;
    bar.opacity = "translucent";

    var menu = bar.addWidget("org.kde.plasma.kickoff");
    configure(menu, ["General"], { icon: "yurei", menuLabel: "Yūrei" });
    configure(menu, ["Shortcuts"], { global: "Alt+F1" });

    // the focused app's menus, like macOS (empty while the desktop is focused)
    bar.addWidget("org.kde.plasma.appmenu");
    bar.addWidget("org.kde.plasma.panelspacer");

    var clock = bar.addWidget("org.kde.plasma.digitalclock");
    configure(clock, ["Appearance"], {
        showDate: true,
        dateFormat: "custom",
        customDateFormat: "ddd d MMM",
        dateDisplayFormat: 1,  // beside the time
    });

    bar.addWidget("org.kde.plasma.panelspacer");
    bar.addWidget("org.kde.plasma.systemtray");
}

function addDock() {
    var dock = new Panel;
    dock.location = "bottom";
    dock.height = 2 * Math.round(gridUnit * 1.6);  // ~58 px
    dock.lengthMode = "fit";
    dock.alignment = "center";
    dock.floating = true;
    dock.hiding = "dodgewindows";  // steps aside when a window covers it
    dock.opacity = "translucent";

    var launcher = dock.addWidget("org.kde.plasma.kickerdash");  // full-screen app grid
    configure(launcher, ["General"], { icon: "yurei" });

    var tasks = dock.addWidget("org.kde.plasma.icontasks");
    configure(tasks, ["General"], {
        launchers: installedApps(DOCK_APPS).join(","),
        showOnlyCurrentDesktop: false,
        indicateAudioStreams: true,
    });

    dock.addWidget("org.kde.plasma.marginsseparator");
    dock.addWidget("org.kde.plasma.trash");
}

function addClassicPanel() {
    var panel = new Panel;
    panel.location = "bottom";
    panel.height = 2 * Math.round(gridUnit * 1.2);
    var menu = panel.addWidget("org.kde.plasma.kickoff");
    configure(menu, ["General"], { icon: "yurei" });
    panel.addWidget("org.kde.plasma.pager");
    var tasks = panel.addWidget("org.kde.plasma.icontasks");
    configure(tasks, ["General"], {
        launchers: "applications:systemsettings.desktop,preferred://filemanager,preferred://browser",
    });
    panel.addWidget("org.kde.plasma.marginsseparator");
    panel.addWidget("org.kde.plasma.systemtray");
    panel.addWidget("org.kde.plasma.digitalclock");
    panel.addWidget("org.kde.plasma.showdesktop");
}

if (requested === "classic") {
    removeAllPanels();
    addClassicPanel();
} else if (requested === "dock" || isStockLayout()) {
    removeAllPanels();
    addTopBar();
    addDock();
}
