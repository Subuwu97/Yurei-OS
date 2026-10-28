"""Loads the SDDM theme in Qt 6 with stand-ins for the objects SDDM provides
(sddm, userModel, sessionModel, keyboard, config).

    python3 tests/sddm_harness.py screenshot OUT.png [WIDTH HEIGHT]
    python3 tests/test_sddm_theme.py            # behaviour tests

Needs PySide6. Rendering uses Qt's software backend, like SDDM on a machine
without working 3D acceleration. This is a development aid: on the real
system, preview with `sddm-greeter-qt6 --test-mode --theme <dir>`.
"""

from __future__ import annotations

import os
import sys
from pathlib import Path

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")
os.environ.setdefault("QT_QUICK_BACKEND", "software")

from PySide6.QtCore import (QAbstractListModel, QByteArray, QModelIndex, QObject, QPoint, Qt,
                            QUrl, Property, Signal, Slot)
from PySide6.QtGui import QGuiApplication
from PySide6.QtQml import QQmlPropertyMap
from PySide6.QtQuick import QQuickView

THEME = Path(__file__).resolve().parent.parent / "themes" / "sddm" / "yurei"
CORRECT_PASSWORD = "moon"


class ListModel(QAbstractListModel):
    def __init__(self, roles: list[str], rows: list[dict], last_index: int = 0):
        super().__init__()
        self._roles = {Qt.UserRole + 1 + i: r.encode() for i, r in enumerate(roles)}
        self._rows = rows
        self._last = last_index

    def rowCount(self, parent=QModelIndex()):
        return len(self._rows)

    def roleNames(self):
        return {k: QByteArray(v) for k, v in self._roles.items()}

    def data(self, index, role):
        name = self._roles.get(role)
        if not index.isValid() or name is None:
            return None
        return self._rows[index.row()].get(name.decode())

    def _count(self):
        return len(self._rows)

    def _last_index(self):
        return self._last

    def _last_user(self):
        return self._rows[self._last]["name"] if self._rows else ""

    countChanged = Signal()
    count = Property(int, _count, notify=countChanged)
    lastIndex = Property(int, _last_index, constant=True)
    lastUser = Property(str, _last_user, constant=True)


class Sddm(QObject):
    loginSucceeded = Signal()
    loginFailed = Signal()

    def __init__(self):
        super().__init__()
        self.calls: list[tuple] = []

    @Slot(str, str, int)
    def login(self, user, password, session):
        self.calls.append(("login", user, password, session))
        (self.loginSucceeded if password == CORRECT_PASSWORD else self.loginFailed).emit()

    @Slot()
    def powerOff(self):
        self.calls.append(("powerOff",))

    @Slot()
    def reboot(self):
        self.calls.append(("reboot",))

    @Slot()
    def suspend(self):
        self.calls.append(("suspend",))

    def _true(self):
        return True

    canPowerOff = Property(bool, _true, constant=True)
    canReboot = Property(bool, _true, constant=True)
    canSuspend = Property(bool, _true, constant=True)
    hostName = Property(str, lambda self: "yurei", constant=True)


class Layout(QObject):
    def __init__(self, short, long):
        super().__init__()
        self._short, self._long = short, long

    shortName = Property(str, lambda self: self._short, constant=True)
    longName = Property(str, lambda self: self._long, constant=True)


class Keyboard(QObject):
    changed = Signal()

    def __init__(self, layouts):
        super().__init__()
        self._layouts = [Layout(s, l) for s, l in layouts]
        self._current = 0
        self._caps = False

    def _get_current(self):
        return self._current

    def _set_current(self, value):
        self._current = value
        self.changed.emit()

    def _get_caps(self):
        return self._caps

    def set_caps(self, value):
        self._caps = value
        self.changed.emit()

    layouts = Property(list, lambda self: self._layouts, notify=changed)
    currentLayout = Property(int, _get_current, _set_current, notify=changed)
    capsLock = Property(bool, _get_caps, notify=changed)
    numLock = Property(bool, lambda self: False, notify=changed)


def make_view(width=1920, height=1080, users=None, layouts=(("us", "English (US)"),),
              force_user_field=False):
    app = QGuiApplication.instance() or QGuiApplication(sys.argv)
    view = QQuickView()
    view.setResizeMode(QQuickView.SizeRootObjectToView)
    ctx = view.rootContext()
    if users is None:
        users = [{"name": "alex", "realName": "Alex", "icon": "", "homeDir": "/home/alex", "needsPassword": True}]
    objects = {
        "sddm": Sddm(),
        "userModel": ListModel(["name", "realName", "icon", "homeDir", "needsPassword"], users),
        "sessionModel": ListModel(["name", "file"], [
            {"name": "Plasma (Wayland)", "file": "plasma.desktop"},
            {"name": "Steam Game Mode (Yūrei)", "file": "yurei-steam.desktop"},
            {"name": "Plasma (X11)", "file": "plasmax11.desktop"},
        ]),
        "keyboard": Keyboard(layouts),
    }
    config = QQmlPropertyMap()
    config.insert("background", "assets/background.jpg")
    config.insert("forceUserField", "true" if force_user_field else "false")
    objects["config"] = config
    for name, obj in objects.items():
        ctx.setContextProperty(name, obj)
    view.setSource(QUrl.fromLocalFile(str(THEME / "Main.qml")))
    if view.status() != QQuickView.Ready:
        raise RuntimeError("\n".join(e.toString() for e in view.errors()))
    view.resize(width, height)
    view.show()
    settle(app)
    view._objects = objects  # keep Python objects alive
    return app, view, objects


def settle(app, rounds=30):
    for _ in range(rounds):
        app.processEvents()


def screenshot(view, path):
    settle(QGuiApplication.instance())
    view.grabWindow().save(str(path))


if __name__ == "__main__":
    if len(sys.argv) >= 3 and sys.argv[1] == "screenshot":
        w, h = (int(sys.argv[3]), int(sys.argv[4])) if len(sys.argv) >= 5 else (1920, 1080)
        app, view, _ = make_view(w, h)
        screenshot(view, sys.argv[2])
        print(sys.argv[2])
    else:
        print(__doc__)
