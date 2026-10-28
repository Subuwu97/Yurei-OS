"""Loads the Plasma splash and the installer's slideshow and step bar in
Qt 6, with stand-ins for Calamares' QML modules, and checks that they load
without warnings and draw what they should.

    python3 -m pytest tests/test_branding_qml.py

Set YUREI_SCREENSHOTS to a directory to keep pictures of what was drawn.
"""

import os
import re
from pathlib import Path

import pytest

pytest.importorskip("PySide6")

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")
os.environ.setdefault("QT_QUICK_BACKEND", "software")

from PySide6.QtCore import QObject, QUrl, qInstallMessageHandler  # noqa: E402
from PySide6.QtGui import QGuiApplication  # noqa: E402
from PySide6.QtQuick import QQuickView  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
THEME = ROOT / "themes/plasma/yurei"  # the global theme, with the splash
BRANDING = ROOT / "overlay/airootfs/usr/share/calamares/branding/yurei"

# just enough of Calamares' QML API for the branding files
STUBS = {
    "calamares/slideshow/qmldir": "module calamares.slideshow\nPresentation 1.0 Presentation.qml\nSlide 1.0 Slide.qml\n",
    "calamares/slideshow/Presentation.qml": """
import QtQuick
Item {
    id: root
    anchors.fill: parent
    property bool activatedInCalamares: false
    property int currentSlide: 0
    property var slides: []
    property int slideCount: 0
    Component.onCompleted: {
        for (var i = 0; i < children.length; ++i)
            if (children[i].isSlide) slides.push(children[i]);
        slideCount = slides.length;
        update();
    }
    onCurrentSlideChanged: update()
    function update() {
        for (var i = 0; i < slides.length; ++i) slides[i].visible = (i === currentSlide);
    }
    function goToNextSlide() { currentSlide = (currentSlide + 1) % slides.length; }
}
""",
    "calamares/slideshow/Slide.qml": "import QtQuick\nItem { property bool isSlide: true }\n",
    "io/calamares/ui/qmldir": "module io.calamares.ui\nsingleton Branding 1.0 Branding.qml\n",
    "io/calamares/ui/Branding.qml": """
pragma Singleton
import QtQuick
QtObject {
    enum StyleEntry { SidebarBackground, SidebarText, SidebarTextCurrent, SidebarBackgroundCurrent }
    enum ImageEntry { ProductLogo }
    property var styles: ({})
    property string brandingDir: ""
    function styleString(role) { return styles[role]; }
    function imagePath(which) { return brandingDir + "/logo.png"; }
}
""",
    "io/calamares/core/qmldir": "module io.calamares.core\nsingleton ViewManager 1.0 ViewManager.qml\n",
    "io/calamares/core/ViewManager.qml": """
pragma Singleton
import QtQuick
ListModel {
    property int currentStepIndex: 1
    ListElement { display: "Welcome" }
    ListElement { display: "Location" }
    ListElement { display: "Keyboard" }
    ListElement { display: "Partitions" }
    ListElement { display: "Users" }
    ListElement { display: "Summary" }
    ListElement { display: "Install" }
    ListElement { display: "Finish" }
}
""",
}

warnings: list[str] = []


@pytest.fixture(scope="module")
def app():
    return QGuiApplication.instance() or QGuiApplication([])


@pytest.fixture
def load(app, tmp_path):
    for name, text in STUBS.items():
        path = tmp_path / "imports" / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text)
    # the desc file's colours, as Calamares would hand them to the QML
    desc = (BRANDING / "branding.desc").read_text()
    colours = dict(re.findall(r'^\s+(Sidebar\w+):\s+"(#\w+)"', desc, re.M))
    ui = tmp_path / "imports/io/calamares/ui/Branding.qml"
    ui.write_text(ui.read_text()
                  .replace('property var styles: ({})', 'property var styles: ({0: "%s", 1: "%s", 2: "%s", 3: "%s"})' % (
                      colours["SidebarBackground"], colours["SidebarText"],
                      colours["SidebarTextCurrent"], colours["SidebarBackgroundCurrent"]))
                  .replace('property string brandingDir: ""', f'property string brandingDir: "{BRANDING}"'))

    warnings.clear()
    previous = qInstallMessageHandler(lambda mode, ctx, msg: warnings.append(msg))
    views = []

    def _load(qml, width, height, **props):
        view = QQuickView()
        view.engine().addImportPath(str(tmp_path / "imports"))
        view.setResizeMode(QQuickView.SizeRootObjectToView)
        view.resize(width, height)
        view.setSource(QUrl.fromLocalFile(str(qml)))
        assert view.status() == QQuickView.Ready, [e.toString() for e in view.errors()]
        for key, value in props.items():
            view.rootObject().setProperty(key, value)
        view.show()
        settle(app)
        views.append(view)
        return view

    yield _load
    for view in views:
        view.close()
        view.deleteLater()
    settle(app)
    qInstallMessageHandler(previous)


