#!/bin/bash
# Deploy llm-proxy to remote server
# Usage: ./deploy.sh
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
CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -o llm-proxy-linux .
echo "Built: $(du -h llm-proxy-linux | cut -f1)"

# md5 helper (macOS: md5 -q, Linux: md5sum)
if command -v md5 >/dev/null 2>&1; then
    LOCAL_MD5=$(md5 -q llm-proxy-linux)
else
    LOCAL_MD5=$(md5sum llm-proxy-linux | cut -d' ' -f1)
fi

# Upload to a staging name first, so an interrupted transfer never replaces a
# working binary. (A truncated/corrupt binary fails at startup with
# "invalid function symbol table".)
echo "=== Uploading binary ==="
$SCP llm-proxy-linux $S:~/llm-proxy/llm-proxy.new

echo "=== Verifying checksum ==="
REMOTE_MD5=$($SSH $S "md5sum ~/llm-proxy/llm-proxy.new | cut -d' ' -f1")
if [ "$LOCAL_MD5" != "$REMOTE_MD5" ]; then
    echo "Error: checksum mismatch (local=$LOCAL_MD5 remote=$REMOTE_MD5) — aborting, old binary left untouched"
    $SSH $S "rm -f ~/llm-proxy/llm-proxy.new" || true
    rm -f llm-proxy-linux
    exit 1
fi
echo "OK: $LOCAL_MD5"

# Swap in the new binary, stop the old process, and relaunch.
#  - pkill -x (NOT -f): -x matches the exact process name "llm-proxy". Using
#    -f would match this ssh session's own command line (which contains
#    "llm-proxy"), killing the session mid-restart.
#  - setsid + </dev/null: fully detaches the process so ssh returns instead of
#    hanging on the held session pipe.
echo "=== Swapping binary and restarting ==="
$SSH $S "cd ~/llm-proxy && mv -f llm-proxy.new llm-proxy && chmod +x llm-proxy && pkill -9 -x llm-proxy; sleep 1; setsid ./llm-proxy -config config.yaml </dev/null >/var/log/llm-proxy.log 2>&1 & echo launched"

echo "=== Waiting for startup ==="
sleep 5

if $SSH $S "grep -q cert_file ~/llm-proxy/config.yaml"; then
    SCHEME="https"
else
    SCHEME="http"
fi

if curl -sk --max-time 10 "${SCHEME}://${DEPLOY_SERVER}/health" | grep -q '"ok"'; then
    echo "=== Deploy success ==="
else
    echo "=== Health check failed, checking logs ==="
    $SSH $S "tail -15 /var/log/llm-proxy.log" || true
fi

rm -f llm-proxy-linux
