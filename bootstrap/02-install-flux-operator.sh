#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# Bước 2: Cài đặt ControlPlane Flux Operator v0.60.0 & Khởi tạo FluxInstance
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

FLUX_OPERATOR_VERSION="0.60.0"

# Temporary clean docker config directory to prevent osxkeychain credential helper issues
TMP_DOCKER_DIR="$(mktemp -d)"
echo '{}' > "${TMP_DOCKER_DIR}/config.json"
trap 'rm -rf "${TMP_DOCKER_DIR}"' EXIT

echo "🚢 1. Cài đặt Flux Operator v${FLUX_OPERATOR_VERSION} qua Helm OCI..."
DOCKER_CONFIG="${TMP_DOCKER_DIR}" helm upgrade --install flux-operator \
  oci://ghcr.io/controlplaneio-fluxcd/charts/flux-operator \
  --version "${FLUX_OPERATOR_VERSION}" \
  --namespace flux-system \
  --create-namespace \
  --wait

echo "⏳ 2. Đang chờ deployment flux-operator sẵn sàng..."
kubectl -n flux-system wait --for=condition=Available deployment/flux-operator --timeout=120s

echo "🚀 3. Áp dụng FluxInstance GitOps manifests..."
kubectl apply -k "${REPO_ROOT}/gitops/flux-system"

echo "✅ Flux Operator v${FLUX_OPERATOR_VERSION} và FluxInstance đã được triển khai thành công!"
echo "Kiểm tra tiến trình Flux sync:"
echo "  kubectl -n flux-system get fluxinstances"
echo "  kubectl -n flux-system get gitrepositories"
echo "  kubectl -n flux-system get kustomizations"
echo ""
echo "Truy cập giao diện Flux Operator Dashboard (nếu cần):"
echo "  kubectl -n flux-system port-forward svc/flux-operator 9080:9080"
echo "  Mở trình duyệt: http://localhost:9080"
