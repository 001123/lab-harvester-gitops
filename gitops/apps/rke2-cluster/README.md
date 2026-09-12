# RKE2 Cluster on Harvester via Rancher Node Driver

Thư mục này chứa toàn bộ cấu hình khai báo dạng Infrastructure as Code (IaC) để Rancher tự động provision cụm **RKE2** (1 Control Plane + 1 Worker) chạy trên máy ảo **Harvester HCI**.

---

## 1. Thành phần cấu hình

| Tập tin | Chức năng |
| :--- | :--- |
| [`00-image.yaml`](file://00-image.yaml) | Khai báo `VirtualMachineImage` cho **openSUSE Leap Micro 6.2** (qcow2) trên Harvester HCI. |
| [`01-machine-configs.yaml`](file://01-machine-configs.yaml) | Khai báo 2 template `HarvesterConfig` (`rke2-cp-config`, `rke2-wk-config`): 2 vCPU, 4GB RAM, 40GB Disk, image `opensuse-leap-micro-62`, user `opensuse`, network `vlan1`, kèm `userData` kích hoạt `qemu-guest-agent` và host resolution. |
| [`02-cluster.yaml`](file://02-cluster.yaml) | Khai báo cụm RKE2 `rke2-lab` (namespace `fleet-default`, k8s `v1.36.4+rke2r1`) sử dụng Cloud Credential `dev` (`cc-tb5bm`). |
| [`kustomization.yaml`](file://kustomization.yaml) | Đóng gói tài nguyên để apply đồng thời lên Rancher. |
| [`apply.sh`](file://apply.sh) | Script kiểm tra image trên Harvester và áp dụng cấu hình lên Rancher Server. |
| [`rke2-kubeconfig.yaml`](file://rke2-kubeconfig.yaml) | Kubeconfig truy cập cụm RKE2 thông qua Rancher Proxy (`rancher.192.168.250.2.sslip.io:31443`). |
| [`rke2-direct-kubeconfig.yaml`](file://rke2-direct-kubeconfig.yaml) | Kubeconfig truy cập trực tiếp Master Node. |

---

## 2. Thông tin hệ điều hành & Cụm RKE2 hiện tại

- **OS**: openSUSE Leap Micro 6.2 (Immutable, Self-healing, Minimal Footprint)
- **Tài khoản SSH mặc định**: `sles` (mặc định của appliance) hoặc `opensuse` / `root`
- **Tích hợp Harvester**: Tích hợp sẵn `qemu-guest-agent` trong bản cloud qcow2 chính thức.
- **Tên cụm**: `rke2-lab`
- **Cluster ID trên Rancher**: `c-m-hpgc7zqw`
- **Kubernetes Version**: `v1.36.4+rke2r1`
- **Các Node**:
  - **Control Plane + ETCD**: `rke2-lab-cp-fmdmk-882bd` — IP `192.168.250.168`
  - **Worker**: `rke2-lab-wk-rndgx-4hqdv` — IP `192.168.250.171`

---


## 3. Lệnh kiểm tra cụm từ máy Mac

### Cách 1: Sử dụng Kubeconfig qua Rancher Server Proxy
```bash
kubectl --kubeconfig=rancher-server/rke2-cluster/rke2-kubeconfig.yaml --insecure-skip-tls-verify get nodes -o wide
kubectl --kubeconfig=rancher-server/rke2-cluster/rke2-kubeconfig.yaml --insecure-skip-tls-verify get pods -A
```

### Cách 2: Sử dụng Kubeconfig trực tiếp tới node Control Plane
```bash
kubectl --kubeconfig=rancher-server/rke2-cluster/rke2-direct-kubeconfig.yaml get nodes -o wide
kubectl --kubeconfig=rancher-server/rke2-cluster/rke2-direct-kubeconfig.yaml get pods -A
```
