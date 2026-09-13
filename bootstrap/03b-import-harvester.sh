#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# Bước 3b: Import Harvester vào Rancher, Khởi tạo Cloud Credential và
# Tự động cập nhật gitops/applications/02-rke2-cluster.yaml
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

if [[ -f "${REPO_ROOT}/kubeconfig.yaml" ]]; then
  HARVESTER_KUBECONFIG="${REPO_ROOT}/kubeconfig.yaml"
elif [[ -f "${REPO_ROOT}/kubeconfig" ]]; then
  HARVESTER_KUBECONFIG="${REPO_ROOT}/kubeconfig"
else
  echo "❌ Lỗi: Không tìm thấy file kubeconfig của Harvester tại ${REPO_ROOT}/kubeconfig.yaml"
  exit 1
fi

RANCHER_KUBECONFIG="${REPO_ROOT}/gitops/infrastructure/rancher-server/rancher-k3s-kubeconfig.yaml"
RKE2_APP_YAML="${REPO_ROOT}/gitops/applications/02-rke2-cluster.yaml"

if [[ ! -f "${RANCHER_KUBECONFIG}" ]]; then
  echo "❌ Lỗi: Không tìm thấy file kubeconfig của Rancher tại ${RANCHER_KUBECONFIG}"
  echo "Vui lòng chạy './bootstrap/03-register-rancher-cluster.sh' trước."
  exit 1
fi

echo "========================================================================"
echo "🚀 BẮT ĐẦU IMPORT HARVESTER VÀO RANCHER & TỰ ĐỘNG HÓA GITOPS"
echo "========================================================================"

# 1. Kiểm tra / Khởi tạo Cluster harvester-local trên Rancher
echo "🔍 1. Kiểm tra cụm 'harvester-local' trên Rancher Server..."
CLUSTER_ID=$(kubectl --kubeconfig="${RANCHER_KUBECONFIG}" get clusters.management.cattle.io -o jsonpath='{range .items[?(@.spec.displayName=="harvester-local")]}{.metadata.name}{end}' 2>/dev/null || echo "")

if [[ -z "${CLUSTER_ID}" ]]; then
  echo "   Chưa tìm thấy cụm 'harvester-local'. Đang tạo mới trên Rancher..."
  cat <<EOF | kubectl --kubeconfig="${RANCHER_KUBECONFIG}" apply -f -
apiVersion: management.cattle.io/v3
kind: Cluster
metadata:
  generateName: c-
  labels:
    provider.cattle.io: harvester
spec:
  displayName: harvester-local
EOF

  echo "   Đang chờ Rancher khởi tạo Cluster ID (c-xxxxx)..."
  while [[ -z "${CLUSTER_ID}" ]]; do
    sleep 3
    CLUSTER_ID=$(kubectl --kubeconfig="${RANCHER_KUBECONFIG}" get clusters.management.cattle.io -o jsonpath='{range .items[?(@.spec.displayName=="harvester-local")]}{.metadata.name}{end}' 2>/dev/null || echo "")
  done
fi

echo "✅ Cluster ID của Harvester: ${CLUSTER_ID}"

# 2. Lấy Registration Token và Manifest từ Rancher
echo "🔑 2. Đang lấy registration manifest từ Rancher Server..."
REG_TOKEN=""
for i in {1..30}; do
  REG_TOKEN=$(kubectl --kubeconfig="${RANCHER_KUBECONFIG}" -n "${CLUSTER_ID}" get secret crt-token-default-token -o jsonpath='{.data.token}' 2>/dev/null | base64 -d || echo "")
  if [[ -n "${REG_TOKEN}" ]]; then
    break
  fi
  echo "   Đang chờ Rancher sinh crt-token-default-token... (${i}/30)"
  sleep 3
done

if [[ -z "${REG_TOKEN}" ]]; then
  echo "❌ Lỗi: Không lấy được token đăng ký từ Rancher"
  exit 1
fi

RAW_URL=$(kubectl --kubeconfig="${RANCHER_KUBECONFIG}" -n "${CLUSTER_ID}" get clusterregistrationtokens.management.cattle.io default-token -o jsonpath='{.status.manifestUrl}' 2>/dev/null || echo "")
MANIFEST_URL="${RAW_URL/\{token\}/${REG_TOKEN}}"

