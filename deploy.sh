#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
TERRAFORM_DIR="$ROOT_DIR/terraform"
SOURCE_HTML="$ROOT_DIR/index_template.html"
GENERATED_HTML="$ROOT_DIR/index.html"
PLACEHOLDER="__API_BASE_URL__"

terraform -chdir="$TERRAFORM_DIR" init
terraform -chdir="$TERRAFORM_DIR" apply

API_BASE_URL="$(terraform -chdir="$TERRAFORM_DIR" output -raw api_url)"
FRONTEND_BUCKET="$(terraform -chdir="$TERRAFORM_DIR" output -raw frontend_bucket_name)"
CLOUDFRONT_DISTRIBUTION_ID="$(terraform -chdir="$TERRAFORM_DIR" output -raw cloudfront_distribution_id)"
CLOUDFRONT_URL="$(terraform -chdir="$TERRAFORM_DIR" output -raw cloudfront_url)"

python3 -c '
from pathlib import Path
import sys

source, output, placeholder, api_url = sys.argv[1:]

html = Path(source).read_text(encoding="utf-8")

if placeholder not in html:
    raise SystemExit(f"Missing placeholder: {placeholder}")

html = html.replace(placeholder, api_url.rstrip("/"))
Path(output).write_text(html, encoding="utf-8")
' "$SOURCE_HTML" "$GENERATED_HTML" "$PLACEHOLDER" "$API_BASE_URL"

aws s3 cp "$GENERATED_HTML" "s3://$FRONTEND_BUCKET/index.html" \
  --content-type "text/html" \
  --cache-control "no-cache,max-age=0"

aws cloudfront create-invalidation \
  --distribution-id "$CLOUDFRONT_DISTRIBUTION_ID" \
  --paths "/" "/index.html" >/dev/null

echo "Deployment complete: $CLOUDFRONT_URL"