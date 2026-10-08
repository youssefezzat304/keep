#!/bin/bash
# SPDX-License-Identifier: MIT
set -euo pipefail

repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
derived_data="$repo/build/DerivedData"
app=""
tag=""
output=""
notes=""
account=com.youssef.keep
appcast=1
work=""
owned_output=0
complete=0

usage() {
    cat <<'EOF'
Usage: Tools/package-release.sh --tag vVERSION [options]

Package a signed Release build made by Tools/build.sh. Creates an APFS/LZFSE DMG,
a signed Sparkle appcast, and SHA256SUMS. Nothing is uploaded or published.

  --tag TAG              Required GitHub release tag; must equal v + app version
  --derived-data PATH    Build cache and Sparkle tools (default: build/DerivedData)
  --app PATH             App to package (default: DerivedData Release/keep.app)
                         Requires the matching adjacent keep-build.json receipt
  --output PATH          New output folder (default: dist/TAG-build-BUILD)
                         Existing folders/files are never overwritten
  --notes PATH           Optional UTF-8 .md, .txt, or .html release notes to embed
  --account NAME         Existing Sparkle Keychain account (default: com.youssef.keep)
  --skip-appcast         Create only the DMG and checksums; no Keychain access
  -h, --help             Show this help

Examples:
  Tools/build.sh --configuration Release --ad-hoc
  Tools/package-release.sh --tag v1.0.0
  Tools/package-release.sh --tag v1.0.0 --notes /path/to/release-notes.md

Ad-hoc builds are not notarized. This script does not create/export keys, sign
with Developer ID, notarize, change version numbers, or contact GitHub. The feed
contains this release only; preserve older compatible feed entries separately
before raising macOS/architecture requirements in a future release.
EOF
}
fail() { printf 'Error: %s\n' "$*" >&2; exit 1; }
value() { [[ $# -ge 2 && -n "$2" && "$2" != --* ]] || fail "$1 requires a value."; }
cleanup() {
    [[ -z "$work" ]] || rm -rf "$work"
    if [[ "$owned_output" == 1 && "$complete" != 1 ]]; then
        rm -rf "$output"
    fi
    return 0
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM HUP

while [[ $# -gt 0 ]]; do
    case "$1" in
        --tag) value "$@"; tag=$2; shift 2 ;;
        --derived-data) value "$@"; derived_data=$2; shift 2 ;;
        --app) value "$@"; app=$2; shift 2 ;;
        --output) value "$@"; output=$2; shift 2 ;;
        --notes) value "$@"; notes=$2; shift 2 ;;
        --account) value "$@"; account=$2; shift 2 ;;
        --skip-appcast) appcast=0; shift ;;
        -h|--help) usage; exit 0 ;;
        *) fail "Unknown option: $1. Use --help." ;;
    esac
done
[[ -n "$tag" ]] || fail '--tag is required. Use --help.'
[[ "$tag" =~ ^v[0-9]+(\.[0-9]+){0,2}$ ]] || fail 'Tag must be v followed by the numeric app version, e.g. v1.0.0.'
[[ $(uname -s) == Darwin ]] || fail 'Packaging requires macOS.'
command -v python3 >/dev/null || fail 'python3 is required to validate release metadata.'
derived_data=$(python3 -c 'from pathlib import Path; import sys; print(Path(sys.argv[1]).expanduser().resolve())' "$derived_data")
[[ -n "$app" ]] || app="$derived_data/Build/Products/Release/keep.app"
app=$(python3 -c 'from pathlib import Path; import sys; print(Path(sys.argv[1]).expanduser().resolve())' "$app")
work=$(mktemp -d "${TMPDIR:-/tmp}/keep-release.XXXXXX")
# Validate the receipt before reading paths/versions from the bundle. The same
# checks run on the staged copy to catch changes made during copying.
cat > "$work/validate.py" <<'PY'
import base64, hashlib, json, plistlib, re, sys
from pathlib import Path
from urllib.parse import urlsplit
app, receipt, tag, destination = map(Path, sys.argv[1:5])
tag = str(tag)
def require(condition, message):
    if not condition:
        raise ValueError(message)