echo "📥 3. Áp dụng registration manifest vào cụm Harvester..."
curl -k -sSL "${MANIFEST_URL}" | kubectl --kubeconfig="${HARVESTER_KUBECONFIG}" apply -f -

# 3b. Kiểm tra & chuẩn hóa CAPI CRDs (chặn lỗi 502 Harvester)
echo "🛡️ 3b. Kiểm tra & chuẩn hóa CAPI CRDs (ngăn ngừa lỗi 502 Harvester Webhook)..."
for crd in $(kubectl --kubeconfig="${HARVESTER_KUBECONFIG}" get crd -o custom-columns=NAME:.metadata.name --no-headers 2>/dev/null | grep 'cluster\.x-k8s\.io' || true); do
  STRAT=$(kubectl --kubeconfig="${HARVESTER_KUBECONFIG}" get crd "${crd}" -o jsonpath='{.spec.conversion.strategy}' 2>/dev/null || true)
  if [[ "${STRAT}" == "Webhook" ]]; then
    echo "   Vá CRD ${crd} về strategy: None..."
    kubectl --kubeconfig="${HARVESTER_KUBECONFIG}" patch crd "${crd}" --type=merge -p '{"spec":{"conversion":{"strategy":"None","webhook":null}}}' 2>/dev/null || true
  fi
done

# 4. Chờ Auto-Healer vá TLS Secret
echo "🛡️ 4. Chờ Auto-Healer cấu hình và bảo vệ chứng chỉ TLS (cattle-system)..."
for i in {1..40}; do
  STATIC_STATUS=$(kubectl --kubeconfig="${HARVESTER_KUBECONFIG}" -n cattle-system get secret tls-rancher-internal -o jsonpath='{.metadata.annotations.listener\.cattle\.io/static}' 2>/dev/null || echo "")
  if [[ "${STATIC_STATUS}" == "true" ]]; then
    echo "✅ Chứng chỉ tls-rancher-internal đã được Auto-Healer xác lập chế độ static: true an toàn!"
    break
  fi
  echo "   Đang chờ Auto-Healer hoàn tất vá chứng chỉ... (${i}/40)"
  sleep 3
done

# 4. Kiểm tra hoặc Tạo Cloud Credential 'dev' trên Rancher
echo "🔐 5. Kiểm tra Cloud Credential 'dev' trên Rancher..."
CLOUD_CRED_NAME=$(kubectl --kubeconfig="${RANCHER_KUBECONFIG}" -n cattle-global-data get secrets -l cattle.io/creator=norman -o jsonpath='{range .items[?(@.metadata.annotations.field\.cattle\.io/name=="dev")]}{.metadata.name}{end}' 2>/dev/null || echo "")

if [[ -z "${CLOUD_CRED_NAME}" ]]; then
  echo "   Chưa có Cloud Credential 'dev'. Đang tự động tạo mới..."
  
  # Chờ ServiceAccount cattle và token trong cattle-system
  CATTLE_TOKEN_SECRET=""
  for i in {1..30}; do
    CATTLE_TOKEN_SECRET=$(kubectl --kubeconfig="${HARVESTER_KUBECONFIG}" -n cattle-system get secrets -o jsonpath='{range .items[?(@.type=="kubernetes.io/service-account-token")]}{.metadata.name}{"\n"}{end}' | grep -E '^cattle-token-' | head -n 1 || echo "")
    if [[ -n "${CATTLE_TOKEN_SECRET}" ]]; then
      break
    fi
    sleep 2
  done

  # Nếu không có Secret token kiểu cũ (K8s 1.24+), tạo token trực tiếp qua kubectl
  if [[ -n "${CATTLE_TOKEN_SECRET}" ]]; then
    BEARER_TOKEN=$(kubectl --kubeconfig="${HARVESTER_KUBECONFIG}" -n cattle-system get secret "${CATTLE_TOKEN_SECRET}" -o jsonpath='{.data.token}' | base64 -d)
  else
    BEARER_TOKEN=$(kubectl --kubeconfig="${HARVESTER_KUBECONFIG}" -n cattle-system create token cattle --duration=87600h 2>/dev/null || echo "")
  fi

  HARVESTER_API_ENDPOINT="https://192.168.250.2:6443"
  KUBECONFIG_CONTENT=$(cat <<EOF
apiVersion: v1
kind: Config
clusters:
- cluster:
    insecure-skip-tls-verify: true
    server: ${HARVESTER_API_ENDPOINT}
  name: default
contexts:
- context:
    cluster: default
    user: default
  name: default
current-context: default
users:
- name: default
  user:
    token: ${BEARER_TOKEN}
EOF
)

  B64_CLUSTER_ID=$(echo -n "${CLUSTER_ID}" | base64 | tr -d '\n')
  B64_CLUSTER_TYPE=$(echo -n "imported" | base64 | tr -d '\n')
  B64_KUBECONFIG=$(echo -n "${KUBECONFIG_CONTENT}" | base64 | tr -d '\n')

  cat <<EOF | kubectl --kubeconfig="${RANCHER_KUBECONFIG}" apply -f -
