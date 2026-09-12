#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# Bước 4: Lấy Kubeconfig cụm RKE2 Downstream và Đăng ký vào Argo CD Hub
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

if [[ -f "${REPO_ROOT}/kubeconfig.yaml" ]]; then
  export KUBECONFIG="${REPO_ROOT}/kubeconfig.yaml"
elif [[ -f "${REPO_ROOT}/kubeconfig" ]]; then
  export KUBECONFIG="${REPO_ROOT}/kubeconfig"
fi

RANCHER_KUBECONFIG="${REPO_ROOT}/gitops/infrastructure/rancher-server/rancher-k3s-kubeconfig.yaml"
RKE2_KUBECONFIG="${REPO_ROOT}/gitops/infrastructure/rke2-cluster/rke2-kubeconfig.yaml"

echo "⏳ 1. Chờ cụm RKE2 downstream khởi động hoàn tất trên Rancher..."
while true; do
  READY=$(kubectl --kubeconfig="${RANCHER_KUBECONFIG}" -n fleet-default get cluster.provisioning.cattle.io rke2-lab -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "False")
  if [[ "${READY}" == "True" ]]; then
    echo "✅ Cụm rke2-lab đã ở trạng thái Ready trên Rancher!"
    break
  fi
  MSG=$(kubectl --kubeconfig="${RANCHER_KUBECONFIG}" -n fleet-default get cluster.provisioning.cattle.io rke2-lab -o jsonpath='{.status.conditions[?(@.type=="Ready")].message}' 2>/dev/null || echo "Đang khởi tạo...")
  echo "   ${MSG} (thử lại sau 15s)"
  sleep 15
done

echo "🔑 2. Đang lấy kubeconfig cụm downstream RKE2..."
"${REPO_ROOT}/gitops/infrastructure/rke2-cluster/get-kubeconfig.sh"

if [[ ! -f "${RKE2_KUBECONFIG}" ]]; then
  echo "❌ Lỗi: Không tìm thấy file kubeconfig tại ${RKE2_KUBECONFIG}"
  exit 1
fi

echo "🚢 2. Đăng ký cluster 'rke2-cluster' vào Argo CD Hub..."

SERVER_URL=$(kubectl --kubeconfig="${RKE2_KUBECONFIG}" config view --minify --raw -o jsonpath='{.clusters[0].cluster.server}')
CA_DATA=$(kubectl --kubeconfig="${RKE2_KUBECONFIG}" config view --minify --raw -o jsonpath='{.clusters[0].cluster.certificate-authority-data}' 2>/dev/null || echo "")
BEARER_TOKEN=$(kubectl --kubeconfig="${RKE2_KUBECONFIG}" config view --minify --raw -o jsonpath='{.users[0].user.token}' 2>/dev/null || echo "")
CLIENT_CERT=$(kubectl --kubeconfig="${RKE2_KUBECONFIG}" config view --minify --raw -o jsonpath='{.users[0].user.client-certificate-data}' 2>/dev/null || echo "")
CLIENT_KEY=$(kubectl --kubeconfig="${RKE2_KUBECONFIG}" config view --minify --raw -o jsonpath='{.users[0].user.client-key-data}' 2>/dev/null || echo "")

if [[ -n "${CA_DATA}" ]]; then
  TLS_CONFIG="\"insecure\":false,\"caData\":\"${CA_DATA}\""
else
  TLS_CONFIG="\"insecure\":true"
fi

if [[ -n "${BEARER_TOKEN}" ]]; then
  CONFIG_JSON="{\"bearerToken\":\"${BEARER_TOKEN}\",\"tlsClientConfig\":{${TLS_CONFIG}}}"
else
  CONFIG_JSON="{\"tlsClientConfig\":{${TLS_CONFIG},\"certData\":\"${CLIENT_CERT}\",\"keyData\":\"${CLIENT_KEY}\"}}"
fi

cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Secret
metadata:
  name: cluster-rke2-cluster
  namespace: argocd
  labels:
    argocd.argoproj.io/secret-type: cluster
type: Opaque
stringData:
  name: rke2-cluster
  server: "${SERVER_URL}"
  config: '${CONFIG_JSON}'
EOF

echo "✅ Đã đăng ký cluster 'rke2-cluster' (${SERVER_URL}) vào Argo CD Hub thành công!"
echo "Kiểm tra danh sách cluster trong Argo CD:"
echo "  kubectl -n argocd get secrets -l argocd.argoproj.io/secret-type=cluster"
echo ""

echo "🏷️ 3. Đang tự động gắn nhãn định danh (node-alias) cho các node..."
# Gán nhãn cho Master / Control-plane
cp_nodes=$(kubectl --kubeconfig="${RKE2_KUBECONFIG}" get nodes -l node-role.kubernetes.io/control-plane=true -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || echo "")
idx=1
for node in $cp_nodes; do
  kubectl --kubeconfig="${RKE2_KUBECONFIG}" label node "$node" node-alias="master-${idx}" --overwrite
  echo "   -> Gán nhãn node-alias=master-${idx} cho $node"
  ((idx++))
done

# Gán nhãn cho Worker nodes
wk_nodes=$(kubectl --kubeconfig="${RKE2_KUBECONFIG}" get nodes -l node-role.kubernetes.io/worker=true -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || echo "")
idx=1
for node in $wk_nodes; do
  kubectl --kubeconfig="${RKE2_KUBECONFIG}" label node "$node" node-alias="worker-${idx}" --overwrite
  echo "   -> Gán nhãn node-alias=worker-${idx} cho $node"
  ((idx++))
done

echo ""
echo "Danh sách node sau khi gắn nhãn:"
kubectl --kubeconfig="${RKE2_KUBECONFIG}" get nodes -L node-alias -o wide
echo ""
echo "🎉 Toàn bộ nền tảng và Workloads trên cụm RKE2 sẽ được Argo CD tự động đồng bộ!"
