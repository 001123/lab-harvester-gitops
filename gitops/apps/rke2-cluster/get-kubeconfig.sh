#!/usr/bin/env bash
set -e

DIR="$(cd "$(dirname "$0")" && pwd)"
OUTPUT_FILE="$DIR/rke2-kubeconfig.yaml"
HARVESTER_IP="192.168.250.2"
SSH_PORT="31022"
RANCHER_HOST="rancher.192.168.250.2.sslip.io:31443"

echo "=== Đang lấy Kubeconfig cho cụm RKE2 (rke2-lab) ==="

# Lấy kubeconfig từ secret rke2-lab-kubeconfig trong namespace fleet-default trên Rancher
KUBECONFIG_DATA=$(ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -p "$SSH_PORT" "opensuse@$HARVESTER_IP" \
  "sudo /usr/local/bin/k3s kubectl -n fleet-default get secret rke2-lab-kubeconfig -o jsonpath='{.data.value}'" 2>/dev/null || true)

if [ -z "$KUBECONFIG_DATA" ]; then
  echo "Lỗi: Không lấy được secret rke2-lab-kubeconfig từ Rancher Server."
  echo "Vui lòng kiểm tra lại SSH hoặc trạng thái cụm rke2-lab trên Rancher."
  exit 1
fi

# Giải mã Base64 và thay thế địa chỉ endpoint nội bộ 10.43.x.x bằng endpoint Rancher Proxy qua NodePort
echo "$KUBECONFIG_DATA" | base64 -d | sed -e "s|https://10.43.[0-9.]*|https://$RANCHER_HOST|g" > "$OUTPUT_FILE"
chmod 600 "$OUTPUT_FILE"

echo ">> Đã lưu kubeconfig thành công tại: $OUTPUT_FILE"
echo ""
echo "=== Kiểm tra kết nối tới cụm RKE2 ==="
kubectl --kubeconfig="$OUTPUT_FILE" --insecure-skip-tls-verify get nodes -o wide