def settle(app, rounds=20):
    for _ in range(rounds):
        app.processEvents()


def shot(img, name):
    if os.environ.get("YUREI_SCREENSHOTS"):
        out = Path(os.environ["YUREI_SCREENSHOTS"])
        out.mkdir(parents=True, exist_ok=True)
        img.save(str(out / f"{name}.png"))


def brightness(img, x, y):
    c = img.pixelColor(x, y)
    return (c.red() + c.green() + c.blue()) / 3


def test_splash_matches_boot_animation_placement(load, app):
    view = load(THEME / "contents/splash/Splash.qml", 1920, 1080, stage=3)
    root = view.rootObject()
    # same fit as yurei.script: min(1920*0.92/1085, 1080*0.62/532) ~ 1.26
    assert abs(root.property("fit") - min(1920 * 0.92 / 1085, 1080 * 0.62 / 532)) < 1e-6
    img = view.grabWindow()
    shot(img, "plasma-splash")
    assert img.pixelColor(5, 5).name() == "#060c1f"  # the boot animation's navy
    # the mascot is drawn in the right half of the frame, around the middle
    assert max(brightness(img, x, 430) for x in range(1000, 1500, 10)) > 120
    assert not warnings, warnings


def test_splash_animates_and_tracks_stages(load, app):
    view = load(THEME / "contents/splash/Splash.qml", 1366, 768, stage=1)
    root = view.rootObject()
    start = root.property("tick")
    for _ in range(10):
        QObject().thread().msleep(45)
        settle(app)
    assert root.property("tick") != start
    for stage in (1, 6):
        root.setProperty("stage", stage)
        settle(app)
    assert not warnings, warnings


def test_global_theme_package():
    import configparser
    import json
    meta = json.loads((THEME / "metadata.json").read_text())
    assert meta["KPackageStructure"] == "Plasma/LookAndFeel"
    assert meta["KPlugin"]["Id"] == "org.yurei.desktop"
    defaults = (THEME / "contents/defaults").read_text()
    assert "ColorScheme=Yurei" in defaults and "Theme=org.yurei.desktop" in defaults
    for preview in ("preview.png", "fullscreenpreview.jpg", "splash.png"):
        assert (THEME / "contents/previews" / preview).is_file()
    # the colour scheme it names exists and has every colour set
    files = ROOT / "pkg/yurei-settings/files"
    scheme = configparser.ConfigParser(interpolation=None)
    scheme.optionxform = str
    scheme.read(files / "usr/share/color-schemes/Yurei.colors")
    for group in ("Button", "Complementary", "Header", "Selection", "Tooltip", "View", "Window"):
        assert len(scheme[f"Colors:{group}"]) == 12, group
    assert scheme["General"]["ColorScheme"] == "Yurei"
    assert "Theme=org.yurei.desktop" in (files / "etc/xdg/ksplashrc").read_text()
    frames = list((THEME / "contents/splash/images").glob("wave-*.png"))
    count = int(re.search(r"frameCount = (\d+)", (THEME / "contents/splash/wave.js").read_text())[1])
    assert len(frames) == count


def test_slideshow(load, app):
    view = load(BRANDING / "show.qml", 1100, 480)
    root = view.rootObject()
    count = root.property("slideCount")
    assert count == 5
    for i in range(count):
        root.setProperty("currentSlide", i)
        settle(app)
        img = view.grabWindow()
        shot(img, f"installer-slide-{i + 1}")
        # dark behind the text on the left, the artwork on the right
        assert brightness(img, 20, 20) < 60
        assert max(brightness(img, x, 240) for x in range(700, 1100, 10)) > 90
    assert not warnings, warnings


def test_sidebar(load, app):
    view = load(BRANDING / "calamares-sidebar.qml", 1100, 40)
    img = view.grabWindow()
    shot(img, "installer-steps")
    # the current step (Location, the 2nd) is a lavender tab
    lavender = [x for x in range(0, 1100, 4) if img.pixelColor(x, 20).name() == "#b9aaff"]
    assert lavender and 150 < lavender[0] < 400, lavender[:3]
    assert img.pixelColor(1099, 2).name() == "#0e1430"
    assert not warnings, warnings


def test_branding_desc():
    yaml = pytest.importorskip("yaml")
    desc = yaml.safe_load((BRANDING / "branding.desc").read_text())
    assert desc["componentName"] == BRANDING.name
    assert desc["strings"]["bootloaderEntryName"].isascii()
    for key in ("productLogo", "productIcon", "productWelcome"):
        assert (BRANDING / desc["images"][key]).is_file()
    assert (BRANDING / desc["slideshow"]).is_file()
    for art in re.findall(r'art: "([^"]+)"', (BRANDING / "show.qml").read_text()):
        assert (BRANDING / art).is_file(), art
