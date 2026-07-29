#!/usr/bin/env node

const fs = require("fs");
const path = require("path");
const sharp = require("sharp");

const repo = path.resolve(__dirname, "..");
const sourcePath = path.join(
  __dirname,
  "brand",
  "soft-connect-logo-source.svg",
);
const buildDir = path.join(__dirname, ".icon-build");

const source = fs.readFileSync(sourcePath, "utf8");
const pathMatch = source.match(/<path class="fil0" d="([\s\S]*?)"\/>/);
if (!pathMatch) {
  throw new Error(`Could not find the CorelDRAW logo path in ${sourcePath}`);
}
const foxPath = pathMatch[1];

const commonDefs = `
  <linearGradient id="bg" x1="92" y1="54" x2="936" y2="970" gradientUnits="userSpaceOnUse">
    <stop stop-color="#112D4B"/>
    <stop offset="0.5" stop-color="#071827"/>
    <stop offset="1" stop-color="#030A12"/>
  </linearGradient>
  <linearGradient id="frame" x1="174" y1="170" x2="850" y2="716" gradientUnits="userSpaceOnUse">
    <stop stop-color="#4BE8FF"/>
    <stop offset="0.54" stop-color="#1786FF"/>
    <stop offset="1" stop-color="#7058FF"/>
  </linearGradient>
  <linearGradient id="fox" gradientUnits="userSpaceOnUse" x1="6108.4" y1="3469.54" x2="4570.89" y2="-735.29">
    <stop stop-color="#FF6A29"/>
    <stop offset="1" stop-color="#FFB200"/>
  </linearGradient>
  <filter id="foxshadow" x="-30%" y="-30%" width="160%" height="170%">
    <feDropShadow dx="0" dy="28" stdDeviation="28" flood-color="#FF7A1A" flood-opacity="0.32"/>
  </filter>`;

function fox(x, y, width, height, fill = "url(#fox)", filter = "") {
  return `<svg x="${x}" y="${y}" width="${width}" height="${height}" viewBox="0 0 2824 2734.25" overflow="hidden">
    <path d="${foxPath}" fill="${fill}"${filter ? ` filter="${filter}"` : ""}/>
  </svg>`;
}

function appIconSvg() {
  return `<?xml version="1.0" encoding="UTF-8"?>
<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">
  <defs>${commonDefs}</defs>
  <rect x="30" y="30" width="964" height="964" rx="224" fill="url(#bg)"/>
  <rect x="48" y="48" width="928" height="928" rx="207" fill="none" stroke="#31526E" stroke-width="7" opacity="0.72"/>
  <rect x="174" y="166" width="676" height="548" rx="112" fill="#050F1B" stroke="#163A59" stroke-width="24"/>
  <path d="M286 166h-45a67 67 0 0 0-67 67v76M738 166h45a67 67 0 0 1 67 67v76M174 571v76a67 67 0 0 0 67 67h45M850 571v76a67 67 0 0 1-67 67h-45"
        fill="none" stroke="url(#frame)" stroke-width="28" stroke-linecap="round"/>
  <circle cx="786" cy="226" r="16" fill="#31E7B1"/>
  <circle cx="786" cy="226" r="29" fill="none" stroke="#31E7B1" stroke-width="7" opacity="0.24"/>
  <path d="M512 714v84M407 818h210" fill="none" stroke="#355A79" stroke-width="30" stroke-linecap="round"/>
  ${fox(270, 244, 484, 393, "url(#fox)", "url(#foxshadow)")}
</svg>`;
}

function smallIconSvg() {
  return `<?xml version="1.0" encoding="UTF-8"?>
<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">
  <defs>${commonDefs}</defs>
  <rect x="30" y="30" width="964" height="964" rx="224" fill="url(#bg)"/>
  <rect x="52" y="52" width="920" height="920" rx="202" fill="none" stroke="#31526E" stroke-width="10" opacity="0.78"/>
  <path d="M286 154h-60a72 72 0 0 0-72 72v92M738 154h60a72 72 0 0 1 72 72v92M154 706v92a72 72 0 0 0 72 72h60M870 706v92a72 72 0 0 1-72 72h-60"
        fill="none" stroke="url(#frame)" stroke-width="40" stroke-linecap="round"/>
  ${fox(182, 244, 660, 536, "url(#fox)")}
</svg>`;
}

