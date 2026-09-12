# Rancher Server Trên openSUSE Leap Micro 6.2 (Harvester VM)

Thư mục này chứa toàn bộ cấu hình khai báo **Infrastructure as Code (IaC)** và **GitOps** để tự động triển khai máy ảo quản trị **Rancher Server** chạy trên nền hệ điều hành bất biến **openSUSE Leap Micro 6.2** trực tiếp trên hạ tầng **Harvester HCI v1.8.2**.

---

## 1. Thành Phần Cấu Hình

| Tập tin | Chức năng |
| :--- | :--- |
| [`00-image.yaml`](file://gitops/apps/rancher-server/00-image.yaml) | Khai báo `VirtualMachineImage` cho openSUSE Leap Micro 6.2 (qcow2 cloud image) trên Harvester. |
| [`01-cloud-init.yaml`](file://gitops/apps/rancher-server/01-cloud-init.yaml) | Secret `rancher-cloudinit` (đã mã hóa bảo mật với **SOPS + Age**). Tự động tạo user `opensuse`, cấu hình SSH key, và chạy script bootstrap cài K3s, Helm v3, Cert-Manager, Rancher Manager. |
| [`02-services.yaml`](file://gitops/apps/rancher-server/02-services.yaml) | Khai báo các NodePort Services để mở cổng ra mạng vật lý của Harvester Node (`192.168.250.2`). |
| [`03-vm.yaml`](file://gitops/apps/rancher-server/03-vm.yaml) | Khai báo máy ảo KubeVirt `VirtualMachine`: 4 vCPU, 8 GiB RAM, 40 GiB Block Disk qua Longhorn StorageClass. |
| [`harvester-import.yaml`](file://gitops/apps/rancher-server/harvester-import.yaml) | Khai báo `cattle-cluster-agent` để kết nối và đăng ký cụm Harvester HCI vào quản trị trên Rancher. |
| [`kustomization.yaml`](file://gitops/apps/rancher-server/kustomization.yaml) | Đóng gói toàn bộ tài nguyên trên cho Flux Kustomization Controller đồng bộ. |
| [`get-kubeconfig.sh`](file://gitops/apps/rancher-server/get-kubeconfig.sh) | Script tiện ích tự động lấy file Kubeconfig của cụm K3s quản lý Rancher về máy trạm Mac qua SSH. |
| [`tail-log.sh`](file://gitops/apps/rancher-server/tail-log.sh) | Script theo dõi log tiến trình bootstrap (`/var/log/rancher-bootstrap.log`) trực tiếp qua SSH. |
| [`rancher-k3s-kubeconfig.yaml`](file://gitops/apps/rancher-server/rancher-k3s-kubeconfig.yaml) | File Kubeconfig truy cập cụm K3s chạy Rancher Server từ máy trạm. |

---

## 2. Thông Số Phần Cứng & Hạ Tầng Máy Ảo

- **Tên máy ảo**: `rancher-server` (Namespace: `default`)
- **Hệ điều hành**: openSUSE Leap Micro 6.2 (x86_64, Linux Kernel 6.12+)
- **Tài nguyên**:
  - **CPU**: 4 vCPU (Cores: 4, Sockets: 1, Threads: 1)
  - **RAM**: 8 GiB (Reserved Memory: 512 MiB)
  - **Đĩa cứng**: 40 GiB Block Volume (PVC `rancher-server-disk`)
  - **StorageClass**: `lh-eea5b656-bfe6-4970-87fd-c85f3ac90655` (Longhorn replicated storage)
- **Mạng**: KubeVirt Masquerade Network kết nối qua Service NodePort ra mạng LAN vật lý.
- **Tính năng cao cấp**: Hỗ trợ ACPI, Live Migration (`LiveMigrateIfPossible`), RunStrategy `RerunOnFailure`.

---

## 3. Bản Đồ Cổng & Điểm Truy Cập Dịch Vụ

Các cổng được expose ra IP vật lý của máy chủ Harvester (`192.168.250.2`):

| Cổng Ngoài | Giao Thức | Dịch Vụ Đích Bên Trong VM | Mô Tả & Điểm Truy Cập |
| :---: | :---: | :---: | :--- |
| **`31443`** | HTTPS | Rancher Web UI / API (`443`) | **Web UI Rancher**: [https://rancher.192.168.250.2.sslip.io:31443](https://rancher.192.168.250.2.sslip.io:31443) |
| **`31022`** | SSH | OpenSSH Server (`22`) | **SSH máy ảo**: `ssh -p 31022 opensuse@192.168.250.2` |
| **`31643`** | HTTPS | K3s Kubernetes API Server (`6443`) | **K3s API**: Dùng cho file Kubeconfig điều khiển K3s từ xa |
| **`31080`** | HTTP | HTTP Redirection (`80`) | Chuyển hướng tự động sang HTTPS |

---

## 4. Thông Tin Đăng Nhập Mặc Định

- **Rancher Web UI**:
  - **URL**: [https://rancher.192.168.250.2.sslip.io:31443](https://rancher.192.168.250.2.sslip.io:31443)
  - **Tài khoản**: `admin`
  - **Mật khẩu**: `admin@2026!!`
- **SSH OS máy ảo**:
  - **Lệnh**: `ssh -p 31022 opensuse@192.168.250.2`
  - **Mật khẩu**: `rancher@2026!` (hoặc xác thực bằng SSH key cá nhân đã nạp trong SOPS)
  - **Sudo**: Toàn quyền `sudo` không cần mật khẩu (`NOPASSWD: ALL`).

---

## 5. Tích Hợp Harvester HCI & Cơ Chế GitOps Remote Sync

Rancher Server sau khi khởi tạo đóng vai trò là **Management Plane** để provision các cụm RKE2:

1. **Đăng ký Harvester HCI vào Rancher**:
   - Harvester được import vào Rancher thành cụm quản lý với mã Cluster ID (ví dụ: `c-tphkg`).
   - Rancher sinh ra Cloud Credential (ví dụ: `cc-8dghb`) chứa token kết nối với Harvester HCI API.
2. **Kênh điều khiển GitOps từ Harvester vào Rancher**:
   - Secret `rancher-kubeconfig` trong namespace `flux-system` trên Harvester chứa thông tin kết nối tới K3s API (`https://192.168.250.2:31643`).
   - FluxCD Kustomization [`sync-rke2-cluster.yaml`](file://gitops/clusters/harvester/sync-rke2-cluster.yaml) sử dụng Secret này để đồng bộ các khai báo cụm RKE2 downstream trực tiếp vào API của Rancher Server.
   - Nhờ tính năng **Flux PostBuild Variable Substitution**, các ID động (`${HARVESTER_CLUSTER_ID}`, `${HARVESTER_CLOUD_CREDENTIAL_SECRET_NAME}`) được inject tự động từ [`cluster-vars.yaml`](file://gitops/clusters/harvester/cluster-vars.yaml) mà không bị hardcode trong mã nguồn ứng dụng.

---

## 6. Các Lệnh Vận Hành & Khắc Phục Sự Cố Thường Gặp

### Lấy Kubeconfig K3s về máy Mac
```bash
./gitops/apps/rancher-server/get-kubeconfig.sh
```

### Xem log bootstrap Rancher Server thời gian thực
```bash
./gitops/apps/rancher-server/tail-log.sh
```

### Kiểm tra Pods hệ thống Rancher
```bash
kubectl --kubeconfig=gitops/apps/rancher-server/rancher-k3s-kubeconfig.yaml -n cattle-system get pods -o wide
```

### Kiểm tra trạng thái máy ảo trên Harvester
```bash
kubectl --kubeconfig=kubeconfig.yaml get vm,vmi rancher-server -n default
```
