import { expect, test, type Page } from "@playwright/test";
import AxeBuilder from "@axe-core/playwright";

const endpoint = "https://api.github.com/repos/youssefezzat304/keep/releases?per_page=10";
const releases = "https://github.com/youssefezzat304/keep/releases";

async function noRelease(page: Page) {
  await page.route(endpoint, route => route.fulfill({ status: 200, contentType: "application/json", body: "[]" }));
}

test("page stays light, loads its screenshots, and has no accessibility violations", async ({ page }) => {
  const errors: string[] = [];
  page.on("pageerror", error => errors.push(error.message));
  await noRelease(page);
  await page.goto("/");
  await expect(page.getByRole("heading", { level: 1 })).toHaveText("Make roomfor focus.");
  const heroImage = page.locator(".hero .capture img");
  await expect.poll(() => heroImage.evaluate((image: HTMLImageElement) => image.currentSrc)).toContain("focus-light");
  await expect(page.locator("html")).toHaveCSS("color-scheme", "light");
  await expect(page.locator("body")).toHaveCSS("background-color", "rgb(250, 248, 244)");
  await expect(heroImage).toBeVisible();
  await expect.poll(() => heroImage.evaluate((image: HTMLImageElement) => image.complete && image.naturalWidth > 0)).toBe(true);
  await expect(page.locator("#download-status")).toContainText("Public downloads are coming soon");
  // Visit every reveal before auditing so visible content is included.
  for (const section of ["#workspace", "#focus", "#timesheet", "#calendar", "#habits", "#stats", "#goals", "#exports", "#music", "#zen", "#mac", "#download"]) {
    await page.locator(section).scrollIntoViewIfNeeded();
  }
  for (const reveal of await page.locator(".reveal").all()) {
    await reveal.scrollIntoViewIfNeeded();
    await expect(reveal).toHaveCSS("opacity", "1");
  }
  await expect(page.locator("html")).toHaveJSProperty("scrollWidth", page.viewportSize()!.width);
  const audit = await new AxeBuilder({ page }).withTags(["wcag2a", "wcag2aa", "wcag21aa"]).analyze();
  expect(audit.violations).toEqual([]);
  expect(errors).toEqual([]);
});

test("Get Keep takes users to the release section", async ({ page }) => {
  await noRelease(page);
  await page.goto("/");
  await page.getByRole("link", { name: "Get Keep", exact: true }).first().click();
  await expect(page).toHaveURL(/#download$/);
  await expect(page.getByRole("link", { name: "View releases", exact: true })).toBeInViewport();
  await expect(page.getByRole("link", { name: "View releases", exact: true })).toHaveAttribute("href", releases);
});

test("scrolling advances the sticky feature preview", async ({ page }, info) => {
  test.skip(info.project.name.includes("mobile"), "Mobile uses inline screenshots");
  await noRelease(page);
  await page.goto("/");
  await expect(page.locator(".tour")).toHaveAttribute("data-enhanced", "true");
  for (const chapter of ["focus", "timesheet", "calendar", "habits", "stats"]) {
    await page.locator(`#${chapter}`).scrollIntoViewIfNeeded();
    await expect(page.locator(".tour-screens")).toHaveAttribute("data-active", chapter);
  }
  await page.locator('.tour-tabs a[href="#habits"]').click();
  await expect(page.locator(".tour-screens")).toHaveAttribute("data-active", "habits");
});

test("a published DMG becomes the download destination", async ({ page }) => {
  const dmg = `${releases}/download/v1.0.0/Keep.dmg`;
  await page.route(endpoint, route => route.fulfill({ json: [
    { draft: false, prerelease: true, assets: [{ browser_download_url: `${releases}/download/v2.0.0-beta/Keep.dmg` }] },
    { draft: true, prerelease: false, assets: [{ browser_download_url: `${releases}/download/draft/Keep.dmg` }] },
    { draft: false, prerelease: false, assets: [{ browser_download_url: dmg }] },
  ] }));
  await page.goto("/");
  await expect(page.getByRole("link", { name: "Download for Mac", exact: true })).toHaveAttribute("href", dmg);
  await expect(page.locator("#download-status")).toHaveText("macOS 15 and newer");
});

test("an untrusted asset never becomes a download link", async ({ page }) => {
  await page.route(endpoint, route => route.fulfill({ json: [{ draft: false, prerelease: false, assets: [{ browser_download_url: "https://github.com.evil.example/Keep.dmg" }, { browser_download_url: "javascript:alert(1)" }] }] }));
  await page.goto("/");
  await expect(page.getByRole("link", { name: "View releases", exact: true })).toHaveAttribute("href", releases);
  await expect(page.locator("#download-status")).toContainText("Public downloads are coming soon");
});

test("network failure leaves a working release link", async ({ page }) => {
  await page.route(endpoint, route => route.abort());
  await page.goto("/");
  await expect(page.locator("#download-status")).toContainText("Check GitHub");
  await expect(page.getByRole("link", { name: "View releases", exact: true })).toHaveAttribute("href", releases);
});

test("reduced motion shows every feature inline", async ({ page }) => {
  await page.emulateMedia({ reducedMotion: "reduce" });
  await noRelease(page);
  await page.goto("/");
  await expect(page.locator(".tour")).toHaveAttribute("data-enhanced", "false");
  await expect(page.locator(".tour-stage")).toBeHidden();
  for (const capture of await page.locator(".tour-inline").all()) await expect(capture).toBeVisible();
  await expect(page.locator(".hero .preview-motion")).toHaveCSS("transform", "none");
});

test("keyboard users can skip the navigation", async ({ page, browserName }) => {
  await noRelease(page);
  await page.goto("/");
  // WebKit on macOS uses Option+Tab to include links with default keyboard settings.
  await page.keyboard.press(browserName === "webkit" ? "Alt+Tab" : "Tab");
  await expect(page.getByRole("link", { name: "Skip to content" })).toBeFocused();
  await page.keyboard.press("Enter");
  await expect(page).toHaveURL(/#main$/);
});

test("content and release link work without JavaScript", async ({ browser }, info) => {
  const context = await browser.newContext({ javaScriptEnabled: false, viewport: info.project.use.viewport, colorScheme: info.project.use.colorScheme });
  const page = await context.newPage();
  await page.goto("http://127.0.0.1:3000");
  await expect(page.getByRole("heading", { level: 1 })).toBeVisible();
  for (const capture of await page.locator(".tour-inline").all()) await expect(capture).toBeVisible();
  await expect(page.getByRole("link", { name: "View releases", exact: true })).toHaveAttribute("href", releases);
  await context.close();
});

test("the narrow layout stays within the viewport", async ({ page }) => {
  await page.setViewportSize({ width: 320, height: 740 });
  await noRelease(page);
  await page.goto("/");
  await expect(page.locator("html")).toHaveJSProperty("scrollWidth", 320);
  await expect(page.locator(".hero .button")).toBeInViewport();
});