apiVersion: v1
kind: Secret
metadata:
  generateName: cc-
  namespace: cattle-global-data
  annotations:
    field.cattle.io/name: dev
  labels:
    cattle.io/creator: norman
type: Opaque
data:
  harvestercredentialConfig-clusterId: ${B64_CLUSTER_ID}
  harvestercredentialConfig-clusterType: ${B64_CLUSTER_TYPE}
  harvestercredentialConfig-kubeconfigContent: ${B64_KUBECONFIG}
EOF

  sleep 2
  CLOUD_CRED_NAME=$(kubectl --kubeconfig="${RANCHER_KUBECONFIG}" -n cattle-global-data get secrets -l cattle.io/creator=norman -o jsonpath='{range .items[?(@.metadata.annotations.field\.cattle\.io/name=="dev")]}{.metadata.name}{end}' 2>/dev/null || echo "")
fi

echo "✅ Cloud Credential Secret Name: ${CLOUD_CRED_NAME}"

# 5. Tự động cập nhật file gitops/applications/02-rke2-cluster.yaml
echo "📝 6. Cập nhật ${RKE2_APP_YAML}..."
if [[ -f "${RKE2_APP_YAML}" ]]; then
  if [[ "$OSTYPE" == "darwin"* ]]; then
    sed -i '' "s/harvesterClusterId:.*/harvesterClusterId: \"${CLUSTER_ID}\"/" "${RKE2_APP_YAML}"
    sed -i '' "s/cloudCredentialSecretName:.*/cloudCredentialSecretName: \"${CLOUD_CRED_NAME}\"/" "${RKE2_APP_YAML}"
  else
    sed -i "s/harvesterClusterId:.*/harvesterClusterId: \"${CLUSTER_ID}\"/" "${RKE2_APP_YAML}"
    sed -i "s/cloudCredentialSecretName:.*/cloudCredentialSecretName: \"${CLOUD_CRED_NAME}\"/" "${RKE2_APP_YAML}"
  fi
  echo "✅ Đã cập nhật harvesterClusterId: \"${CLUSTER_ID}\" và cloudCredentialSecretName: \"${CLOUD_CRED_NAME}\""
else
  echo "⚠️ Cảnh báo: Không tìm thấy file ${RKE2_APP_YAML}"
fi

echo ""
echo "========================================================================"
echo "🎉 HOÀN TẤT IMPORT & CẤU HÌNH TỰ ĐỘNG!"
echo "========================================================================"
echo "Trạng thái trong gitops/applications/02-rke2-cluster.yaml:"
git diff "${RKE2_APP_YAML}" || true
echo ""
echo "Các bước tiếp theo:"
echo "1. Đẩy thay đổi lên Git repo (nếu có thay đổi mới):"
echo "   git add gitops/applications/02-rke2-cluster.yaml"
echo "   git commit -m 'chore: update Harvester Cluster ID and Cloud Credential'"
echo "   git push"
echo "2. Argo CD Hub sẽ tự động kích hoạt tạo 3 máy ảo cụm RKE2."
echo "3. Sau khi cụm RKE2 sẵn sàng (khoảng 5-10 phút), chạy:"
echo "   ./bootstrap/04-register-rke2-cluster.sh"
