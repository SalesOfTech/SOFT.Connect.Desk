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
// CorelDRAW exported the fox and the wordmark as one compound path. Every
// subpath after the first starts with a relative `m`, so normalise those moves
// to absolute coordinates before discarding all wordmark geometry.
const compoundSubpaths = pathMatch[1].replace(/z(?=m)/g, "z|").split("|");
let subpathX = 0;
let subpathY = 0;
const absoluteSubpaths = compoundSubpaths.map((subpath) => {
  const move = subpath.match(
    /^([Mm])\s*(-?\d+(?:\.\d+)?)\s*[ ,]\s*(-?\d+(?:\.\d+)?)/,
  );
  if (!move) {
    throw new Error(`Could not parse a CorelDRAW subpath in ${sourcePath}`);
  }
  const moveX = Number(move[2]);
  const moveY = Number(move[3]);
  if (move[1] === "M") {
    subpathX = moveX;
    subpathY = moveY;
  } else {
    subpathX += moveX;
    subpathY += moveY;
  }
  return {
    x: subpathX,
    path: `M${subpathX} ${subpathY}${subpath.slice(move[0].length)}`,
  };
});
const foxSubpaths = absoluteSubpaths
  .filter(({ x }) => x < 3000)
  .map(({ path: subpath }) => subpath);
if (foxSubpaths.length === 0 || foxSubpaths.length === compoundSubpaths.length) {
  throw new Error(`Could not isolate the fox geometry in ${sourcePath}`);
}
const foxPath = foxSubpaths.join("");

const commonDefs = `
  <linearGradient id="bg" x1="92" y1="54" x2="936" y2="970" gradientUnits="userSpaceOnUse">
    <stop stop-color="#112D4B"/>
    <stop offset="0.5" stop-color="#071827"/>
    <stop offset="1" stop-color="#030A12"/>
  </linearGradient>
  <linearGradient id="connection" x1="690" y1="684" x2="890" y2="892" gradientUnits="userSpaceOnUse">
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
  <rect x="34" y="34" width="956" height="956" rx="228" fill="url(#bg)"/>
  <rect x="54" y="54" width="916" height="916" rx="208" fill="none" stroke="#2A4A64" stroke-width="8" opacity="0.82"/>
  ${fox(208, 188, 608, 589, "url(#fox)", "url(#foxshadow)")}
  <circle cx="794" cy="790" r="126" fill="#071827"/>
  <circle cx="794" cy="790" r="108" fill="url(#connection)"/>
  <path d="M767 770l50 43" fill="none" stroke="#FFFFFF" stroke-width="15" stroke-linecap="round"/>
  <circle cx="752" cy="758" r="18" fill="#FFFFFF"/>
  <circle cx="832" cy="826" r="18" fill="#FFFFFF"/>
</svg>`;
}

function smallIconSvg() {
  return `<?xml version="1.0" encoding="UTF-8"?>
<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">
  <defs>${commonDefs}</defs>
  <rect x="34" y="34" width="956" height="956" rx="228" fill="url(#bg)"/>
  <rect x="58" y="58" width="908" height="908" rx="202" fill="none" stroke="#2A4A64" stroke-width="12" opacity="0.88"/>
  ${fox(202, 218, 620, 600, "url(#fox)")}
</svg>`;
}

// The regular composition is too detailed at 16 px. Keep the original fox,
// but enlarge it and remove the connection badge and decorative border so the
// product mark remains recognisable in captions and the system tray.
function microIconSvg() {
  return `<?xml version="1.0" encoding="UTF-8"?>
<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">
  <defs>${commonDefs}</defs>
  <rect x="20" y="20" width="984" height="984" rx="226" fill="url(#bg)"/>
  ${fox(70, 84, 884, 856, "url(#fox)")}
</svg>`;
}

// The in-app desktop title bar renders this mark at only 16 logical pixels.
// A background tile and the regular app-icon padding make the fox too small
// and blurry there, so keep a dedicated edge-to-edge vector asset.
function foxOnlySvg() {
  return `<?xml version="1.0" encoding="UTF-8"?>
<svg xmlns="http://www.w3.org/2000/svg" width="2824" height="2824" viewBox="0 -44.875 2824 2824">
  <defs>${commonDefs}</defs>
  <path d="${foxPath}" fill="url(#fox)"/>
</svg>`;
}

function roundIconSvg() {
  return `<?xml version="1.0" encoding="UTF-8"?>
<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">
  <defs>${commonDefs}</defs>
  <circle cx="512" cy="512" r="494" fill="url(#bg)"/>
  <circle cx="512" cy="512" r="470" fill="none" stroke="#2A4A64" stroke-width="9" opacity="0.82"/>
  ${fox(214, 204, 596, 577, "url(#fox)", "url(#foxshadow)")}
  <circle cx="790" cy="786" r="122" fill="#071827"/>
  <circle cx="790" cy="786" r="102" fill="url(#connection)"/>
  <path d="M764 768l48 41" fill="none" stroke="#FFFFFF" stroke-width="15" stroke-linecap="round"/>
  <circle cx="750" cy="756" r="17" fill="#FFFFFF"/>
  <circle cx="826" cy="821" r="17" fill="#FFFFFF"/>
</svg>`;
}

