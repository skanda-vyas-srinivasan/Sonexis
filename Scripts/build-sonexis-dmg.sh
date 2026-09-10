#!/bin/zsh
set -euo pipefail

script_dir=${0:A:h}

if (( $# < 1 || $# > 2 )); then
  echo "Usage: $0 NOTARIZED_APP [OUTPUT_DIRECTORY]" >&2
  echo "Example: $0 ~/Downloads/Sonexis.app ~/Downloads" >&2
  exit 64
fi

app_path=${1:A}
output_dir=${2:-$HOME/Downloads}
output_dir=${output_dir:A}

[[ -d "$app_path" ]] || { echo "App not found: $app_path" >&2; exit 66; }

info_plist="$app_path/Contents/Info.plist"
[[ -f "$info_plist" ]] || { echo "Not a macOS app bundle: $app_path" >&2; exit 65; }

version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$info_plist")
build=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$info_plist")
output_path="$output_dir/Sonexis-$version-Installer.dmg"

if [[ -e "$output_path" ]]; then
  echo "Output already exists: $output_path" >&2
  echo "Move or rename it, then run this command again." >&2
  exit 73
fi

identity=$(security find-identity -v -p codesigning \
  | sed -n 's/.*"\(Developer ID Application:[^"]*\)".*/\1/p' \
  | head -1)
[[ -n "$identity" ]] || {
  echo "No Developer ID Application signing identity was found in Keychain." >&2
  exit 69
}

work_dir=$(mktemp -d /private/tmp/sonexis-release.XXXXXX)
background_path="$work_dir/SonexisDMGBackground.png"
trap 'rm -rf "$work_dir"' EXIT

echo "Checking Sonexis $version (build $build)…"
codesign --verify --deep --strict --verbose=2 "$app_path"
xcrun stapler validate "$app_path"

echo "Rendering the Retina Sonexis installer background…"
swift "$script_dir/render-dmg-background.swift" "$background_path"
sips --setProperty dpiWidth 144 --setProperty dpiHeight 144 \
  "$background_path" >/dev/null

mkdir -p "$output_dir"
echo "Building and signing $(basename "$output_path")…"
"$script_dir/make-sonexis-dmg.sh" \
  "$app_path" "$background_path" "$output_path" "$identity" \
  "Sonexis $version ($build) Installer"

# Sign once more after Finder has fully released its layout metadata.
codesign --force --timestamp --sign "$identity" "$output_path"
codesign --verify --verbose=2 "$output_path"
hdiutil verify "$output_path" >/dev/null

echo
echo "Ready: $output_path"
echo "Version: $version ($build)"
echo "SHA-256: $(shasum -a 256 "$output_path" | awk '{print $1}')"
