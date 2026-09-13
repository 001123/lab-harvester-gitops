#!/usr/bin/env bash
# ==============================================================================
# Script xuất Root CA "Harvester HomeLab i5" từ cụm RKE2
# và hướng dẫn thêm vào danh sách tin cậy (Trust Store) trên Mac / Linux / Windows
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

KUBECONFIG_PATH="${KUBECONFIG:-${REPO_ROOT}/gitops/infrastructure/rke2-cluster/rke2-kubeconfig.yaml}"
OUTPUT_CERT="${REPO_ROOT}/homelab-root-ca.crt"

echo "==> 1. Kiểm tra kubeconfig RKE2..."
if [[ ! -f "${KUBECONFIG_PATH}" ]]; then
  echo "❌ Lỗi: Không tìm thấy file kubeconfig tại: ${KUBECONFIG_PATH}"
  echo "    Hãy đảm bảo cụm RKE2 đã được đăng ký và file kubeconfig đã sẵn sàng."
  exit 1
fi

echo "==> 2. Đang lấy Secret Root CA từ namespace 'cert-manager'..."
if ! kubectl --kubeconfig="${KUBECONFIG_PATH}" -n cert-manager get secret homelab-root-ca-secret >/dev/null 2>&1; then
  echo "❌ Lỗi: Secret 'homelab-root-ca-secret' chưa sẵn sàng trong namespace 'cert-manager'."
  echo "    Hãy kiểm tra lại Argo CD đã đồng bộ xong Application 'cluster-issuers' chưa:"
  echo "    kubectl --kubeconfig=${KUBECONFIG_PATH} -n cert-manager get certificate homelab-root-ca"
  exit 1
fi

# Trích xuất chứng chỉ ca.crt hoặc tls.crt
kubectl --kubeconfig="${KUBECONFIG_PATH}" -n cert-manager get secret homelab-root-ca-secret \
  -o jsonpath='{.data.tls\.crt}' | base64 -d > "${OUTPUT_CERT}"

echo "✅ Đã xuất chứng chỉ Root CA thành công vào:"
echo "   📍 ${OUTPUT_CERT}"
echo ""
echo "------------------------------------------------------------------------------"
echo "📜 THÔNG TIN CHỨNG CHỈ:"
openssl x509 -in "${OUTPUT_CERT}" -noout -subject -issuer -dates
echo "------------------------------------------------------------------------------"
echo ""
echo "🚀 HƯỚNG DẪN CÀI ĐẶT ĐỂ ĐẠT Ổ KHÓA XANH (TRUSTED GREEN LOCK):"
echo ""
echo "🍎 TRÊN MACOS:"
echo "   Chạy lệnh sau trên terminal máy Mac của bạn:"
echo "   sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain \"${OUTPUT_CERT}\""
echo ""
echo "🐧 TRÊN UBUNTU / DEBIAN LINUX:"
echo "   sudo cp \"${OUTPUT_CERT}\" /usr/local/share/ca-certificates/homelab-root-ca.crt"
echo "   sudo update-ca-certificates"
echo ""
echo "🪟 TRÊN WINDOWS:"
echo "   1. Nhấp đúp vào file 'homelab-root-ca.crt'"
echo "   2. Chọn 'Install Certificate...' -> Chọn 'Local Machine'"
echo "   3. Chọn 'Place all certificates in the following store'"
echo "   4. Chọn 'Trusted Root Certification Authorities' -> Finish"
echo ""
echo "📱 TRÊN IOS / ANDROID:"
echo "   Gửi file 'homelab-root-ca.crt' qua AirDrop / Email / Google Drive và cài vào Profile / Security Certificates."
echo "=============================================================================="