function roundIconSvg() {
  return `<?xml version="1.0" encoding="UTF-8"?>
<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">
  <defs>${commonDefs}</defs>
  <circle cx="512" cy="512" r="494" fill="url(#bg)"/>
  <circle cx="512" cy="512" r="474" fill="none" stroke="#31526E" stroke-width="8" opacity="0.72"/>
  <path d="M306 174h-64a68 68 0 0 0-68 68v82M718 174h64a68 68 0 0 1 68 68v82M174 700v82a68 68 0 0 0 68 68h64M850 700v82a68 68 0 0 1-68 68h-64"
        fill="none" stroke="url(#frame)" stroke-width="32" stroke-linecap="round"/>
  ${fox(222, 277, 580, 471, "url(#fox)", "url(#foxshadow)")}
</svg>`;
}

function adaptiveForegroundSvg() {
  return `<?xml version="1.0" encoding="UTF-8"?>
<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">
  <defs>${commonDefs}</defs>
  <rect x="190" y="190" width="644" height="588" rx="118" fill="#050F1B" stroke="#163A59" stroke-width="22"/>
  <path d="M310 190h-49a71 71 0 0 0-71 71v74M714 190h49a71 71 0 0 1 71 71v74M190 633v74a71 71 0 0 0 71 71h49M834 633v74a71 71 0 0 1-71 71h-49"
        fill="none" stroke="url(#frame)" stroke-width="30" stroke-linecap="round"/>
  <circle cx="770" cy="250" r="15" fill="#31E7B1"/>
  ${fox(266, 285, 492, 399, "url(#fox)", "url(#foxshadow)")}
</svg>`;
}

function traySvg(color = "#FF9A16", background = true) {
  return `<?xml version="1.0" encoding="UTF-8"?>
<svg xmlns="http://www.w3.org/2000/svg" width="256" height="256" viewBox="0 0 1024 1024">
  ${background ? '<circle cx="512" cy="512" r="470" fill="#071827"/><circle cx="512" cy="512" r="438" fill="none" stroke="#24506F" stroke-width="32"/>' : ""}
  ${fox(background ? 154 : 62, background ? 222 : 147, background ? 716 : 900, background ? 581 : 730, color)}
</svg>`;
}

function notificationSvg() {
  return `<?xml version="1.0" encoding="UTF-8"?>
<svg xmlns="http://www.w3.org/2000/svg" width="256" height="256" viewBox="0 0 1024 1024">
  ${fox(154, 222, 716, 581, "#FFFFFF")}
</svg>`;
}

async function render(svg, size, output) {
  await sharp(Buffer.from(svg))
    .resize(size, size, { fit: "fill" })
    .png()
    .toFile(output);
}

async function wordmark(iconPng, color, output) {
  const iconData = iconPng.toString("base64");
  const svg = `<svg xmlns="http://www.w3.org/2000/svg" width="555" height="111" viewBox="0 0 555 111">
    <image x="5" y="5" width="101" height="101" href="data:image/png;base64,${iconData}"/>
    <text x="126" y="70" fill="${color}" font-family="Segoe UI, Arial, sans-serif" font-size="45" font-weight="600" letter-spacing="-1">SOFT.Connect.Desk</text>
  </svg>`;
  await sharp(Buffer.from(svg)).png().toFile(output);
}

