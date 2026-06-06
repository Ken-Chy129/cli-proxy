#!/bin/bash
# Deploy cli-proxy to remote server
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

echo "=== Building for Linux ==="
CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -o cli-proxy-linux .
echo "Built: $(du -h cli-proxy-linux | cut -f1)"

echo "=== Stopping remote service ==="
export SSHPASS="$DEPLOY_PASSWORD"
sshpass -e ssh -o StrictHostKeyChecking=no root@$DEPLOY_SERVER "pkill -9 -f cli-proxy; sleep 1; rm -f ~/cli-proxy/cli-proxy" 2>/dev/null || true

echo "=== Uploading binary ==="
sshpass -e scp -o StrictHostKeyChecking=no cli-proxy-linux root@$DEPLOY_SERVER:~/cli-proxy/cli-proxy

echo "=== Starting service ==="
sshpass -e ssh -o StrictHostKeyChecking=no root@$DEPLOY_SERVER "chmod +x ~/cli-proxy/cli-proxy; cd ~/cli-proxy && nohup ./cli-proxy -config config.yaml > /var/log/cli-proxy.log 2>&1 &"

echo "=== Waiting for startup ==="
sleep 15

HEALTH_URL=$(sshpass -e ssh -o StrictHostKeyChecking=no root@$DEPLOY_SERVER "grep cert_file ~/cli-proxy/config.yaml" 2>/dev/null)
if [ -n "$HEALTH_URL" ]; then
    SCHEME="https"
else
    SCHEME="http"
fi

if curl -sk --max-time 10 "${SCHEME}://${DEPLOY_SERVER}/health" | grep -q '"ok"'; then
    echo "=== Deploy success ==="
else
    echo "=== Health check failed, checking logs ==="
    sshpass -e ssh -o StrictHostKeyChecking=no root@$DEPLOY_SERVER "tail -5 /var/log/cli-proxy.log" 2>/dev/null || true
fi

rm -f cli-proxy-linux
