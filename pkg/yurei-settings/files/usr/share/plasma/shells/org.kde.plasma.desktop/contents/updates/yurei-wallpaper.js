// Runs once per user the first time Plasma starts: use the Yūrei wallpaper.
// Plasma remembers that it ran, so a wallpaper the user picks later stays.
// Pointing at the package lets Plasma pick the image size closest to the screen.
const wallpaper = "/usr/share/wallpapers/Yurei";
desktops().forEach((desktop) => {
    desktop.wallpaperPlugin = "org.kde.image";
    desktop.currentConfigGroup = ["Wallpaper", "org.kde.image", "General"];
    desktop.writeConfig("Image", wallpaper);
});
