#!/bin/zsh

echo "=== [001/006] Creating namespace 'onepassword' ==="
kubectl apply -f - <<EOF
apiVersion: v1
kind: Namespace
metadata:
  name: onepassword
EOF

echo "=== [002/006] Reading 'jwt' ==="
jwt=$(op read op://homelab/homelab-1password-jwt/credential)

echo "=== [003/006] Reading '1password-credentials.json' ==="
credentials=$(op read op://homelab/homelab-1password-credentials/1password-credentials.json | base64)

echo "=== [004/006] Creating secret 'op-token' ==="
kubectl create secret generic --namespace onepassword op-token \
  --from-literal=token="$jwt"

echo "=== [005/006] Creating secret 'connect-server-credentials' ==="
kubectl create secret generic --namespace onepassword op-credentials \
  --from-literal=1password-credentials.json="${credentials}"

echo "=== [006/006] Secret Bootstrapping complete, continue on with the rest of the bootstrapping process."
exit 0



