import { defineConfig } from "@playwright/test";

export default defineConfig({
  testDir: "./tests",
  fullyParallel: true,
  forbidOnly: Boolean(process.env.CI),
  retries: 0,
  workers: 4,
  reporter: "list",
  use: { baseURL: "http://127.0.0.1:3000", browserName: "chromium", trace: "retain-on-failure" },
  projects: [
    { name: "desktop-light", use: { viewport: { width: 1440, height: 1000 }, colorScheme: "light" } },
    { name: "desktop-dark", use: { viewport: { width: 1440, height: 1000 }, colorScheme: "dark" } },
    { name: "mobile-light", use: { viewport: { width: 390, height: 844 }, colorScheme: "light", isMobile: true, hasTouch: true } },
    { name: "mobile-dark", use: { viewport: { width: 390, height: 844 }, colorScheme: "dark", isMobile: true, hasTouch: true } },
    { name: "safari-desktop-light", use: { browserName: "webkit", viewport: { width: 1440, height: 1000 }, colorScheme: "light" } },
    { name: "safari-desktop-dark", use: { browserName: "webkit", viewport: { width: 1440, height: 1000 }, colorScheme: "dark" } },
    { name: "safari-mobile-light", use: { browserName: "webkit", viewport: { width: 390, height: 844 }, colorScheme: "light", isMobile: true, hasTouch: true } },
    { name: "safari-mobile-dark", use: { browserName: "webkit", viewport: { width: 390, height: 844 }, colorScheme: "dark", isMobile: true, hasTouch: true } },
  ],
  webServer: { command: "npm start", url: "http://127.0.0.1:3000", reuseExistingServer: !process.env.CI },
});
