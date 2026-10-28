"""Behaviour tests for the SDDM theme, run in Qt 6 against stand-in SDDM
objects (see sddm_harness.py). Keyboard input goes through real Qt key events.

    python3 -m pytest tests/test_sddm_theme.py
"""

import pytest

pytest.importorskip("PySide6")

from PySide6.QtCore import QEvent, QObject, Qt, QUrl, qInstallMessageHandler  # noqa: E402
from PySide6.QtGui import QGuiApplication, QKeyEvent  # noqa: E402
from PySide6.QtTest import QTest  # noqa: E402

import sddm_harness as h  # noqa: E402

warnings: list[str] = []


def _collect(mode, context, message):
    if "QQmlPropertyMap" not in message:
        warnings.append(message)


@pytest.fixture
def theme(request):
    warnings.clear()
    previous = qInstallMessageHandler(_collect)
    kwargs = getattr(request, "param", {})
    app, view, objects = h.make_view(**kwargs)
    root = view.rootObject()

    def find(name):
        item = root.findChild(QObject, name)
        assert item is not None, f"no item named {name}"
        return item

    yield app, view, objects, find
    view.setSource(QUrl())  # unload the theme before the stand-in objects go
    view.close()
    h.settle(app)
    qInstallMessageHandler(previous)
    view.deleteLater()


def type_text(app, view, text):
    for ch in text:
        key = Qt.Key(ord(ch.upper())) if ch.isalnum() else Qt.Key_unknown
        for kind in (QEvent.KeyPress, QEvent.KeyRelease):
            QGuiApplication.sendEvent(view, QKeyEvent(kind, key, Qt.NoModifier, ch))
    h.settle(app)


def press(app, view, key):
    QTest.keyClick(view, key)
    h.settle(app)


def focused(view):
    item = view.activeFocusItem()
    # TextField's internal input gets focus; report the control
    while item is not None and not item.objectName():
        item = item.parentItem()
    return item.objectName() if item else None


def test_loads_without_qml_warnings(theme):
    app, view, objects, find = theme
    h.settle(app, 60)
    assert warnings == []


def test_password_has_focus_on_start(theme):
    app, view, objects, find = theme
    assert focused(view) == "password"
    assert find("userLabel").property("text") == "Alex"


def test_wrong_password_shows_error_and_clears_field(theme):
    app, view, objects, find = theme
    type_text(app, view, "nope")
    press(app, view, Qt.Key_Return)
    assert objects["sddm"].calls == [("login", "alex", "nope", 0)]
    assert "Wrong password" in find("message").property("text")
    assert find("password").property("text") == ""
    assert focused(view) == "password"
    # typing again clears the error
    type_text(app, view, "m")
    assert find("message").property("text") == ""


def test_successful_login_uses_selected_session(theme):
    app, view, objects, find = theme
    find("session").setProperty("currentIndex", 1)  # Steam Game Mode
    find("password").forceActiveFocus()
    h.settle(app)
    type_text(app, view, h.CORRECT_PASSWORD)
    press(app, view, Qt.Key_Enter)
    assert objects["sddm"].calls == [("login", "alex", h.CORRECT_PASSWORD, 1)]
    assert find("message").property("text") == ""


def test_submit_button_logs_in(theme):
    app, view, objects, find = theme
    type_text(app, view, h.CORRECT_PASSWORD)
    QTest.keyClick(view, Qt.Key_Tab)  # focus the button, then activate it
    h.settle(app)
    assert focused(view) == "submit"
    press(app, view, Qt.Key_Return)
    assert ("login", "alex", h.CORRECT_PASSWORD, 0) in objects["sddm"].calls


def test_tab_order_reaches_every_control(theme):
    app, view, objects, find = theme
    order = []
    for _ in range(6):
        press(app, view, Qt.Key_Tab)
        order.append(focused(view))
    assert order == ["submit", "session", "suspendButton", "rebootButton", "powerButton", "password"]


def test_power_buttons(theme):
    app, view, objects, find = theme
    for name in ("suspendButton", "rebootButton", "powerButton"):
        find(name).forceActiveFocus()
        h.settle(app)
        press(app, view, Qt.Key_Space)
    assert objects["sddm"].calls == [("suspend",), ("reboot",), ("powerOff",)]


def test_caps_lock_warning(theme):
    app, view, objects, find = theme
    objects["keyboard"].set_caps(True)
    h.settle(app)
    assert find("message").property("text") == "Caps Lock is on"
    type_text(app, view, "NOPE")
    press(app, view, Qt.Key_Return)
    assert find("message").property("text") == "Wrong password - Caps Lock is on"


@pytest.mark.parametrize("theme", [{"users": [
    {"name": "alex", "realName": "Alex", "icon": ""},
    {"name": "sam", "realName": "", "icon": ""},
]}], indirect=True)
def test_arrow_keys_switch_user(theme):
    app, view, objects, find = theme
    press(app, view, Qt.Key_Right)
    assert find("userLabel").property("text") == "sam"
    type_text(app, view, "x")
    press(app, view, Qt.Key_Left)  # with text typed, arrows move the cursor instead
    assert find("userLabel").property("text") == "sam"
    press(app, view, Qt.Key_Return)
    assert objects["sddm"].calls[-1][1] == "sam"


@pytest.mark.parametrize("theme", [{"users": []}], indirect=True)
def test_username_field_when_no_users_are_listed(theme):
    app, view, objects, find = theme
    assert find("usernameField").property("visible")
    assert focused(view) == "usernameField"
    type_text(app, view, "kai")
    press(app, view, Qt.Key_Return)  # moves on to the password
    assert focused(view) == "password"
    type_text(app, view, h.CORRECT_PASSWORD)
    press(app, view, Qt.Key_Return)
    assert objects["sddm"].calls == [("login", "kai", h.CORRECT_PASSWORD, 0)]


@pytest.mark.parametrize("theme", [{"layouts": [("us", "English (US)"), ("jp", "Japanese")]}], indirect=True)
def test_keyboard_layout_button(theme):
    app, view, objects, find = theme
    button = find("layoutButton")
    assert button.property("visible")
    button.forceActiveFocus()
    h.settle(app)
    press(app, view, Qt.Key_Space)
    assert objects["keyboard"].property("currentLayout") == 1


@pytest.mark.parametrize("theme", [{"width": 1280, "height": 1024}, {"width": 3440, "height": 1440},
                                   {"width": 1080, "height": 1920}], indirect=True)
def test_login_column_stays_on_screen(theme):
    app, view, objects, find = theme
    root = view.rootObject()
    for name in ("password", "avatar", "session", "powerButton"):
        item = find(name)
        top_left = item.mapToItem(root, 0, 0)
        assert top_left.x() >= 0 and top_left.y() >= 0, name
        assert top_left.x() + item.width() <= root.width() + 1, name
        assert top_left.y() + item.height() <= root.height() + 1, name
