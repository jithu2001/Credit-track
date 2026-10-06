#!/usr/bin/env bash
# Copies the website to the server (https://wholeflow.jitsuji.xyz).
#   website/deploy.sh
# Needs the `ssh wholeflow` alias (see the root README, step 2).
set -euo pipefail
cd "$(dirname "$0")"
sed -i "s#<lastmod>.*</lastmod>#<lastmod>$(date +%F)</lastmod>#" sitemap.xml
rsync -a --delete --chmod=D755,F644 \
  --exclude tools/ --exclude deploy.sh --exclude README.md \
  ./ wholeflow:/var/www/wholeflow-site/
echo "Deployed. Check: curl -sI https://wholeflow.jitsuji.xyz/"