try:
    metadata = json.loads(receipt.read_text())
    require(metadata.get('configuration') == 'Release', 'Only Release builds can be packaged.')
    require(metadata.get('signing') == 'ad-hoc', 'Build with Tools/build.sh --configuration Release --ad-hoc.')
    info_path = app / 'Contents/Info.plist'
    info = plistlib.loads(info_path.read_bytes())
    require(info.get('CFBundleIdentifier') == 'com.youssef.keep', 'Unexpected bundle identifier.')
    require(app.name == 'keep.app' and info.get('CFBundleExecutable') == 'keep', 'Unexpected app/executable name.')
    digest = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()
    require(digest(info_path) == metadata['infoPlistSHA256'], 'Info.plist changed after the build; rebuild first.')
    require(digest(app / 'Contents/MacOS/keep') == metadata['executableSHA256'], 'Executable changed after the build; rebuild first.')
    version, build = info['CFBundleShortVersionString'], info['CFBundleVersion']
    require(isinstance(version, str) and re.fullmatch(r'[0-9]+(?:\.[0-9]+){0,2}', version), 'Invalid marketing version.')
    require(isinstance(build, str) and re.fullmatch(r'[0-9]+', build) and int(build) > 0, 'Use a positive integer build number.')
    require(tag == 'v' + version, f'Tag must match the built app version: v{version}.')
    require(version == metadata['version'] and build == metadata['build'], 'Build receipt does not match app version.')
    feed = urlsplit(info['SUFeedURL'])
    parts = feed.path.strip('/').split('/')
    require(feed.scheme == 'https' and feed.netloc == 'github.com' and not feed.query and not feed.fragment
            and len(parts) == 6 and parts[2:] == ['releases', 'latest', 'download', 'appcast.xml']
            and all(re.fullmatch(r'[A-Za-z0-9_.-]+', p) for p in parts[:2]), 'Unexpected GitHub appcast feed URL.')
    key = info['SUPublicEDKey']
    require(len(base64.b64decode(key, validate=True)) == 32 and '\n' not in key, 'Invalid Sparkle public key.')
    require(info.get('SURequireSignedFeed') is True, 'Keep must require signed appcasts.')
    require((app / 'Contents/Frameworks/Sparkle.framework').is_dir(), 'Embedded Sparkle framework is missing.')
    prefix = f'https://github.com/{parts[0]}/{parts[1]}/releases/download/{tag}/'
    destination.write_text('\n'.join([version, build, key, prefix]) + '\n')
except (OSError, ValueError, KeyError, TypeError) as error:
    sys.exit(f'Error: Invalid release build: {error}')
PY
receipt="$(dirname "$app")/keep-build.json"
python3 "$work/validate.py" "$app" "$receipt" "$tag" "$work/metadata"
{
    IFS= read -r version
    IFS= read -r build
    IFS= read -r public_key
    IFS= read -r download_prefix
} < "$work/metadata"
verify_bundle() {
    codesign --verify --deep --strict "$1"
    codesign --display --entitlements - --xml "$1" > "$work/entitlements.plist"
    python3 - "$work/entitlements.plist" <<'PY'
import plistlib, sys
from pathlib import Path
entitlements = plistlib.loads(Path(sys.argv[1]).read_bytes())
if entitlements.get('com.apple.security.get-task-allow') is True:
    sys.exit('Error: Release app has a debugging entitlement; rebuild with Tools/build.sh.')
if entitlements.get('com.apple.security.app-sandbox') is not True:
    sys.exit('Error: Keep must retain App Sandbox in Release builds.')
PY
}
verify_bundle "$app"
[[ -s "$repo/LICENSE.md" ]] || fail 'The repository LICENSE.md is missing or empty.'
[[ -n "$output" ]] || output="$repo/dist/$tag-build-$build"
output=$(python3 -c 'from pathlib import Path; import sys; print(Path(sys.argv[1]).expanduser().absolute())' "$output")
[[ ! -e "$output" && ! -L "$output" ]] || fail "Output already exists; choose a new folder: $output"
if [[ -n "$notes" ]]; then
    [[ -f "$notes" ]] || fail "Release notes not found: $notes"
    case "$notes" in *.md|*.txt|*.html) ;; *) fail 'Release notes must be .md, .txt, or .html.' ;; esac
    python3 -c 'from pathlib import Path; import sys; Path(sys.argv[1]).read_text(encoding="utf-8")' "$notes"
