#!/usr/bin/env bash
# ==============================================================================
# Script xuất Root CA của Rancher Server (192.168.250.30)
# và hướng dẫn thêm vào danh sách tin cậy (Trust Store) trên macOS
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
OUTPUT_CERT="${REPO_ROOT}/rancher-ca.crt"

echo "==> 1. Đang tải chứng chỉ CA từ Rancher Server (192.168.250.30)..."
curl -k -sSL https://rancher.192.168.250.30.sslip.io/v3/settings/cacerts | jq -r .value > "${OUTPUT_CERT}"

if [ ! -s "${OUTPUT_CERT}" ]; then
  echo "❌ Lỗi: Không thể lấy chứng chỉ từ Rancher Server."
  exit 1
fi

echo "✅ Đã xuất chứng chỉ Root CA của Rancher thành công vào:"
echo "   📍 ${OUTPUT_CERT}"
echo ""
echo "------------------------------------------------------------------------------"
echo "📜 THÔNG TIN CHỨNG CHỈ:"
openssl x509 -in "${OUTPUT_CERT}" -noout -subject -issuer -dates
echo "------------------------------------------------------------------------------"
echo ""
echo "🚀 HƯỚNG DẪN CÀI ĐẶT ĐỂ ĐẠT Ổ KHÓA XANH (TRUSTED GREEN LOCK) TRÊN MACOS:"
echo ""
echo "   Chạy lệnh sau trên terminal của bạn:"
echo "   sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain \"${OUTPUT_CERT}\""
echo ""
