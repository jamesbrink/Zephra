#!/usr/bin/env bash
# Upload an already notarized installer to an immutable, versioned public URL.
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
dmg="$root/build/Zephra.dmg"
metadata=$(mktemp "${TMPDIR:-/tmp}/zephra-release-metadata.XXXXXX")
trap 'rm -f "$metadata"' EXIT
aws_cli=(aws)
if [[ -n ${RELEASE_PROFILE:-} ]]; then aws_cli+=(--profile "$RELEASE_PROFILE"); fi
codesign --verify --strict "$dmg"
xcrun stapler validate "$dmg"
"$root/scripts/verify-dmg.sh" "$dmg" "$metadata"
version=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["version"])' "$metadata")
build=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["build"])' "$metadata")
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
  remote_sha=$("${aws_cli[@]}" s3api head-object --bucket "$bucket" --key "$key" \
    --query Metadata.sha256 --output text)
  [[ "$remote_sha" == "$sha" ]] || {
    echo "release: $key already exists with different bytes; use a new build number" >&2; exit 1;
  }
  echo 'release: identical installer already published; verifying it again'
else
  # Conditional write makes the immutable key safe even against concurrent publishers.
  "${aws_cli[@]}" s3api put-object --bucket "$bucket" --key "$key" --body "$dmg" \
    --if-none-match '*' --checksum-algorithm SHA256 \
    --content-type application/x-apple-diskimage \
    --content-disposition "attachment; filename=\"$name\"" \
    --cache-control 'public,max-age=31536000,immutable' --metadata "sha256=$sha" >/dev/null
fi
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

# A stable name beside the immutable one, so a link that is not regenerated on every ship —
# a README, a blog post, someone's bookmark — still reaches the newest build. Only ever a
# copy: S3 has no aliases or symlinks, and this is a bucket-internal copy, so the bytes are
# not uploaded twice.
#
# Its caching is the opposite of the stamped key's, and that is the whole trick. The stamped
# name is `immutable,max-age=31536000` because those bytes never change; the same header on a
# name that DOES change would leave CloudFront and every browser serving last month's build
# under it for a year. So this one is a minute, revalidated, and the distribution is told to
# forget it immediately.
latest_name="Zephra-latest.dmg"
latest_key="releases/$latest_name"
latest_url="https://zephra-assets.urandom.io/$latest_key"
# The download still lands in the user's Downloads folder under the build it actually is,
# rather than as "Zephra-latest.dmg", so two of them are told apart on disk.
"${aws_cli[@]}" s3api copy-object --bucket "$bucket" --key "$latest_key" \
  --copy-source "$bucket/$key" --metadata-directive REPLACE \
  --content-type application/x-apple-diskimage \
  --content-disposition "attachment; filename=\"$name\"" \
  --cache-control 'public,max-age=60,must-revalidate' --metadata "sha256=$sha" >/dev/null

# What the stable name currently points at, and its checksum. Without this the published
# SHA-256 no longer identifies the bytes behind the link, which is the real cost of a mutable
# name; anyone verifying a download from it can read the build and digest here.
latest_manifest=$(mktemp "${TMPDIR:-/tmp}/zephra-latest.XXXXXX")
trap 'rm -f "$metadata" "$latest_manifest"' EXIT
python3 - "$latest_manifest" "$url" "$version" "$build" "$sha" <<'PY'
import json, sys
from pathlib import Path
path, url, version, build, sha = sys.argv[1:]
Path(path).write_text(json.dumps(dict(url=url, version=version, build=build, sha256=sha), indent=2)+'\n')
PY
"${aws_cli[@]}" s3api put-object --bucket "$bucket" --key releases/latest.json \
  --body "$latest_manifest" --content-type application/json \
  --cache-control 'public,max-age=60,must-revalidate' >/dev/null

# CloudFront caches by path, so a mutated key keeps serving the old bytes until it is told
# otherwise. Skipped rather than fatal when no distribution is configured: the release itself
# is already published and verified above, and a stale alias is worth a warning, not a failure.
if [[ -n ${RELEASE_DISTRIBUTION:-} ]]; then
  "${aws_cli[@]}" cloudfront create-invalidation --distribution-id "$RELEASE_DISTRIBUTION" \
    --paths "/$latest_key" /releases/latest.json >/dev/null
  echo "release: invalidated $latest_key on $RELEASE_DISTRIBUTION"
else
  echo "release: RELEASE_DISTRIBUTION unset, $latest_key may serve stale bytes until its TTL" >&2
fi

# The alias is verified the same way the stamped URL was, because a copy that silently landed
# on the wrong bytes is exactly what a stable name would hide.
latest_download="$root/build/download-verification/$latest_name"
curl --fail --location --retry 3 "$latest_url" -o "$latest_download"
[[ $(shasum -a 256 "$latest_download" | awk '{print $1}') == "$sha" ]] || {
  echo "release: $latest_name does not match the build just published" >&2; exit 1;
}
codesign --verify --strict "$latest_download"
xcrun stapler validate "$latest_download"
echo "release: verified stable download $latest_url"
