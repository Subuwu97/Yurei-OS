// Renders the branding artwork shipped with Yūrei:
//   - the desktop wallpaper (yurei-settings package)
//   - the boot menu background (overlay/boot/splash.png, used by build.sh)
// Usage: node branding/render.js   (needs Playwright with Chromium)
const { chromium } = require("playwright");
const path = require("path");
const fs = require("fs");

const root = path.join(__dirname, "..");
const wallpaper = fs.readFileSync(path.join(__dirname, "wallpaper.svg"), "utf8");
const logo = fs.readFileSync(path.join(__dirname, "logo.svg"), "utf8");

async function render(browser, width, height, html, out, type) {
  fs.mkdirSync(path.dirname(out), { recursive: true });
  const page = await browser.newPage({ viewport: { width, height } });
  await page.setContent(html);
  await page.screenshot({ path: out, type, ...(type === "jpeg" ? { quality: 90 } : {}) });
  await page.close();
  console.log(path.relative(root, out));
}

(async () => {
  const browser = await chromium.launch();
  await render(browser, 3840, 2160, `<body style="margin:0">${wallpaper}</body>`,
    path.join(root, "pkg/yurei-settings/files/usr/share/wallpapers/Yurei/contents/images/3840x2160.jpg"), "jpeg");

  // Boot menu: same scene scaled down, logo and name in the top-left corner,
  // leaving the centre free for the menu entries.
  const scaled = wallpaper.replace('width="3840" height="2160"', 'width="1920" height="1080"');
  await render(browser, 1920, 1080, `<body style="margin:0;position:relative">${scaled}
    <div style="position:absolute;left:72px;top:64px;display:flex;align-items:center;gap:24px;
                font:600 54px system-ui,sans-serif;color:#f4f1ff;letter-spacing:.02em">
      <div style="width:96px;height:96px">${logo}</div>Yūrei</div></body>`,
    path.join(root, "overlay/boot/splash.png"), "png");
  await browser.close();
})();
