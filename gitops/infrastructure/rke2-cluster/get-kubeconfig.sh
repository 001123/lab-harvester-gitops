#!/usr/bin/env bash
set -e

DIR="$(cd "$(dirname "$0")" && pwd)"
OUTPUT_FILE="$DIR/rke2-kubeconfig.yaml"
HARVESTER_IP="192.168.250.2"
RANCHER_HOST="rancher.192.168.250.2.sslip.io:31443"
REPO_ROOT="$(cd "$DIR/../../.." && pwd)"
RANCHER_KUBECONFIG="${REPO_ROOT}/gitops/infrastructure/rancher-server/rancher-k3s-kubeconfig.yaml"

echo "=== Đang lấy Kubeconfig cho cụm RKE2 (rke2-lab) ==="

# Lấy kubeconfig từ secret rke2-lab-kubeconfig trong namespace fleet-default trên Rancher
if [[ -f "${RANCHER_KUBECONFIG}" ]]; then
  KUBECONFIG_DATA=$(kubectl --kubeconfig="${RANCHER_KUBECONFIG}" -n fleet-default get secret rke2-lab-kubeconfig -o jsonpath='{.data.value}' 2>/dev/null || true)
  RANCHER_CA=$(kubectl --kubeconfig="${RANCHER_KUBECONFIG}" -n cattle-system get secret tls-rancher-ingress -o jsonpath='{.data.ca\.crt}' 2>/dev/null || true)
fi

if [[ -z "${KUBECONFIG_DATA:-}" ]]; then
  SSH_PORT="31022"
  KUBECONFIG_DATA=$(ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -p "$SSH_PORT" "opensuse@$HARVESTER_IP" \
    "sudo /usr/local/bin/k3s kubectl -n fleet-default get secret rke2-lab-kubeconfig -o jsonpath='{.data.value}'" 2>/dev/null || true)
  RANCHER_CA=$(ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -p "$SSH_PORT" "opensuse@$HARVESTER_IP" \
    "sudo /usr/local/bin/k3s kubectl -n cattle-system get secret tls-rancher-ingress -o jsonpath='{.data.ca\.crt}'" 2>/dev/null || true)
fi

if [ -z "$KUBECONFIG_DATA" ]; then
  echo "Lỗi: Không lấy được secret rke2-lab-kubeconfig từ Rancher Server."
  echo "Vui lòng kiểm tra lại SSH hoặc trạng thái cụm rke2-lab trên Rancher."
  exit 1
fi

if [ -n "$RANCHER_CA" ]; then
  echo ">> Tìm thấy Rancher Ingress CA certificate, cấu hình TLS CA đầy đủ..."
  echo "$KUBECONFIG_DATA" | base64 -d \
    | sed -e "s|https://10.43.[0-9.]*|https://$RANCHER_HOST|g" \
    | sed -e "s|certificate-authority-data: .*|certificate-authority-data: $RANCHER_CA|g" > "$OUTPUT_FILE"
else
  echo ">> Không tìm thấy Rancher CA, cấu hình insecure-skip-tls-verify..."
  echo "$KUBECONFIG_DATA" | base64 -d \
    | sed -e "s|https://10.43.[0-9.]*|https://$RANCHER_HOST|g" \
    | sed -e "s|certificate-authority-data: .*|insecure-skip-tls-verify: true|g" > "$OUTPUT_FILE"
fi
chmod 600 "$OUTPUT_FILE"

echo ">> Đã lưu kubeconfig thành công tại: $OUTPUT_FILE"
echo ""
echo "=== 1. Kiểm tra kết nối tới cụm RKE2 ==="
kubectl --kubeconfig="$OUTPUT_FILE" get nodes -o wide

