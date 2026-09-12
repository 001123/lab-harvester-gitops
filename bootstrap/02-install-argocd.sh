#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# Bước 2: Cài đặt Argo CD Hub & KSOPS trên cụm Harvester HCI
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

if [[ -f "${REPO_ROOT}/kubeconfig.yaml" ]]; then
  export KUBECONFIG="${REPO_ROOT}/kubeconfig.yaml"
elif [[ -f "${REPO_ROOT}/kubeconfig" ]]; then
  export KUBECONFIG="${REPO_ROOT}/kubeconfig"
fi

for tool in helm kubectl; do
  if ! command -v "${tool}" &>/dev/null; then
    echo "❌ Thiếu công cụ: '${tool}' chưa được cài đặt."
    exit 1
  fi
done

ARGOCD_CHART_VERSION="10.8.4"

echo "📦 1. Cập nhật Argo Helm repository..."
helm repo add argo https://argoproj.github.io/argo-helm --force-update >/dev/null 2>&1 || true
helm repo update argo >/dev/null

echo "🚢 2. Triển khai Argo CD Hub v${ARGOCD_CHART_VERSION} trên Harvester..."
helm upgrade --install argo-cd argo/argo-cd \
  --version "${ARGOCD_CHART_VERSION}" \
  --namespace argocd \
  --create-namespace \
  -f "${SCRIPT_DIR}/values-argocd-hub.yaml" \
  --wait \
  --timeout 10m

echo "⏳ 3. Chờ các Pods của Argo CD sẵn sàng..."
kubectl -n argocd wait --for=condition=Available deployment/argo-cd-argocd-server --timeout=180s
kubectl -n argocd wait --for=condition=Available deployment/argo-cd-argocd-repo-server --timeout=180s
kubectl -n argocd wait --for=condition=Available deployment/argo-cd-argocd-applicationset-controller --timeout=180s

echo "🚀 4. Khởi tạo Root Application (App-of-Apps)..."
kubectl apply -f "${REPO_ROOT}/gitops/root.yaml"

echo ""
echo "=============================================================================="
echo "🎉 Argo CD Hub đã được cài đặt và cấu hình thành công trên Harvester!"
echo "=============================================================================="
echo "🌐 Web UI: http://192.168.250.2:30080"
echo "👤 Username: admin"
echo -n "🔑 Password: "
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
echo ""
echo "=============================================================================="
echo "Bước tiếp theo: Sau khi máy ảo Rancher Server sẵn sàng, chạy:"
echo "  ./bootstrap/03-register-rancher-cluster.sh"