fi
if [[ "$appcast" == 1 ]]; then
    sparkle_tools="$derived_data/SourcePackages/artifacts/sparkle/Sparkle/bin"
    for tool in generate_keys generate_appcast sign_update; do
        [[ -x "$sparkle_tools/$tool" ]] || fail "Missing Sparkle tool: $sparkle_tools/$tool. Use the build’s --derived-data path."
    done
    # -p only reads the existing public key; it never creates or exports keys.
    existing_key=$("$sparkle_tools/generate_keys" --account "$account" -p) || fail "Cannot read the existing Sparkle key for account $account. See docs/updates.md."
    [[ "$existing_key" == "$public_key" ]] || fail 'Sparkle Keychain public key differs from the built app. Do not generate a replacement key.'
fi
mkdir -p "$(dirname "$output")"
mkdir "$output" || fail "Cannot reserve output folder: $output"
owned_output=1
mkdir "$work/image"
ditto "$app" "$work/image/keep.app"
ln -s /Applications "$work/image/Applications"
cp "$repo/LICENSE.md" "$work/image/LICENSE.md"
python3 "$work/validate.py" "$work/image/keep.app" "$receipt" "$tag" "$work/staged-metadata"
verify_bundle "$work/image/keep.app"
archive="Keep-$version-build-$build.dmg"
printf 'Packaging Keep %s (%s)…\n' "$version" "$build"
hdiutil create -quiet -fs APFS -format ULFO -volname "Keep $version" -srcfolder "$work/image" "$output/$archive"
hdiutil verify "$output/$archive"
if [[ "$appcast" == 1 ]]; then
    if [[ -n "$notes" ]]; then
        cp "$notes" "$output/${archive%.dmg}.${notes##*.}"
    fi
    "$sparkle_tools/generate_appcast" --account "$account" --maximum-deltas 0 \
        --embed-release-notes --download-url-prefix "$download_prefix" "$output"
    [[ -f "$output/appcast.xml" ]] || fail 'Sparkle did not create appcast.xml.'
    "$sparkle_tools/sign_update" --account "$account" --verify "$output/appcast.xml"
    signature=$(python3 - "$output/appcast.xml" "$output/$archive" "$version" "$build" "$download_prefix" <<'PY'
import sys, xml.etree.ElementTree as ET
from pathlib import Path
feed, archive, version, build, prefix = sys.argv[1:]
sparkle = '{http://www.andymatuschak.org/xml-namespaces/sparkle}'
items = ET.parse(feed).findall('./channel/item')
if len(items) != 1:
    sys.exit('Error: Expected exactly one release in the new appcast.')
item = items[0]
enclosure = item.find('enclosure')
if enclosure is None:
    sys.exit('Error: Appcast enclosure is missing.')
checks = [item.findtext(sparkle+'version') == build,
          item.findtext(sparkle+'shortVersionString') == version,
          enclosure.get('url') == prefix + Path(archive).name,
          enclosure.get('length') == str(Path(archive).stat().st_size),
          bool(enclosure.get(sparkle+'edSignature')),
          item.find(sparkle+'releaseNotesLink') is None]
if not all(checks):
    sys.exit('Error: Appcast version, URL, length, signature, or embedded notes do not match the release.')
print(enclosure.get(sparkle+'edSignature'))
PY
)
    "$sparkle_tools/sign_update" --account "$account" --verify "$output/$archive" "$signature"
    [[ -z "$notes" ]] || rm -f "$output/${archive%.dmg}.${notes##*.}"
fi
(
    cd "$output"
    files=("$archive")
    [[ "$appcast" != 1 ]] || files+=(appcast.xml)
    shasum -a 256 "${files[@]}" > SHA256SUMS
    shasum -a 256 -c SHA256SUMS
)
complete=1
printf '\nRelease artifacts: %s\n' "$output"
printf 'App: Keep %s (%s), ad-hoc signed; not notarized.\n' "$version" "$build"
if [[ "$appcast" == 1 ]]; then
    printf 'Upload %s, appcast.xml, and SHA256SUMS to the GitHub release tagged %s.\n' "$archive" "$tag"
else
    printf 'Appcast skipped: this DMG alone does not prepare a Sparkle update.\n'
fi
printf 'Nothing has been published. Test the downloaded app and a real upgrade before distributing.\n'
