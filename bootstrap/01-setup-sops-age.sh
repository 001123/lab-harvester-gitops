#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# Bước 1: Khởi tạo namespace flux-system và nạp Secret SOPS Age vào Harvester
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

if [[ -f "${REPO_ROOT}/kubeconfig.yaml" ]]; then
  export KUBECONFIG="${REPO_ROOT}/kubeconfig.yaml"
elif [[ -f "${REPO_ROOT}/kubeconfig" ]]; then
  export KUBECONFIG="${REPO_ROOT}/kubeconfig"
fi

if ! command -v kubectl &>/dev/null; then
  echo "❌ Lỗi: 'kubectl' chưa được cài đặt."
  exit 1
fi

AGE_KEY_FILE="${HOME}/.config/sops/age/keys.txt"

if [[ ! -f "${AGE_KEY_FILE}" ]]; then
  echo "❌ Lỗi: Không tìm thấy file private key Age tại ${AGE_KEY_FILE}"
  exit 1
fi

echo "🔐 1. Kiểm tra / Tạo namespace 'flux-system' trên Harvester..."
kubectl create namespace flux-system --dry-run=client -o yaml | kubectl apply -f -

echo "🔑 2. Tạo Secret 'sops-age' trong namespace 'flux-system'..."
kubectl -n flux-system create secret generic sops-age \
  --from-file=age.agekey="${AGE_KEY_FILE}" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "✅ Đã cấu hình Secret sops-age thành công trên Harvester!"
echo "Bước tiếp theo: Chạy './bootstrap/02-install-flux-operator.sh' để cài đặt Flux Operator."
