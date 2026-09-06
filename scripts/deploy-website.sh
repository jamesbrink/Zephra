#!/usr/bin/env bash
# Publish only the static browser export. Keep old hashed chunks for open tabs.
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
site="$root/product-mockups/dist/client"
: "${WEBSITE_BUCKET:=zephra-site-urandom-io}"
: "${WEBSITE_DISTRIBUTION:=ETNI7JSPHMJRF}"
: "${WEBSITE_URL:=https://zephra.urandom.io}"
aws_cli=(aws)
if [[ -n ${WEBSITE_PROFILE:-} ]]; then aws_cli+=(--profile "$WEBSITE_PROFILE"); fi
[[ -s "$site/index.html" && -s "$site/404.html" && -d "$site/_next/static" ]] || {
  echo 'website: missing static export; run make website-build' >&2; exit 1;
}
# Hashed JS/CSS first, mutable images next, entry documents last. Never sync server output.
"${aws_cli[@]}" s3 cp "$site/_next/" "s3://$WEBSITE_BUCKET/_next/" --recursive \
  --cache-control 'public,max-age=31536000,immutable' --only-show-errors
"${aws_cli[@]}" s3 cp "$site/" "s3://$WEBSITE_BUCKET/" --recursive \
  --exclude '_next/*' --exclude '*.html' --exclude '.*' \
  --cache-control 'public,max-age=60,must-revalidate' --only-show-errors
"${aws_cli[@]}" s3 cp "$site/" "s3://$WEBSITE_BUCKET/" --recursive \
  --exclude '*' --include '*.html' --content-type 'text/html; charset=utf-8' \
  --cache-control 'public,max-age=0,must-revalidate' --only-show-errors
invalidation=$("${aws_cli[@]}" cloudfront create-invalidation \
  --distribution-id "$WEBSITE_DISTRIBUTION" --paths '/*' --query Invalidation.Id --output text)
echo "website: waiting for CloudFront invalidation $invalidation"
"${aws_cli[@]}" cloudfront wait invalidation-completed \
  --distribution-id "$WEBSITE_DISTRIBUTION" --id "$invalidation"
python3 "$root/scripts/verify-website.py" "$site" "$WEBSITE_URL"
