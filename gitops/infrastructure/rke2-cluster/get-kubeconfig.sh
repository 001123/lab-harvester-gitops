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

# Lấy CA certificate của Rancher Ingress để bảo đảm kết nối TLS chuẩn từ Flux và Helm
RANCHER_CA=$(ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -p "$SSH_PORT" "opensuse@$HARVESTER_IP" \
  "sudo /usr/local/bin/k3s kubectl -n cattle-system get secret tls-rancher-ingress -o jsonpath='{.data.ca\.crt}'" 2>/dev/null || true)

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

REPO_ROOT="$(cd "$DIR/../../.." && pwd)"
HARVESTER_KUBECONFIG=""
if [[ -f "$REPO_ROOT/kubeconfig.yaml" ]]; then
  HARVESTER_KUBECONFIG="$REPO_ROOT/kubeconfig.yaml"
elif [[ -f "$REPO_ROOT/kubeconfig" ]]; then
  HARVESTER_KUBECONFIG="$REPO_ROOT/kubeconfig"
fi

# Nạp Secret rke2-kubeconfig vào namespace flux-system trên Harvester
if [[ -n "$HARVESTER_KUBECONFIG" ]]; then
  echo ""
  echo "=== 2. Đồng bộ Secret 'rke2-kubeconfig' vào namespace 'flux-system' trên Harvester ==="
  kubectl --kubeconfig="$HARVESTER_KUBECONFIG" --insecure-skip-tls-verify -n flux-system create secret generic rke2-kubeconfig \
    --from-file=value="$OUTPUT_FILE" \
    --dry-run=client -o yaml | kubectl --kubeconfig="$HARVESTER_KUBECONFIG" --insecure-skip-tls-verify apply -f -
  echo ">> Đã cập nhật Secret 'rke2-kubeconfig' thành công trên Harvester!"
fi

# Nạp Secret sops-age vào namespace argocd trên RKE2
AGE_KEY_FILE="${HOME}/.config/sops/age/keys.txt"
if [[ -f "$AGE_KEY_FILE" ]]; then
  echo ""
  echo "=== 3. Khởi tạo namespace 'argocd' và nạp Secret 'sops-age' trên RKE2 ==="
  kubectl --kubeconfig="$OUTPUT_FILE" create namespace argocd --dry-run=client -o yaml | kubectl --kubeconfig="$OUTPUT_FILE" apply -f -
  kubectl --kubeconfig="$OUTPUT_FILE" -n argocd create secret generic sops-age \
    --from-file=age.agekey="$AGE_KEY_FILE" \
    --dry-run=client -o yaml | kubectl --kubeconfig="$OUTPUT_FILE" apply -f -
  echo ">> Đã nạp Secret 'sops-age' vào namespace 'argocd' trên RKE2 thành công!"
fi