async function main() {
  fs.mkdirSync(buildDir, { recursive: true });

  const appSvg = appIconSvg();
  const smallSvg = smallIconSvg();
  const roundSvg = roundIconSvg();
  const foregroundSvg = adaptiveForegroundSvg();
  const trayColorSvg = traySvg("#FFAA00", false);
  const trayTemplateSvg = traySvg("#000000", false);
  const notifySvg = notificationSvg();

  for (const output of [
    path.join(__dirname, "icon-master.svg"),
    path.join(__dirname, "scalable.svg"),
    path.join(__dirname, "logo.svg"),
    path.join(__dirname, "logo-header.svg"),
    path.join(repo, "flutter", "assets", "icon.svg"),
  ]) {
    fs.writeFileSync(output, appSvg);
  }

  const standardOutputs = [
    [1024, path.join(__dirname, "icon.png")],
    [1024, path.join(__dirname, "mac-icon.png")],
    [256, path.join(__dirname, "128x128@2x.png")],
    [128, path.join(__dirname, "128x128.png")],
    [64, path.join(__dirname, "64x64.png")],
    [512, path.join(repo, "flutter", "assets", "icon.png")],
    [512, path.join(repo, "fastlane", "metadata", "android", "en-US", "images", "icon.png")],
  ];
  for (const [size, output] of standardOutputs) {
    await render(appSvg, size, output);
  }
  await render(smallSvg, 32, path.join(__dirname, "32x32.png"));

  const appFrames = [16, 24, 32, 48, 64, 128, 256];
  for (const size of appFrames) {
    await render(
      size <= 32 ? smallSvg : appSvg,
      size,
      path.join(buildDir, `app-${size}.png`),
    );
  }
  for (const size of appFrames) {
    await render(trayColorSvg, size, path.join(buildDir, `tray-${size}.png`));
  }
  await render(appSvg, 1024, path.join(buildDir, "app-1024.png"));

  await render(trayTemplateSvg, 44, path.join(__dirname, "mac-tray-dark-x2.png"));
  await render(trayTemplateSvg, 44, path.join(__dirname, "mac-tray-light-x2.png"));

  const android = path.join(repo, "flutter", "android", "app", "src", "main", "res");
  const densities = {
    mdpi: [48, 108, 24],
    hdpi: [72, 162, 36],
    xhdpi: [96, 216, 48],
    xxhdpi: [144, 324, 72],
    xxxhdpi: [192, 432, 96],
  };
  for (const [density, [launcher, foreground, notification]] of Object.entries(densities)) {
    const dir = path.join(android, `mipmap-${density}`);
    await render(appSvg, launcher, path.join(dir, "ic_launcher.png"));
    await render(roundSvg, launcher, path.join(dir, "ic_launcher_round.png"));
    await render(foregroundSvg, foreground, path.join(dir, "ic_launcher_foreground.png"));
    await render(notifySvg, notification, path.join(dir, "ic_stat_logo.png"));
  }

  const icon100 = await sharp(Buffer.from(appSvg)).resize(101, 101).png().toBuffer();
  await wordmark(icon100, "#061A32", path.join(repo, "flutter", "assets", "logo.png"));
  await wordmark(icon100, "#F7FAFF", path.join(repo, "flutter", "assets", "logo_dark.png"));
  await wordmark(icon100, "#061A32", path.join(repo, "flutter", "assets", "logo_light.png"));

  const preview = await sharp(Buffer.from(appSvg)).resize(512, 512).png().toBuffer();
  fs.writeFileSync(path.join(__dirname, "brand", "soft-connect-desk-icon-preview.png"), preview);

  const previewVariants = [
    ["Desktop / Linux / macOS", appSvg],
    ["Small 16–32 px", smallSvg],
    ["Round launcher", roundSvg],
    ["Android foreground", foregroundSvg],
    ["System tray", trayColorSvg],
  ];
  const sheetComposites = [];
  for (const [index, [label, svg]] of previewVariants.entries()) {
    const left = 36 + index * 238;
    const icon = await sharp(Buffer.from(svg)).resize(180, 180).png().toBuffer();
    const card = Buffer.from(`<svg xmlns="http://www.w3.org/2000/svg" width="216" height="260">
      <rect x="1" y="1" width="214" height="258" rx="24" fill="#0B1724" stroke="#24435D" stroke-width="2"/>
      <text x="108" y="232" text-anchor="middle" fill="#DDEBFA"
            font-family="Segoe UI, Arial, sans-serif" font-size="16" font-weight="600">${label}</text>
    </svg>`);
    sheetComposites.push({ input: card, left, top: 70 });
    sheetComposites.push({ input: icon, left: left + 18, top: 88 });
  }
  sheetComposites.unshift({
    input: Buffer.from(`<svg xmlns="http://www.w3.org/2000/svg" width="1220" height="54">
      <text x="28" y="38" fill="#F4F8FC" font-family="Segoe UI, Arial, sans-serif"
            font-size="27" font-weight="700">SOFT.Connect.Desk — icon family preview</text>
    </svg>`),
    left: 0,
    top: 0,
  });
  await sharp({
    create: {
      width: 1264,
      height: 366,
      channels: 4,
      background: "#050B12",
    },
  })
    .composite(sheetComposites)
    .png()
    .toFile(path.join(__dirname, "brand", "soft-connect-desk-icon-family.png"));
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
