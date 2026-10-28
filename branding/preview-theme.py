#!/usr/bin/env python3
"""Draws a preview of the Yūrei colour scheme and Konsole colours on real Qt
widgets over the wallpaper, for docs/previews/theme.jpg.

    python3 branding/preview-theme.py [OUT]

This shows the palette; the real desktop draws its own window borders,
panels and fonts. Needs PySide6.
"""

import configparser
import os
import sys
from pathlib import Path

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")

from PySide6.QtCore import QRect, Qt  # noqa: E402
from PySide6.QtGui import QColor, QFont, QImage, QPainter, QPalette  # noqa: E402
from PySide6.QtWidgets import (QApplication, QCheckBox, QComboBox, QFrame, QHBoxLayout, QLabel,  # noqa: E402
                               QLineEdit, QListWidget, QProgressBar, QPushButton, QSlider,
                               QVBoxLayout, QWidget)

ROOT = Path(__file__).resolve().parent.parent
FILES = ROOT / "pkg/yurei-settings/files"


def load(path):
    cfg = configparser.ConfigParser(interpolation=None, strict=False)
    cfg.optionxform = str
    cfg.read(path)
    return cfg


def rgb(value):
    return QColor(*[int(v) for v in value.split(",")])


def palette(scheme):
    def c(group, key):
        return rgb(scheme[f"Colors:{group}"][key])
    p = QPalette()
    p.setColor(QPalette.Window, c("Window", "BackgroundNormal"))
    p.setColor(QPalette.WindowText, c("Window", "ForegroundNormal"))
    p.setColor(QPalette.Base, c("View", "BackgroundNormal"))
    p.setColor(QPalette.AlternateBase, c("View", "BackgroundAlternate"))
    p.setColor(QPalette.Text, c("View", "ForegroundNormal"))
    p.setColor(QPalette.PlaceholderText, c("View", "ForegroundInactive"))
    p.setColor(QPalette.Button, c("Button", "BackgroundNormal"))
    p.setColor(QPalette.ButtonText, c("Button", "ForegroundNormal"))
    p.setColor(QPalette.Highlight, c("Selection", "BackgroundNormal"))
    p.setColor(QPalette.HighlightedText, c("Selection", "ForegroundNormal"))
    p.setColor(QPalette.ToolTipBase, c("Tooltip", "BackgroundNormal"))
    p.setColor(QPalette.ToolTipText, c("Tooltip", "ForegroundNormal"))
    p.setColor(QPalette.Link, c("View", "ForegroundLink"))
    p.setColor(QPalette.Light, c("Button", "BackgroundAlternate"))
    p.setColor(QPalette.Mid, c("Window", "BackgroundAlternate"))
    p.setColor(QPalette.Dark, c("Complementary", "BackgroundNormal"))
    p.setColor(QPalette.Accent, c("Selection", "BackgroundNormal"))
    return p


def settings_window(scheme):
    w = QWidget()
    w.setFixedSize(760, 470)
    outer = QHBoxLayout(w)
    outer.setContentsMargins(0, 0, 0, 0)
    outer.setSpacing(0)
    side = QListWidget()
    side.setFixedWidth(210)
    side.addItems(["Appearance", "Colours & Themes", "Display", "Sound", "Gaming", "Network", "About Yūrei"])
    side.setCurrentRow(1)
    side.setFrameShape(QFrame.NoFrame)
    side.setSpacing(5)
    side.setStyleSheet("QListWidget { padding: 10px 8px; } QListWidget::item { padding: 4px 8px; border-radius: 6px; } "
                       "QListWidget::item:selected { background: palette(highlight); color: palette(highlighted-text); }")
    outer.addWidget(side)
    body = QVBoxLayout()
    body.setContentsMargins(24, 20, 24, 20)
    body.setSpacing(14)
    title = QLabel("Colours & Themes")
    f = title.font()
    f.setPointSize(15)
    f.setBold(True)
    title.setFont(f)
    body.addWidget(title)
    body.addWidget(QLabel('Global theme: <b>Yūrei</b> &nbsp; <a href="#">Get new themes…</a>'))
    search = QLineEdit()
    search.setPlaceholderText("Search…")
    body.addWidget(search)
    row = QHBoxLayout()
    combo = QComboBox()
    combo.addItems(["Yūrei", "Breeze Dark", "Breeze"])
    row.addWidget(combo)
    apply = QPushButton("Apply")
    apply.setDefault(True)
    row.addWidget(apply)
    row.addWidget(QPushButton("Reset"))
    body.addLayout(row)
    for text, on in (("Accent colour from the theme", True), ("Blur behind panels", True), ("Reduce animations", False)):
        box = QCheckBox(text)
        box.setChecked(on)
        body.addWidget(box)
    slider = QSlider(Qt.Horizontal)
    slider.setValue(65)
    body.addWidget(slider)
    bar = QProgressBar()
    bar.setValue(72)
    bar.setFormat("Downloading Proton…  %p%")
    body.addWidget(bar)
    status = QLabel()
    sel = scheme["Colors:Window"]
    status.setText(f'<span style="color:rgb({sel["ForegroundPositive"]})">● Up to date</span> &nbsp; '
                   f'<span style="color:rgb({sel["ForegroundNeutral"]})">● 3 updates</span> &nbsp; '
                   f'<span style="color:rgb({sel["ForegroundNegative"]})">● 1 error</span>')
    body.addWidget(status)
    body.addStretch()
    outer.addLayout(body)
    return w


