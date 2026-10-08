#!/usr/bin/env python3
"""Run native standalone checks against an existing Debug build.

Uses an isolated temporary app identity/resources, never the installed Keep app.
Build first with Tools/build.sh or the command in docs/architecture.md.
"""
import argparse
from pathlib import Path
import platform
import plistlib
import shutil
import subprocess
import tempfile

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("checks", nargs="+", help="Check source names, e.g. UpdaterChecks")
parser.add_argument("--derived-data", type=Path, default=Path("/tmp/keep-derived-data"))
args = parser.parse_args()
repo = Path(__file__).resolve().parents[1]
build = args.derived_data / "Build"
products = build / "Products/Debug"
original = products / "keep.app/Contents"
architecture = platform.machine()
sources = sorted(str(p) for p in (repo / "Sources/Keep").rglob("*.swift") if p.name != "KeepApp.swift")
if not (original / "Info.plist").exists() or not (products / "Sparkle.framework").exists():
    parser.error("Build the Debug keep scheme with Tools/build.sh first.")
for name in args.checks:
    if not name.isidentifier() or not (repo / f"Tests/{name}.swift").is_file():
        parser.error(f"Unknown check source: {name}")
    with tempfile.TemporaryDirectory(prefix="keep-checks-") as directory:
        temporary = Path(directory)
        contents = temporary / "Checks.app/Contents"
        (contents / "MacOS").mkdir(parents=True)
        shutil.copytree(original / "Resources", contents / "Resources", symlinks=True)
        shutil.copytree(original / "Frameworks", contents / "Frameworks", symlinks=True)
        info = plistlib.loads((original / "Info.plist").read_bytes())
        info.update(CFBundleIdentifier=f"local.keep.checks.{name}", CFBundleExecutable="checks",
                    CFBundleName="Keep checks", SUEnableAutomaticChecks=False,
                    SUAutomaticallyUpdate=False)
        (contents / "Info.plist").write_bytes(plistlib.dumps(info))
        harness = temporary / "Checks.swift"
        harness.write_text((repo / f"Tests/{name}.swift").read_text())
        executable = contents / "MacOS/checks"
        subprocess.run(["xcrun", "swiftc", "-parse-as-library", "-default-isolation", "MainActor",
                        "-target", f"{architecture}-apple-macos{info['LSMinimumSystemVersion']}",
                        "-I", str(products), "-F", str(products), "-framework", "Sparkle",
                        "-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks",
                        str(harness), *sources, "-o", str(executable)], check=True)
        subprocess.run([str(executable)], check=True, timeout=120)
