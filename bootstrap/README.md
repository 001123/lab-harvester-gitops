# Hướng Dẫn Bootstrap GitOps Cho Harvester Bằng Argo CD Hub

Thư mục này chứa các kịch bản bootstrap tự động để đưa cụm **Harvester HCI** vào quản lý bởi **Argo CD Hub (Mô hình Centralized Hub-and-Spoke)**, tích hợp sẵn **KSOPS (Kustomize SOPS)** để giải mã Secret tự động.

---

## 1. Yêu cầu trước khi chạy
- Máy trạm đã cài đặt: `kubectl`, `helm`, `sops`, `age`.
- File private key của Age nằm tại `~/.config/sops/age/keys.txt`.
- Đặt file `kubeconfig.yaml` của cụm Harvester ở thư mục gốc của repository.

---

## 2. Quy Trình Bootstrap 4 Bước

### Bước 1: Khởi tạo Secret SOPS Age
```bash
./bootstrap/01-setup-sops-age.sh
```
Script sẽ tạo namespace `argocd` và nạp secret `sops-age` chứa Age private key lên Harvester.

### Bước 2: Cài đặt Argo CD Hub & KSOPS
```bash
./bootstrap/02-install-argocd.sh
```
Script sẽ cài đặt Helm Chart `argo-cd` v10.8.4:
- Mở NodePort Web UI tại cổng `30080`.
- Cấu hình plugin KSOPS ConfigManagementPlugin (CMP) trong `argocd-repo-server`.
- Mount secret `sops-age` vào repo-server.
- Tự động áp dụng Root Application (`gitops/root.yaml`).

Sau khi cài đặt, bạn có thể truy cập Web UI tại:
- **URL**: `http://192.168.250.2:30080`
- **Username**: `admin`
- **Password**: In ra ở cuối script (lấy từ secret `argocd-initial-admin-secret`).

### Bước 3: Đăng ký Rancher Server Cluster
Sau khi máy ảo `rancher-server` khởi động xong và nhận IP (mất khoảng 2-3 phút), chạy:
```bash
./bootstrap/03-register-rancher-cluster.sh
```
Script sẽ lấy file kubeconfig của Rancher VM và đăng ký thành remote cluster `rancher-server` trong Argo CD Hub. Ngay sau đó, Argo CD sẽ tự động triển khai Application `rke2-cluster` để Rancher bắt đầu provisioning cụm downstream RKE2.

### Bước 4: Đăng ký Cụm Downstream RKE2
Sau khi cụm downstream `rke2-lab` được Rancher provisioning xong (khoảng 5-10 phút):
```bash
./bootstrap/04-register-rke2-cluster.sh
```
Script sẽ lấy kubeconfig của cụm RKE2 và đăng ký thành remote cluster `rke2-cluster` trong Argo CD Hub. Toàn bộ các công cụ nền tảng (`platform/cert-manager`) và ứng dụng (`workloads/`) sẽ được Argo CD tự động đồng bộ sang cụm RKE2.