def draw_window(painter, scheme, widget, x, y, title):
    header = scheme["Colors:Header"]
    radius_rect = QRect(x, y, widget.width(), widget.height() + 34)
    painter.setPen(Qt.NoPen)
    painter.setBrush(QColor(0, 0, 0, 90))
    painter.drawRoundedRect(radius_rect.adjusted(-2, 6, 8, 14), 10, 10)  # shadow
    painter.setBrush(rgb(header["BackgroundNormal"]))
    painter.drawRoundedRect(QRect(x, y, widget.width(), 44), 8, 8)
    painter.setPen(rgb(header["ForegroundNormal"]))
    f = QFont()
    f.setPointSize(10)
    painter.setFont(f)
    painter.drawText(QRect(x, y, widget.width(), 34), Qt.AlignCenter, title)
    for i, colour in enumerate((header["ForegroundInactive"],) * 2 + (header["DecorationHover"],)):
        painter.setBrush(rgb(colour))
        painter.setPen(Qt.NoPen)
        painter.drawEllipse(x + widget.width() - 84 + i * 26, y + 11, 13, 13)
    painter.drawImage(x, y + 34, widget.grab().toImage())


def draw_terminal(painter, konsole, x, y, w, h):
    def k(name):
        return rgb(konsole[name]["Color"])
    bg = k("Background")
    bg.setAlpha(240)
    painter.setPen(Qt.NoPen)
    painter.setBrush(QColor(0, 0, 0, 90))
    painter.drawRoundedRect(QRect(x - 2, y + 6, w + 10, h + 14), 10, 10)
    painter.setBrush(bg)
    painter.drawRoundedRect(QRect(x, y, w, h), 8, 8)
    f = QFont("DejaVu Sans Mono")
    f.setPixelSize(15)
    painter.setFont(f)
    lines = [
        [("Color5", "ana@yurei"), ("Foreground", " ~ "), ("Color4", "❯ "), ("Foreground", "yurei status")],
        [("Color6", "  Kernel   "), ("Foreground", "linux-cachyos 6.18 (BORE)")],
        [("Color6", "  GPU      "), ("Foreground", "AMD Radeon RX 7800 XT")],
        [("Color6", "  GameMode "), ("Color2", "ready")],
        [("Color6", "  Updates  "), ("Color3", "3 available")],
        [],
        [("Color5", "ana@yurei"), ("Foreground", " ~ "), ("Color4", "❯ "), ("Foreground", "ls")],
        [("Color4", "Desktop  Games  Music  "), ("Color2", "run.sh  "), ("Color1", "broken-link")],
        [("Color5", "ana@yurei"), ("Foreground", " ~ "), ("Color4", "❯ "), ("Color7Intense", "█")],
    ]
    for row, parts in enumerate(lines):
        cx = x + 18
        for name, text in parts:
            painter.setPen(k(name))
            painter.drawText(cx, y + 32 + row * 24, text)
            cx += painter.fontMetrics().horizontalAdvance(text)


def main():
    out = Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / "docs/previews/theme.jpg"
    app = QApplication(["preview", "-platform", "offscreen"])
    app.setStyle("Fusion")
    scheme = load(FILES / "usr/share/color-schemes/Yurei.colors")
    konsole = load(FILES / "usr/share/konsole/Yurei.colorscheme")
    app.setPalette(palette(scheme))
    wallpaper = sorted((FILES / "usr/share/wallpapers/Yurei/contents/images").glob("*.jpg"))[0]
    canvas = QImage(str(wallpaper)).scaled(1672, 941, Qt.IgnoreAspectRatio, Qt.SmoothTransformation)
    painter = QPainter(canvas)
    painter.setRenderHint(QPainter.Antialiasing)
    win = settings_window(scheme)
    win.show()
    app.processEvents()
    draw_window(painter, scheme, win, 70, 90, "System Settings")
    draw_terminal(painter, konsole, 870, 330, 560, 250)
    painter.end()
    canvas.save(str(out), quality=88)
    print(f"wrote {out}")


if __name__ == "__main__":
    main()
