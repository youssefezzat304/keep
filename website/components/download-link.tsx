"use client";

import { useEffect, useState } from "react";
import { ArrowDown, ArrowUpRight } from "@phosphor-icons/react";

const repository = "youssefezzat304/keep";
const releases = `https://github.com/${repository}/releases`;
type Release = { phase: "checking" | "available" | "unpublished" | "unavailable"; url: string };

function downloadURL(value: unknown): string | null {
  if (typeof value !== "string") return null;
  try {
    const url = new URL(value);
    return url.protocol === "https:" && url.hostname === "github.com"
      && url.pathname.startsWith(`/${repository}/releases/download/`)
      && url.pathname.toLowerCase().endsWith(".dmg") ? url.href : null;
  } catch { return null; }
}

export function DownloadLink() {
  const [release, setRelease] = useState<Release>({ phase: "checking", url: releases });
  useEffect(() => {
    const controller = new AbortController();
    let disposed = false;
    const timeout = setTimeout(() => controller.abort(), 8000);
    const findRelease = async () => {
      try {
        const response = await fetch(`https://api.github.com/repos/${repository}/releases?per_page=10`, {
          signal: controller.signal, headers: { Accept: "application/vnd.github+json" },
        });
        if (disposed) return;
        if (response.status === 404) { setRelease({ phase: "unpublished", url: releases }); return; }
        if (!response.ok) throw new Error("Release lookup unavailable");
        const data: unknown = await response.json();
        const latest: unknown = Array.isArray(data) ? data.find((item: unknown) => typeof item === "object" && item !== null && "draft" in item && item.draft === false && "prerelease" in item && item.prerelease === false) : undefined;
        const assets = typeof latest === "object" && latest !== null && "assets" in latest && Array.isArray(latest.assets) ? latest.assets : [];
        const url = assets.map((asset: unknown) => typeof asset === "object" && asset !== null && "browser_download_url" in asset ? downloadURL(asset.browser_download_url) : null).find(Boolean);
        if (!disposed) setRelease(url ? { phase: "available", url } : { phase: "unpublished", url: releases });
      } catch {
        if (!disposed) setRelease({ phase: "unavailable", url: releases });
      } finally { clearTimeout(timeout); }
    };
    void findRelease();
    return () => { disposed = true; controller.abort(); clearTimeout(timeout); };
  }, []);
  const available = release.phase === "available";
  const status = available ? "macOS 15 and newer" : release.phase === "unpublished"
    ? "Public downloads are coming soon. macOS 15 and newer."
    : release.phase === "unavailable" ? "Check GitHub for the latest download. macOS 15 and newer."
      : "Find the latest download on GitHub. macOS 15 and newer.";
  return <div className="download-action">
    <a href={release.url} className="button button-primary" aria-describedby="download-status">
      {available ? <ArrowDown size={19} aria-hidden="true" /> : <ArrowUpRight size={19} aria-hidden="true" />}
      {available ? "Download for Mac" : "View releases"}
    </a>
    <p id="download-status" className="download-status" role="status">{status}</p>
  </div>;
}
