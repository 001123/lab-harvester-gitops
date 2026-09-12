#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# Bước 4: Lấy Kubeconfig cụm RKE2 Downstream và Đăng ký vào Argo CD Hub
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

if [[ -f "${REPO_ROOT}/kubeconfig.yaml" ]]; then
  export KUBECONFIG="${REPO_ROOT}/kubeconfig.yaml"
elif [[ -f "${REPO_ROOT}/kubeconfig" ]]; then
  export KUBECONFIG="${REPO_ROOT}/kubeconfig"
fi

RKE2_KUBECONFIG="${REPO_ROOT}/gitops/infrastructure/rke2-cluster/rke2-kubeconfig.yaml"

echo "⏳ 1. Đang lấy kubeconfig cụm downstream RKE2..."
"${REPO_ROOT}/gitops/infrastructure/rke2-cluster/get-kubeconfig.sh"

if [[ ! -f "${RKE2_KUBECONFIG}" ]]; then
  echo "❌ Lỗi: Không tìm thấy file kubeconfig tại ${RKE2_KUBECONFIG}"
  exit 1
fi

echo "🚢 2. Đăng ký cluster 'rke2-cluster' vào Argo CD Hub..."

SERVER_URL=$(kubectl --kubeconfig="${RKE2_KUBECONFIG}" config view --minify --raw -o jsonpath='{.clusters[0].cluster.server}')
CA_DATA=$(kubectl --kubeconfig="${RKE2_KUBECONFIG}" config view --minify --raw -o jsonpath='{.clusters[0].cluster.certificate-authority-data}' 2>/dev/null || echo "")
BEARER_TOKEN=$(kubectl --kubeconfig="${RKE2_KUBECONFIG}" config view --minify --raw -o jsonpath='{.users[0].user.token}' 2>/dev/null || echo "")
CLIENT_CERT=$(kubectl --kubeconfig="${RKE2_KUBECONFIG}" config view --minify --raw -o jsonpath='{.users[0].user.client-certificate-data}' 2>/dev/null || echo "")
CLIENT_KEY=$(kubectl --kubeconfig="${RKE2_KUBECONFIG}" config view --minify --raw -o jsonpath='{.users[0].user.client-key-data}' 2>/dev/null || echo "")

if [[ -n "${CA_DATA}" ]]; then
  TLS_CONFIG="\"insecure\":false,\"caData\":\"${CA_DATA}\""
else
  TLS_CONFIG="\"insecure\":true"
fi

if [[ -n "${BEARER_TOKEN}" ]]; then
  CONFIG_JSON="{\"bearerToken\":\"${BEARER_TOKEN}\",\"tlsClientConfig\":{${TLS_CONFIG}}}"
else
  CONFIG_JSON="{\"tlsClientConfig\":{${TLS_CONFIG},\"certData\":\"${CLIENT_CERT}\",\"keyData\":\"${CLIENT_KEY}\"}}"
fi

cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Secret
metadata:
  name: cluster-rke2-cluster
  namespace: argocd
  labels:
    argocd.argoproj.io/secret-type: cluster
type: Opaque
stringData:
  name: rke2-cluster
  server: "${SERVER_URL}"
  config: '${CONFIG_JSON}'
EOF

echo "✅ Đã đăng ký cluster 'rke2-cluster' (${SERVER_URL}) vào Argo CD Hub thành công!"
echo "Kiểm tra danh sách cluster trong Argo CD:"
echo "  kubectl -n argocd get secrets -l argocd.argoproj.io/secret-type=cluster"
echo ""
echo "🎉 Toàn bộ nền tảng và Workloads trên cụm RKE2 sẽ được Argo CD tự động đồng bộ!"
