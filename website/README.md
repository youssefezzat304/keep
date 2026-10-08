# Keep website

A one-page Next.js site for the native Mac app, designed using [Taste](https://github.com/Leonxlnx/taste-skill/tree/main/skills/taste-skill). The design follows Keep’s cream, terracotta and rounded typography, with a sticky scroll tour on desktop and inline screenshots on mobile. It uses light styling and light app screenshots regardless of system appearance, and respects Reduce Motion. The tour includes Dashboard Timesheet and Calendar, with dedicated goals, export and music-player sections. Zen explains choosing personal image or MP4 wallpapers. Every Keep feature is free.

## Run locally

Use Node.js 22.12 or newer. From the repository root:

```sh
cd website
npm ci
npm run dev
```

Open <http://127.0.0.1:3000>. For a production preview:

```sh
npm run build
npm start
```

`npm start` serves the static `out/` directory locally. Set `PORT=3001` if port 3000 is occupied. It is a preview tool, not a production server.

## Screenshots

The images are captured from actual Keep SwiftUI views, hosted in an isolated native app with example projects, habits and activity. Playback is silent; the fixture does not read or write your live archives, request Music access, or contact audio providers.

To refresh them, first build the native app using the workflow in `docs/architecture.md`, then run from the repository root:

```sh
python3 Tools/run-app-checks.py WebsitePresentationChecks
cd website
npm run screenshots
```

The native harness writes eight light PNG captures to `/tmp/keep-website-captures`. The preparation script creates responsive WebP sizes in `public/screenshots/` and copies/converts the existing app icon. Set `KEEP_SCREENSHOT_DIR` to read the captures from another directory. Screenshots need refreshing when the app interface materially changes; they are not live embeds. Outfit is self-hosted, with its license in `public/brand/outfit-license.txt`.

## Downloads

The final button looks up the newest stable release among the ten most recent public GitHub releases. Only HTTPS `.dmg` assets hosted under this repository’s GitHub release download path are accepted. Prereleases and drafts are skipped. With no DMG, no JavaScript, a timeout or an API failure, a regular GitHub Releases link stays available. No GitHub token is required or bundled.

There is currently no published release. Publishing a DMG is separate work; building this website does not create or publish one.

## Verify

```sh
npx playwright install chromium webkit
npm run typecheck
npm run lint
npm run build
npm run test:e2e
```

Browser checks confirm light-only styling under both light and dark system preferences on desktop/mobile in Chromium and WebKit. They also cover scroll progression, release states, keyboard navigation, reduced motion, disabled JavaScript, 320-pixel overflow, and axe accessibility checks. Tests mock GitHub responses and never download a DMG.

## Hosting later

Set `KEEP_SITE_URL` to the chosen public origin before `npm run build` so social preview URLs use the deployed hostname. Without it, preview metadata uses localhost. Deploy `out/` to a static host with compression, cache immutable `/_next/static/` files, and serve HTML without long-lived caching. No Node.js server, database, account or secret is needed at runtime.

The current asset paths assume hosting at the domain root. A GitHub Pages project URL under `/keep/` needs a coordinated Next `basePath` and public-asset prefix change before deployment. No host, custom domain or deployment workflow has been configured.
