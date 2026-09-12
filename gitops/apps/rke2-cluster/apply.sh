#!/usr/bin/env bash
set -e

DIR="$(cd "$(dirname "$0")" && pwd)"
RANCHER_KUBECONFIG="$DIR/../rancher-k3s-kubeconfig.yaml"
HARVESTER_KUBECONFIG="$DIR/../../kubeconfig.yaml"

echo "=== 1. Đảm bảo Image openSUSE Leap Micro 6.2 đã có trên Harvester ==="
kubectl --kubeconfig="$HARVESTER_KUBECONFIG" apply -f "$DIR/00-image.yaml"

echo "Chờ Image hoàn tất tải về (Imported: True)..."
while true; do
  IMPORTED=$(kubectl --kubeconfig="$HARVESTER_KUBECONFIG" get virtualmachineimage opensuse-leap-micro-62 -n default -o jsonpath='{.status.conditions[?(@.type=="Imported")].status}' 2>/dev/null || true)
  PROGRESS=$(kubectl --kubeconfig="$HARVESTER_KUBECONFIG" get virtualmachineimage opensuse-leap-micro-62 -n default -o jsonpath='{.status.progress}' 2>/dev/null || true)
  if [ "$IMPORTED" = "True" ]; then
    echo ">> Image opensuse-leap-micro-62 đã sẵn sàng 100%!"
    break
  fi
  echo "Đang tải image... Tiến độ: ${PROGRESS:-0}%"
  sleep 5
done

echo ""
echo "=== 2. Áp dụng khai báo cụm RKE2 lên Rancher Server ==="
kubectl --kubeconfig="$RANCHER_KUBECONFIG" apply -k "$DIR"

echo ""
echo "=== 3. Kiểm tra trạng thái Cluster trên Rancher ==="
kubectl --kubeconfig="$RANCHER_KUBECONFIG" get clusters.provisioning.cattle.io -n fleet-default

echo ""
echo "=== 4. Rancher đang bắt đầu gọi Harvester API để tạo VM... ==="
echo "Kiểm tra danh sách VM trên Harvester:"
kubectl --kubeconfig="$HARVESTER_KUBECONFIG" get vm -A