function adaptiveForegroundSvg() {
  return `<?xml version="1.0" encoding="UTF-8"?>
<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">
  <defs>${commonDefs}</defs>
  ${fox(246, 232, 532, 515, "url(#fox)", "url(#foxshadow)")}
  <circle cx="748" cy="744" r="108" fill="#071827"/>
  <circle cx="748" cy="744" r="91" fill="url(#connection)"/>
  <path d="M725 728l42 36" fill="none" stroke="#FFFFFF" stroke-width="13" stroke-linecap="round"/>
  <circle cx="713" cy="718" r="15" fill="#FFFFFF"/>
  <circle cx="780" cy="775" r="15" fill="#FFFFFF"/>
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

function dilateRgba(data, width, height, radius) {
  const output = Buffer.alloc(data.length);
  for (let y = 0; y < height; y += 1) {
    for (let x = 0; x < width; x += 1) {
      let sourceOffset = (y * width + x) * 4;
      let alpha = data[sourceOffset + 3];
      for (let dy = -radius; dy <= radius; dy += 1) {
        for (let dx = -radius; dx <= radius; dx += 1) {
          if (dx * dx + dy * dy > radius * radius) continue;
          const sourceX = x + dx;
          const sourceY = y + dy;
          if (
            sourceX >= 0 &&
            sourceX < width &&
            sourceY >= 0 &&
            sourceY < height
          ) {
            const candidateOffset = (sourceY * width + sourceX) * 4;
            const candidateAlpha = data[candidateOffset + 3];
            if (candidateAlpha > alpha) {
              alpha = candidateAlpha;
              sourceOffset = candidateOffset;
            }
          }
        }
      }
      const outputOffset = (y * width + x) * 4;
      output[outputOffset] = data[sourceOffset];
      output[outputOffset + 1] = data[sourceOffset + 1];
      output[outputOffset + 2] = data[sourceOffset + 2];
      output[outputOffset + 3] = alpha;
    }
  }
  return output;
}

// RustDesk's compact mark consists of two heavy shapes, whereas the fox has
// much finer internal geometry. Thicken its alpha mask by one supersampled
// pixel before the final high-quality downscale. This is only 0.25 physical
// pixels, enough to keep the lines readable without jagged thresholding.
async function renderSmoothSmall(svg, size, output) {
  const supersampling = 4;
  const workingSize = size * supersampling;
  const png = await sharp(Buffer.from(svg))
    .resize(workingSize, workingSize, { fit: "fill" })
    .png()
    .toBuffer();
  const { data, info } = await sharp(png)
    .ensureAlpha()
    .raw()
    .toBuffer({ resolveWithObject: true });
  const rgba = dilateRgba(data, info.width, info.height, 1);
  await sharp(rgba, {
    raw: { width: info.width, height: info.height, channels: 4 },
  })
    .resize(size, size, { kernel: sharp.kernel.lanczos3 })
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
  const microSvg = microIconSvg();
  const titleSvg = foxOnlySvg();
  const roundSvg = roundIconSvg();
  const foregroundSvg = adaptiveForegroundSvg();
  // The Windows notification area is already constrained to a tiny square.
  // Reuse the edge-to-edge title mark so the fox is not reduced twice by an
  // additional background tile and padding.
  const trayColorSvg = titleSvg;
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
  fs.writeFileSync(
    path.join(repo, "flutter", "assets", "title-icon.svg"),
    titleSvg,
  );
  fs.writeFileSync(
    path.join(__dirname, "brand", "soft-connect-fox.svg"),
    titleSvg,
  );

  const standardOutputs = [
    [1024, path.join(__dirname, "icon.png")],
    [1024, path.join(__dirname, "mac-icon.png")],
    [256, path.join(__dirname, "128x128@2x.png")],
    [128, path.join(__dirname, "128x128.png")],
    [64, path.join(__dirname, "64x64.png")],
    [512, path.join(repo, "flutter", "assets", "icon.png")],
    [512, path.join(repo, "fastlane", "metadata", "android", "en-US", "images", "icon.png")],
  ];
  for (const [size, output, sourceSvg = appSvg] of standardOutputs) {
    await render(sourceSvg, size, output);
  }
  // Windows uses this file directly for the notification area. Supplying a
  // tray-sized source avoids the shell downscaling a detailed 256 px image.
  await renderSmoothSmall(
    trayColorSvg,
    16,
    path.join(repo, "flutter", "assets", "tray-icon.png"),
  );
  for (const size of [16, 20, 24, 32, 40, 48]) {
    const output = path.join(
      repo,
      "flutter",
      "assets",
      `tray-icon-${size}.png`,
    );
    await renderSmoothSmall(trayColorSvg, size, output);
  }
  await render(smallSvg, 32, path.join(__dirname, "32x32.png"));

  const appFrames = [16, 24, 32, 48, 64, 128, 256];
  for (const size of appFrames) {
    await render(
      size <= 64 ? microSvg : appSvg,
      size,
      path.join(buildDir, `app-${size}.png`),
    );
  }
  for (const size of appFrames) {
    await render(trayColorSvg, size, path.join(buildDir, `tray-${size}.png`));
  }
  const captionFrames = [16, 20, 24, 32, 40, 48];
  for (const size of captionFrames) {
    await render(microSvg, size, path.join(buildDir, `caption-${size}.png`));
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
    ["Caption / system tray", microSvg],
    ["Small 24–32 px", smallSvg],
    ["Round launcher", roundSvg],
    ["Android foreground", foregroundSvg],
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
