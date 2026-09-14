# Rancher Server Trên openSUSE Leap Micro 6.2 (Harvester VM)

Thư mục này chứa toàn bộ cấu hình khai báo **Infrastructure as Code (IaC)** và **GitOps** để tự động triển khai máy ảo quản trị **Rancher Server** chạy trên nền hệ điều hành bất biến **openSUSE Leap Micro 6.2** trực tiếp trên hạ tầng **Harvester HCI v1.8.2**.

---

## 1. Thành Phần Cấu Hình

| Tập tin | Chức năng |
| :--- | :--- |
| [`00-image.yaml`](file:///Users/timi/lab/lab-harvester/gitops/infrastructure/rancher-server/00-image.yaml) | Khai báo `VirtualMachineImage` cho openSUSE Leap Micro 6.2 (qcow2 cloud image) trên Harvester. |
| [`01-cloud-init.yaml`](file:///Users/timi/lab/lab-harvester/gitops/infrastructure/rancher-server/01-cloud-init.yaml) | Secret `rancher-cloudinit` (mã hóa **SOPS + Age**). Cấu hình static IP `192.168.250.30`, user `opensuse`, SSH key, bootstrap K3s, Helm v3, Cert-Manager, Rancher Manager. |
| [`03-vm.yaml`](file:///Users/timi/lab/lab-harvester/gitops/infrastructure/rancher-server/03-vm.yaml) | Khai báo máy ảo KubeVirt `VirtualMachine`: 2 vCPU, 6 GiB RAM, 32 GiB Block Disk, kết nối Bridge VLAN `default/vlan1`. |
| [`04-harvester-ui-extension.yaml`](file:///Users/timi/lab/lab-harvester/gitops/infrastructure/rancher-server/04-harvester-ui-extension.yaml) | Khai báo các `ClusterRepo` và `UIPlugin` để tự động kích hoạt Harvester UI Extension trong Rancher. |
| [`harvester-import.yaml`](file:///Users/timi/lab/lab-harvester/gitops/infrastructure/rancher-server/harvester-import.yaml) | Khai báo `cattle-cluster-agent` để kết nối và đăng ký cụm Harvester HCI vào quản trị trên Rancher. |
| [`kustomization.yaml`](file:///Users/timi/lab/lab-harvester/gitops/infrastructure/rancher-server/kustomization.yaml) | Đóng gói toàn bộ tài nguyên trên cho Argo CD đồng bộ lên Harvester. |
| [`get-kubeconfig.sh`](file:///Users/timi/lab/lab-harvester/gitops/infrastructure/rancher-server/get-kubeconfig.sh) | Script tiện ích tự động lấy file Kubeconfig của cụm K3s quản lý Rancher về máy trạm Mac qua SSH port 22. |
| [`tail-log.sh`](file:///Users/timi/lab/lab-harvester/gitops/infrastructure/rancher-server/tail-log.sh) | Script theo dõi log tiến trình bootstrap (`/var/log/rancher-bootstrap.log`) trực tiếp qua SSH port 22. |
| [`rancher-k3s-kubeconfig.yaml`](file:///Users/timi/lab/lab-harvester/gitops/infrastructure/rancher-server/rancher-k3s-kubeconfig.yaml) | File Kubeconfig truy cập cụm K3s chạy Rancher Server từ máy trạm. |

---

## 2. Thông Số Phần Cứng & Hạ Tầng Máy Ảo

- **Tên máy ảo**: `rancher-server` (Namespace: `default`)
- **Hệ điều hành**: openSUSE Leap Micro 6.2 (x86_64, Linux Kernel 6.12+)
- **Tài nguyên**:
  - **CPU**: 2 vCPU (Cores: 2, Sockets: 1, Threads: 1)
  - **RAM**: 6 GiB (Reserved Memory: 512 MiB)
  - **Đĩa cứng**: 32 GiB Block Volume (PVC `rancher-server-disk`)
  - **StorageClass**: `lh-eea5b656-bfe6-4970-87fd-c85f3ac90655` (Longhorn replicated storage)
- **Mạng**: Bridge Multus Network `default/vlan1` nhận IP tĩnh cố định `192.168.250.30/24`.
- **Tính năng cao cấp**: Hỗ trợ ACPI, Live Migration (`LiveMigrateIfPossible`), RunStrategy `Always`.

---

## 3. Bản Đồ Cổng & Điểm Truy Cập Dịch Vụ

Máy ảo sử dụng IP tĩnh chuyên dụng `192.168.250.30` với toàn bộ các cổng chuẩn Enterprise:

| Cổng | Giao Thức | Dịch Vụ | Mô Tả & Điểm Truy Cập |
| :---: | :---: | :--- | :--- |
| **`443`** | HTTPS | Rancher Web UI / API | **Web UI Rancher**: [https://rancher.192.168.250.30.sslip.io](https://rancher.192.168.250.30.sslip.io) |
| **`6443`** | HTTPS | K3s Kubernetes API Server | **K3s API**: `https://192.168.250.30:6443` |
| **`22`** | SSH | OpenSSH Server | **SSH máy ảo**: `ssh opensuse@192.168.250.30` |
| **`80`** | HTTP | HTTP Redirection | Chuyển hướng tự động sang HTTPS |

---

## 4. Thông Tin Đăng Nhập Mặc Định

- **Rancher Web UI**:
  - **URL**: [https://rancher.192.168.250.30.sslip.io](https://rancher.192.168.250.30.sslip.io)
  - **Tài khoản**: `admin`
  - **Mật khẩu**: `admin@2026!!`
- **SSH OS máy ảo**:
  - **Lệnh**: `ssh opensuse@192.168.250.30`
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
