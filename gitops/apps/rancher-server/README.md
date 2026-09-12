# Rancher Server Trên openSUSE Leap Micro 6.2 (Harvester VM)

Thư mục này chứa toàn bộ cấu hình GitOps để tự động triển khai máy ảo **Rancher Server** chạy hệ điều hành **openSUSE Leap Micro 6.2** trên Harvester HCI.

---

## 1. Thành phần cấu hình

| File | Chức năng |
| :--- | :--- |
| `00-image.yaml` | Khai báo `VirtualMachineImage` cho openSUSE Leap Micro 6.2 |
| `01-cloud-init.yaml` | Secret Cloud-Init (đã mã hóa SOPS) cài K3s, Helm v3, Cert-Manager, Rancher |
| `02-services.yaml` | NodePort Services (31443 cho HTTPS, 31022 cho SSH, 31643 cho K3s API) |
| `03-vm.yaml` | KubeVirt `VirtualMachine` (4 vCPU, 8GiB RAM, 40GiB Disk, StorageClass `lh-eea5b656-bfe6-4970-87fd-c85f3ac90655`) |
| `kustomization.yaml` | Đóng gói tài nguyên để Flux đồng bộ |
| `get-kubeconfig.sh` | Lấy file Kubeconfig của K3s về máy trạm qua SSH |
| `tail-log.sh` | Theo dõi log bootstrap Rancher trực tiếp qua SSH |

---

## 2. Thông tin đăng nhập & Truy cập

- **Web UI Rancher**: [https://rancher.192.168.250.2.sslip.io:31443](https://rancher.192.168.250.2.sslip.io:31443)
- **Tài khoản mặc định**: `admin`
- **Mật khẩu khởi tạo**: `admin@2026!!`
- **SSH máy ảo**: `ssh -p 31022 opensuse@192.168.250.2` (mật khẩu: `rancher@2026!` hoặc SSH key)
