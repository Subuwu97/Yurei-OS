# Starts the desktop after logging in on the first screen (tty1). Press a
# key within 3 seconds to stay in the console; to stop it for good, create
# ~/.config/yurei/no-desktop. Logging out of the desktop returns here.
if [ "$(tty)" = /dev/tty1 ] && [ -z "$WAYLAND_DISPLAY" ] && [ -z "$YUREI_NO_DESKTOP" ] \
   && [ ! -e "$HOME/.config/yurei/no-desktop" ] && command -v yurei-desktop > /dev/null; then
    printf '\n  Starting the desktop… (press any key within 3 seconds to stay in the console)\n'
    if [ -n "$BASH_VERSION" ] && ! read -r -s -t 3 -n 1 _; then
        yurei-desktop
    fi
fi
