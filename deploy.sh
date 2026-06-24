#!/bin/bash
# Deploy llm-proxy to remote server
# Usage: ./deploy.sh
#
# MIGRATION NOTE (repo renamed cli-proxy -> llm-proxy, 2026-06):
#   The remote server still runs under ~/cli-proxy/ (binary, /var/log/cli-proxy.log)
#   and the data dir is still ~/.cli-proxy (OAuth tokens, stats.db, API keys).
#   These paths are intentionally LEFT AS-IS here so this script keeps working
#   against the un-migrated server. To migrate the box to llm-proxy, do a
#   coordinated switch: stop old process, mv ~/cli-proxy ~/llm-proxy and
#   mv ~/.cli-proxy ~/.llm-proxy, then update the paths below + token_dir.
#
# Required env vars (set in .bashrc/.zshrc):
#   DEPLOY_SERVER   - server IP
#   DEPLOY_PASSWORD - SSH password

if [ -z "$DEPLOY_SERVER" ] || [ -z "$DEPLOY_PASSWORD" ]; then
    echo "Error: DEPLOY_SERVER and DEPLOY_PASSWORD env vars are required"
    echo "Add to your ~/.zshrc:"
    echo '  export DEPLOY_SERVER="your-server-ip"'
    echo '  export DEPLOY_PASSWORD="your-password"'
    exit 1
fi

set -e
export SSHPASS="$DEPLOY_PASSWORD"
SSH="sshpass -e ssh -o StrictHostKeyChecking=no -o ConnectTimeout=20"
SCP="sshpass -e scp -o StrictHostKeyChecking=no -o ConnectTimeout=20"
S="root@$DEPLOY_SERVER"

echo "=== Building for Linux ==="
CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -o cli-proxy-linux .
echo "Built: $(du -h cli-proxy-linux | cut -f1)"

# md5 helper (macOS: md5 -q, Linux: md5sum)
if command -v md5 >/dev/null 2>&1; then
    LOCAL_MD5=$(md5 -q cli-proxy-linux)
else
    LOCAL_MD5=$(md5sum cli-proxy-linux | cut -d' ' -f1)
fi

# Upload to a staging name first, so an interrupted transfer never replaces a
# working binary. (A truncated/corrupt binary fails at startup with
# "invalid function symbol table".)
echo "=== Uploading binary ==="
$SCP cli-proxy-linux $S:~/cli-proxy/cli-proxy.new

echo "=== Verifying checksum ==="
REMOTE_MD5=$($SSH $S "md5sum ~/cli-proxy/cli-proxy.new | cut -d' ' -f1")
if [ "$LOCAL_MD5" != "$REMOTE_MD5" ]; then
    echo "Error: checksum mismatch (local=$LOCAL_MD5 remote=$REMOTE_MD5) — aborting, old binary left untouched"
    $SSH $S "rm -f ~/cli-proxy/cli-proxy.new" || true
    rm -f cli-proxy-linux
    exit 1
fi
echo "OK: $LOCAL_MD5"

# Swap in the new binary, stop the old process, and relaunch.
#  - pkill -x (NOT -f): -x matches the exact process name "cli-proxy". Using
#    -f would match this ssh session's own command line (which contains
#    "cli-proxy"), killing the session mid-restart.
#  - setsid + </dev/null: fully detaches the process so ssh returns instead of
#    hanging on the held session pipe.
echo "=== Swapping binary and restarting ==="
$SSH $S "cd ~/cli-proxy && mv -f cli-proxy.new cli-proxy && chmod +x cli-proxy && pkill -9 -x cli-proxy; sleep 1; setsid ./cli-proxy -config config.yaml </dev/null >/var/log/cli-proxy.log 2>&1 & echo launched"

echo "=== Waiting for startup ==="
sleep 5

if $SSH $S "grep -q cert_file ~/cli-proxy/config.yaml"; then
    SCHEME="https"
else
    SCHEME="http"
fi

if curl -sk --max-time 10 "${SCHEME}://${DEPLOY_SERVER}/health" | grep -q '"ok"'; then
    echo "=== Deploy success ==="
else
    echo "=== Health check failed, checking logs ==="
    $SSH $S "tail -15 /var/log/cli-proxy.log" || true
fi

rm -f cli-proxy-linux
