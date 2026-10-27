// Runs once per user the first time Plasma starts: use the Yūrei wallpaper.
// Plasma remembers that it ran, so a wallpaper the user picks later stays.
const image = "file:///usr/share/wallpapers/Yurei/contents/images/3840x2160.jpg";
desktops().forEach((desktop) => {
    desktop.wallpaperPlugin = "org.kde.image";
    desktop.currentConfigGroup = ["Wallpaper", "org.kde.image", "General"];
    desktop.writeConfig("Image", image);
});
