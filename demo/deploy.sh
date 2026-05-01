#!/usr/bin/env bash
set -euo pipefail

WORK_BACKEND="$HOME/work/backend"   # adjust
WORK_FRONTEND="$HOME/work/frontend" # adjust
PROD=/opt/myapp

echo "==> Building frontend"
(cd "$WORK_FRONTEND" && pnpm install --frozen-lockfile && pnpm build)

echo "==> Syncing backend"
sudo rsync -a --delete \
    --exclude '__pycache__' --exclude '.venv' --exclude '.env' \
    "$WORK_BACKEND"/ "$PROD/backend/"

echo "==> Syncing frontend dist"
sudo rsync -a --delete "$WORK_FRONTEND/dist"/ "$PROD/frontend/"

echo "==> Updating venv + deps"
sudo -u myapp bash -c "
    cd $PROD/backend
    [ -d .venv ] || python3 -m venv .venv
    .venv/bin/pip install --upgrade pip wheel
    .venv/bin/pip install -r requirements.txt
"

sudo chown -R myapp:myapp "$PROD/backend" "$PROD/frontend"

echo "==> Restarting services"
sudo systemctl restart myapp-backend.service
# midi service auto-restarts via BindsTo, but be explicit:
sudo systemctl restart myapp-midi.service

echo "==> Done"
