#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# Bước 3: Lấy Kubeconfig Rancher Server và Đăng ký Remote Cluster vào Argo CD Hub
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

if [[ -f "${REPO_ROOT}/kubeconfig.yaml" ]]; then
  export KUBECONFIG="${REPO_ROOT}/kubeconfig.yaml"
elif [[ -f "${REPO_ROOT}/kubeconfig" ]]; then
  export KUBECONFIG="${REPO_ROOT}/kubeconfig"
fi

RANCHER_KUBECONFIG="${REPO_ROOT}/gitops/infrastructure/rancher-server/rancher-k3s-kubeconfig.yaml"

echo "⏳ 1. Kiểm tra trạng thái máy ảo Rancher Server trên Harvester..."
while true; do
  VM_STATUS=$(kubectl get vm rancher-server -n default -o jsonpath='{.status.printableStatus}' 2>/dev/null || echo "NotFound")
  if [[ "${VM_STATUS}" == "Running" ]]; then
    echo "✅ Máy ảo rancher-server đang ở trạng thái Running!"
    break
  fi
  echo "   Đang chờ máy ảo khởi động (Trạng thái hiện tại: ${VM_STATUS})... Thử lại sau 10s"
  sleep 10
done

echo "🔑 2. Đang lấy kubeconfig từ Rancher Server (K3s)..."
"${REPO_ROOT}/gitops/infrastructure/rancher-server/get-kubeconfig.sh"

if [[ ! -f "${RANCHER_KUBECONFIG}" ]]; then
  echo "❌ Lỗi: Không tìm thấy file kubeconfig tại ${RANCHER_KUBECONFIG}"
  exit 1
fi

echo "🚢 3. Đăng ký cluster 'rancher-server' vào Argo CD Hub..."

# Trích xuất thông tin cert và key từ kubeconfig
SERVER_URL=$(kubectl --kubeconfig="${RANCHER_KUBECONFIG}" config view --minify --raw -o jsonpath='{.clusters[0].cluster.server}')
CA_DATA=$(kubectl --kubeconfig="${RANCHER_KUBECONFIG}" config view --minify --raw -o jsonpath='{.clusters[0].cluster.certificate-authority-data}')
CLIENT_CERT=$(kubectl --kubeconfig="${RANCHER_KUBECONFIG}" config view --minify --raw -o jsonpath='{.users[0].user.client-certificate-data}')
CLIENT_KEY=$(kubectl --kubeconfig="${RANCHER_KUBECONFIG}" config view --minify --raw -o jsonpath='{.users[0].user.client-key-data}')

# Áp dụng Secret cluster cho Argo CD
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Secret
metadata:
  name: cluster-rancher-server
  namespace: argocd
  labels:
    argocd.argoproj.io/secret-type: cluster
type: Opaque
stringData:
  name: rancher-server
  server: "${SERVER_URL}"
  config: |
    {
      "tlsClientConfig": {
        "insecure": false,
        "caData": "${CA_DATA}",
        "certData": "${CLIENT_CERT}",
        "keyData": "${CLIENT_KEY}"
      }
    }
EOF

echo "✅ Đã đăng ký cluster 'rancher-server' (${SERVER_URL}) vào Argo CD Hub thành công!"
echo "Kiểm tra danh sách cluster trong Argo CD:"
echo "  kubectl -n argocd get secrets -l argocd.argoproj.io/secret-type=cluster"
echo ""
echo "Bước tiếp theo: Sau khi cụm downstream RKE2 được Rancher tạo xong, chạy:"
echo "  ./bootstrap/04-register-rke2-cluster.sh"
