#!/usr/bin/env bash
# Rebuild and restart Strata after a git pull.
# Run from the Strata source directory, or pass the path as $1.

set -euo pipefail

STRATA_DIR="${1:-$(cd "$(dirname "$0")/.." && pwd)}"

echo "==> Pulling latest code..."
FLUXION_DIR="$(dirname "$STRATA_DIR")/Fluxion"
if [[ -d "$FLUXION_DIR/.git" ]]; then
  cd "$FLUXION_DIR" && git pull origin feature/database-layer
  cp "$FLUXION_DIR/static/fluxion.js" "$STRATA_DIR/static/fluxion.js"
fi
cd "$STRATA_DIR"
git pull

echo "==> Rebuilding binary..."
sbcl --noinform --disable-debugger --load build.lisp

echo "==> Restarting service..."
sudo systemctl restart strata
sleep 2
sudo systemctl status strata --no-pager -l
