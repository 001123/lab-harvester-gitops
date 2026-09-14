#!/usr/bin/env bash
set -e

RANCHER_IP="192.168.250.30"
SSH_PORT="22"
K3S_PORT="6443"
OUTPUT_FILE="$(dirname "$0")/rancher-k3s-kubeconfig.yaml"

echo "Đang lấy kubeconfig từ Rancher Management Node ($RANCHER_IP:$SSH_PORT)..."

# Lấy k3s.yaml qua SSH với user opensuse
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -p "$SSH_PORT" "opensuse@$RANCHER_IP" "sudo cat /etc/rancher/k3s/k3s.yaml" > "$OUTPUT_FILE.tmp" 2>/dev/null

if [ ! -s "$OUTPUT_FILE.tmp" ]; then
  echo "Chưa kết nối được SSH hoặc K3s chưa khởi động xong. Vui lòng đợi 1-2 phút rồi thử lại."
  rm -f "$OUTPUT_FILE.tmp"
  exit 1
fi

# Đổi server 127.0.0.1:6443 thành Rancher IP:PORT
sed -e "s|127.0.0.1:6443|$RANCHER_IP:$K3S_PORT|g" "$OUTPUT_FILE.tmp" > "$OUTPUT_FILE"
rm -f "$OUTPUT_FILE.tmp"
chmod 600 "$OUTPUT_FILE"

echo "Lấy kubeconfig thành công: $OUTPUT_FILE"
echo "Kiểm tra Rancher pods:"
echo "kubectl --kubeconfig=$OUTPUT_FILE get pods -n cattle-system"
