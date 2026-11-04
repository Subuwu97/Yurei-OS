#!/bin/sh
unset DBUS_SESSION_BUS_ADDRESS SESSION_MANAGER WAYLAND_DISPLAY
export XDG_SESSION_TYPE=x11 XDG_CURRENT_DESKTOP=KDE XDG_SESSION_DESKTOP=KDE
[ ! -r /etc/profile ] || . /etc/profile
export KDE_FULL_SESSION=true KDE_SESSION_VERSION=6
# Hyper-V presents no hardware render node to the RDP display.
export LIBGL_ALWAYS_SOFTWARE=1
exec dbus-run-session -- /usr/bin/startplasma-x11
