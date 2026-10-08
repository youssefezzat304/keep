import sharp from "sharp";
import { mkdir } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import path from "node:path";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const input = process.env.KEEP_SCREENSHOT_DIR ?? "/tmp/keep-website-captures";
const target = path.join(root, "public/screenshots");
await mkdir(target, { recursive: true });
for (const name of ["focus-light", "timesheet-light", "calendar-light", "habits-light", "stats-light", "exports-light", "menu-light", "zen"]) {
  const widths = name.startsWith("menu") ? [380, 760] : [720, 1200, 1920];
  for (const width of widths) {
    const suffix = width === widths.at(-1) ? "" : `-${width}`;
    await sharp(path.join(input, `${name}.png`)).resize({ width, withoutEnlargement: true })
      .webp({ quality: 88, effort: 6 }).toFile(path.join(target, `${name}${suffix}.webp`));
  }
}
const icon = path.resolve(root, "../Resources/Assets.xcassets/AppIcon.appiconset/app-icon-256.png");
await sharp(icon).webp({ quality: 92 }).toFile(path.join(root, "public/brand/keep-icon.webp"));
await sharp(icon).resize(128).png().toFile(path.join(root, "app/icon.png"));
console.log("Prepared responsive WebP sizes for eight light native captures and the existing Keep icon.");
