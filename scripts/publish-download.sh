#!/usr/bin/env bash
# Upload an already notarized installer to an immutable, versioned public URL.
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
dmg="$root/build/Zephra.dmg"
app="$root/build/Release/Zephra.app"
aws_cli=(aws)
if [[ -n ${RELEASE_PROFILE:-} ]]; then aws_cli+=(--profile "$RELEASE_PROFILE"); fi
codesign --verify --strict "$dmg"
xcrun stapler validate "$dmg"
"$root/scripts/verify-dmg.sh" "$dmg"
version=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$app/Contents/Info.plist")
build=$(/usr/libexec/PlistBuddy -c 'Print CFBundleVersion' "$app/Contents/Info.plist")
[[ "$version-$build" =~ ^[0-9.]+-[0-9.]+$ ]] || { echo 'release: invalid version'; exit 1; }
name="Zephra-$version-$build.dmg"
key="releases/$name"
bucket=zephra-assets-urandom-io
url="https://zephra-assets.urandom.io/$key"
sha=$(shasum -a 256 "$dmg" | awk '{print $1}')
# Fail on listing errors; never silently overwrite a previously published version.
existing=$("${aws_cli[@]}" s3api list-objects-v2 --bucket "$bucket" --prefix "$key" \
  --query "Contents[?Key=='$key'].Key | [0]" --output text)
if [[ "$existing" == "$key" ]]; then
  echo "release: $key already exists; use a new build number" >&2; exit 1
fi
"${aws_cli[@]}" s3 cp "$dmg" "s3://$bucket/$key" --only-show-errors \
  --content-type application/x-apple-diskimage \
  --content-disposition "attachment; filename=\"$name\"" \
  --cache-control 'public,max-age=31536000,immutable' --metadata "sha256=$sha"
download="$root/build/download-verification/$name"
mkdir -p "$(dirname "$download")"
curl --fail --location --retry 3 "$url" -o "$download"
[[ $(shasum -a 256 "$download" | awk '{print $1}') == "$sha" ]] || {
  echo 'release: downloaded checksum mismatch' >&2; exit 1;
}
codesign --verify --strict "$download"
xcrun stapler validate "$download"
"$root/scripts/verify-dmg.sh" "$download"
python3 - "$root/product-mockups/app/release.json" "$url" "$version" "$build" "$sha" <<'PY'
import json, sys
from pathlib import Path
path, url, version, build, sha = sys.argv[1:]
Path(path).write_text(json.dumps(dict(url=url, version=version, build=build, sha256=sha), indent=2)+'\n')
PY
echo "release: verified public download $url"
