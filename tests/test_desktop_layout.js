// Runs the Yūrei Plasma layout script against a stand-in for Plasma 6's
// desktop scripting API (properties and functions as in plasma-workspace's
// shell/scripting). Run with: node tests/test_desktop_layout.js
"use strict";
const fs = require("fs");
const path = require("path");
const vm = require("vm");

const SCRIPT = fs.readFileSync(path.join(__dirname, "..",
    "pkg/yurei-settings/files/usr/share/plasma/shells/org.kde.plasma.desktop/contents/updates/yurei-desktop-layout.js"), "utf8");

class Widget {
    constructor(type) { this.type = type; this.config = {}; this.currentConfigGroup = []; }
    writeConfig(key, value) { this.config[[...this.currentConfigGroup, key].join("/")] = value; }
}

function makePlasma(existing, installed) {
    const state = { panels: [] };
    class Panel {
        constructor() {
            Object.assign(this, { location: "bottom", height: 0, lengthMode: "fill", alignment: "left",
                                  floating: false, hiding: "none", opacity: "adaptive", _widgets: [] });
            state.panels.push(this);
        }
        addWidget(type) { const w = new Widget(type); this._widgets.push(w); return w; }
        widgets() { return this._widgets.slice(); }
        remove() { state.panels = state.panels.filter((p) => p !== this); }
    }
    const ctx = {
        Panel, gridUnit: 18,
        panels: () => state.panels.slice(),
        applicationExists: (id) => installed.includes(id),
        desktops: () => [],
    };
    for (const spec of existing) {
        const p = new Panel();
        p.location = spec.location;
        spec.widgets.forEach((t) => p.addWidget(t));
    }
    return { ctx, state };
}

function run(existing, { installed = ["org.kde.konsole.desktop", "systemsettings.desktop",
                                      "org.kde.discover.desktop", "steam.desktop"], mode } = {}) {
    const { ctx, state } = makePlasma(existing, installed);
    const prefix = mode ? `var yureiLayout = "${mode}";\n` : "";
    vm.runInNewContext(prefix + SCRIPT, ctx);
    return state.panels;
}

const CACHYOS = [{ location: "bottom", widgets: ["org.kde.plasma.kickoff", "org.kde.plasma.pager",
    "org.kde.plasma.icontasks", "org.kde.plasma.marginsseparator", "org.kde.plasma.systemtray",
    "org.kde.plasma.digitalclock", "org.kde.plasma.showdesktop"] }];

let failed = 0;
function check(name, ok) {
    console.log(`${ok ? "ok  " : "FAIL"} ${name}`);
    if (!ok) failed = 1;
}
const types = (p) => p.widgets().map((w) => w.type);

// --- fresh CachyOS desktop -> Yūrei layout ----------------------------------
let ps = run(CACHYOS);
const top = ps.find((p) => p.location === "top");
const dock = ps.find((p) => p.location === "bottom");
check("stock layout replaced by top bar and dock", ps.length === 2 && top && dock);
check("top bar: menu, global menu, centred clock, tray",
      JSON.stringify(types(top)) === JSON.stringify(["org.kde.plasma.kickoff", "org.kde.plasma.appmenu",
          "org.kde.plasma.panelspacer", "org.kde.plasma.digitalclock", "org.kde.plasma.panelspacer",
          "org.kde.plasma.systemtray"]));
const menu = top.widgets()[0];
check("menu shows the Yūrei icon and name", menu.config["General/icon"] === "yurei" && menu.config["General/menuLabel"] === "Yūrei");
check("clock shows the date beside the time", top.widgets()[3].config["Appearance/showDate"] === true &&
      top.widgets()[3].config["Appearance/customDateFormat"] === "ddd d MMM");
check("top bar is slim and full width", top.height === 28 && top.lengthMode === "fill" && !top.floating);
check("dock floats, centred, fitted to its icons",
      dock.floating && dock.alignment === "center" && dock.lengthMode === "fit" && dock.hiding === "dodgewindows");
check("dock: app grid, apps, separator, trash",
      JSON.stringify(types(dock)) === JSON.stringify(["org.kde.plasma.kickerdash", "org.kde.plasma.icontasks",
          "org.kde.plasma.marginsseparator", "org.kde.plasma.trash"]));
const launchers = dock.widgets()[1].config["General/launchers"].split(",");
check("dock apps in design order", launchers.join() === ["preferred://filemanager", "preferred://browser",
      "applications:org.kde.konsole.desktop", "applications:systemsettings.desktop",
      "applications:org.kde.discover.desktop", "applications:steam.desktop"].join());
check("apps that aren't installed are left out", !launchers.includes("applications:discord.desktop"));

// --- users who arranged their own panels keep them ---------------------------
const custom = [{ location: "bottom", widgets: [...CACHYOS[0].widgets, "org.kde.plasma.weather"] }];
check("an extra widget keeps the user's layout", run(custom)[0].widgets().length === 8);
check("a moved panel keeps the user's layout", run([{ ...CACHYOS[0], location: "left" }])[0].location === "left");
check("two panels keep the user's layout", run([...CACHYOS, { location: "top", widgets: ["org.kde.plasma.appmenu"] }]).length === 2 &&
      run([...CACHYOS, { location: "top", widgets: ["org.kde.plasma.appmenu"] }])[1].widgets().length === 1);
check("no panels at all gets the Yūrei layout", run([]).length === 2);

// --- yurei layout dock|classic -----------------------------------------------
ps = run(custom, { mode: "dock" });
check("'yurei layout dock' applies even over a custom layout", ps.length === 2 && ps.some((p) => p.location === "top"));
ps = run(CACHYOS, { mode: "classic" });
check("'yurei layout classic' gives one bottom panel", ps.length === 1 && ps[0].location === "bottom" &&
      types(ps[0]).slice().sort().join() === CACHYOS[0].widgets.slice().sort().join());
process.exit(failed);
