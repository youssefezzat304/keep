#!/bin/bash
# SPDX-License-Identifier: MIT
set -euo pipefail

repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
configuration=Debug
signing=ad-hoc
derived_data="$repo/build/DerivedData"
launch=0
checks=()
settings_file=""

usage() {
    cat <<'EOF'
Usage: Tools/build.sh [options]

Build Keep through its existing Xcode project. Defaults to an ad-hoc-signed Debug
build; no Apple certificate is needed. Release builds include all project
architectures. Version numbers and entitlements come from Xcode.

  --configuration Debug|Release   Build configuration (default: Debug)
  --ad-hoc                        Sign without an Apple certificate (default)
  --unsigned                      Compilation check only; cannot use --run
  --derived-data PATH             Xcode cache/products (default: build/DerivedData)
  --check NAME                    Run an isolated existing check; repeatable,
                                  Debug only, e.g. --check UpdaterChecks
  --run                           Launch the built Debug app; uses your usual
                                  Keep data, not an isolated developer identity
  -h, --help                      Show this help

Examples:
  Tools/build.sh --check UpdaterChecks
  Tools/build.sh --configuration Release --ad-hoc
  Tools/build.sh --unsigned --derived-data /tmp/keep-derived-data

Does not install, publish, create certificates, or change project settings.
EOF
}
fail() { printf 'Error: %s\n' "$*" >&2; exit 1; }
value() { [[ $# -ge 2 && -n "$2" && "$2" != --* ]] || fail "$1 requires a value."; }
cleanup() { [[ -z "$settings_file" ]] || rm -f "$settings_file"; }
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM HUP

while [[ $# -gt 0 ]]; do
    case "$1" in
        --configuration) value "$@"; configuration=$2; shift 2 ;;
        --derived-data) value "$@"; derived_data=$2; shift 2 ;;
        --check) value "$@"; checks+=("$2"); shift 2 ;;
        --ad-hoc) signing=ad-hoc; shift ;;
        --unsigned) signing=unsigned; shift ;;
        --run) launch=1; shift ;;
        -h|--help) usage; exit 0 ;;
        *) fail "Unknown option: $1. Use --help." ;;
    esac
done
[[ "$configuration" == Debug || "$configuration" == Release ]] || fail 'Configuration must be Debug or Release.'
if [[ "$configuration" != Debug && ( "$launch" == 1 || ${#checks[@]} -gt 0 ) ]]; then
    fail '--run and --check require Debug (Release enables live update checks).'
fi
[[ "$launch" != 1 || "$signing" != unsigned ]] || fail '--run requires a signed build; omit --unsigned.'
[[ $(uname -s) == Darwin ]] || fail 'Keep requires macOS and full Xcode.'
command -v python3 >/dev/null || fail 'python3 is required for build metadata and checks.'
xcodebuild -version >/dev/null || fail 'Select a full Xcode installation before building.'
if [[ ${#checks[@]} -gt 0 ]]; then
    for check in "${checks[@]}"; do
        [[ "$check" =~ ^[A-Za-z_][A-Za-z0-9_]*$ && -f "$repo/Tests/$check.swift" ]] || fail "Unknown check: $check."
    done
fi
derived_data=$(python3 -c 'from pathlib import Path; import sys; print(Path(sys.argv[1]).expanduser().resolve())' "$derived_data")
cd "$repo"
args=(-project "$repo/keep.xcodeproj" -scheme keep -configuration "$configuration"
      -destination 'platform=macOS' -derivedDataPath "$derived_data")
if [[ "$configuration" == Release ]]; then
    args+=(ONLY_ACTIVE_ARCH=NO CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO)
fi
if [[ "$signing" == ad-hoc ]]; then
    args+=(CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM=
           CODE_SIGNING_ALLOWED=YES CODE_SIGNING_REQUIRED=YES)
else
    args+=(CODE_SIGNING_ALLOWED=NO)
fi
printf 'Building Keep %s (%s)…\n' "$configuration" "$signing"
xcodebuild "${args[@]}" build
settings_file=$(mktemp "${TMPDIR:-/tmp}/keep-build-settings.XXXXXX")
xcodebuild "${args[@]}" -showBuildSettings -json > "$settings_file"
app=$(python3 - "$settings_file" <<'PY'
import json, sys
from pathlib import Path
targets = json.loads(Path(sys.argv[1]).read_text())
settings = next(t['buildSettings'] for t in targets if t['target'] == 'keep')
print(Path(settings['TARGET_BUILD_DIR']) / settings['FULL_PRODUCT_NAME'])
PY
)
[[ -d "$app" ]] || fail "Xcode did not produce the expected app: $app"
if [[ "$signing" == ad-hoc ]]; then
    codesign --verify --deep --strict "$app"
fi
if [[ ${#checks[@]} -gt 0 ]]; then
    python3 "$repo/Tools/run-app-checks.py" --derived-data "$derived_data" "${checks[@]}"
fi
python3 - "$app" "$configuration" "$signing" <<'PY'
import hashlib, json, os, plistlib, subprocess, sys, tempfile
from pathlib import Path
app = Path(sys.argv[1])
info_path = app / 'Contents/Info.plist'
info = plistlib.loads(info_path.read_bytes())
executable = app / 'Contents/MacOS' / info['CFBundleExecutable']
digest = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()
metadata = {
    'configuration': sys.argv[2], 'signing': sys.argv[3],
    'bundleIdentifier': info['CFBundleIdentifier'],
    'version': info['CFBundleShortVersionString'], 'build': info['CFBundleVersion'],
    'minimumMacOS': info['LSMinimumSystemVersion'],
    'architectures': subprocess.check_output(['lipo', '-archs', str(executable)], text=True).split(),
    'executableSHA256': digest(executable), 'infoPlistSHA256': digest(info_path),
}
target = app.parent / 'keep-build.json'
with tempfile.NamedTemporaryFile(mode='w', dir=app.parent, delete=False) as f:
    temporary = Path(f.name)
    json.dump(metadata, f, indent=2)
    f.write('\n')
try:
    os.replace(temporary, target)
finally:
    temporary.unlink(missing_ok=True)
print(f"Built Keep {metadata['version']} ({metadata['build']}); "
      f"macOS {metadata['minimumMacOS']}+; {', '.join(metadata['architectures'])}")
print(f'App: {app}\nBuild receipt: {target}')
PY
if [[ "$launch" == 1 ]]; then
    open "$app"
fi
