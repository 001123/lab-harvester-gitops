#!/usr/bin/env bash
set -e

HARVESTER_IP="192.168.250.2"
SSH_PORT="31022"
K3S_PORT="31643"
OUTPUT_FILE="$(dirname "$0")/rancher-k3s-kubeconfig.yaml"

echo "Đang lấy kubeconfig từ Rancher Management Node (192.168.250.2:$SSH_PORT)..."

# Lấy k3s.yaml qua SSH với user opensuse
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -p "$SSH_PORT" "opensuse@$HARVESTER_IP" "sudo cat /etc/rancher/k3s/k3s.yaml" > "$OUTPUT_FILE.tmp" 2>/dev/null

if [ ! -s "$OUTPUT_FILE.tmp" ]; then
  echo "Chưa kết nối được SSH hoặc K3s chưa khởi động xong. Vui lòng đợi 1-2 phút rồi thử lại."
  rm -f "$OUTPUT_FILE.tmp"
  exit 1
fi

# Đổi server 127.0.0.1:6443 thành Harvester NodePort IP:PORT
sed -e "s|127.0.0.1:6443|$HARVESTER_IP:$K3S_PORT|g" "$OUTPUT_FILE.tmp" > "$OUTPUT_FILE"
rm -f "$OUTPUT_FILE.tmp"
chmod 600 "$OUTPUT_FILE"

echo "Lấy kubeconfig thành công: $OUTPUT_FILE"
echo "Kiểm tra Rancher pods:"
echo "kubectl --kubeconfig=$OUTPUT_FILE get pods -n cattle-system"
