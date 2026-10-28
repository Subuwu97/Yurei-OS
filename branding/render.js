// Renders the desktop wallpaper shipped in yurei-settings from wallpaper.svg.
// (The boot menu, boot animation and login artwork come from
// build-assets.py and the mascot art in branding/source/.)
// Usage: node branding/render.js   (needs Playwright with Chromium)
const { chromium } = require("playwright");
const path = require("path");
const fs = require("fs");

const root = path.join(__dirname, "..");
const wallpaper = fs.readFileSync(path.join(__dirname, "wallpaper.svg"), "utf8");

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

  await browser.close();
})();
