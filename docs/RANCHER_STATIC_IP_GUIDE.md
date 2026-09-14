# Hướng Dẫn Chuẩn Hóa IP Tĩnh 192.168.250.30 & Cổng Mạng Chuẩn Cho Rancher Server

Tài liệu này cung cấp hướng dẫn toàn diện về kiến trúc mạng, phương pháp cấu hình máy ảo, cơ chế gán IP tĩnh qua **Cloud-Init / NetworkManager**, quy trình bảo mật với **SOPS/Age**, và sổ tay vận hành thực tế khi triển khai **Rancher Management Server** trên cụm ảo hóa **Harvester HCI v1.8.2** (Hệ điều hành **openSUSE Leap Micro 6.2**).

---

## 1. Tổng Quan & Bối Cảnh Chuyển Đổi

### 1.1. Hạn chế của mô hình cũ (Harvester Masquerade & NodePort)
Ban đầu, máy ảo `rancher-server` được cấu hình sử dụng card mạng mặc định của KubeVirt/Harvester:
* **Card mạng**: Chế độ `pod: {}` kết hợp `masquerade`. Máy ảo nằm sau lớp mạng NAT nội bộ của Harvester.
* **Địa chỉ IP**: Không có IP riêng trên mạng vật lý, phải mượn IP của node Harvester (`192.168.250.2`).
* **Truy cập dịch vụ**: Bắt buộc phải thông qua các cổng NodePort phi chuẩn:
  - Web UI: Cổng `31443` (`https://192.168.250.2:31443`)
  - K3s API Server: Cổng `31643` (`https://192.168.250.2:31643`)
  - SSH Quản trị: Cổng `31022` (`ssh opensuse@192.168.250.2 -p 31022`)
* **Nhược điểm**:
  - Dễ gây xung đột cổng khi mở rộng hệ thống.
  - Các cụm Kubernetes con (RKE2 Downstream Cluster) và `cattle-cluster-agent` phải kết nối vòng qua NodePort của host Harvester, gây nghẽn và chập chờn khi host tải cao.
  - Cấu hình tên miền sslip.io và chứng chỉ TLS bị phức tạp do dính kèm số cổng phi chuẩn.

### 1.2. Mục tiêu của mô hình chuẩn hóa (Enterprise Dedicated Static IP)
Chuyển đổi toàn diện sang kiến trúc mạng phẳng chuyên nghiệp:
* **IP tĩnh chuyên dụng**: `192.168.250.30` độc lập hoàn toàn trên dải mạng vật lý **VLAN 1** (`192.168.250.0/24`).
* **Sử dụng 100% cổng chuẩn**:
  - Web UI: Cổng **`443`** (`https://rancher.192.168.250.30.sslip.io`)
  - K3s API Server: Cổng **`6443`** (`https://192.168.250.30:6443`)
  - SSH Quản trị: Cổng **`22`** (`ssh opensuse@192.168.250.30`)
* **Cơ chế mạng**: Cầu nối mạng vật lý trực tiếp (**Multus CNI Bridge** nối vào `default/vlan1`).

---

## 2. Bảng So Sánh Chi Tiết: Trước & Sau Khi Chuẩn Hóa

| Tiêu Chí | Mô Hình Cũ (Masquerade / NodePort) | Mô Hình Chuẩn Hóa (Dedicated Static IP) |
| :--- | :--- | :--- |
| **Giao tiếp mạng (Network Interface)** | `pod: {}` (NAT Masquerade qua Pod Harvester) | `multus: default/vlan1` (L2 Bridge trực tiếp VLAN 1) |
| **Địa chỉ IP máy chủ** | Dùng chung IP của Harvester `192.168.250.2` | **IP tĩnh riêng biệt `192.168.250.30`** |
| **URL Truy cập Web UI** | `https://192.168.250.2:31443` | **`https://rancher.192.168.250.30.sslip.io` (Cổng 443 chuẩn)** |
| **Kubernetes K3s API** | `https://192.168.250.2:31643` | **`https://192.168.250.30:6443` (Cổng 6443 chuẩn)** |
| **Truy cập SSH Quản trị** | `ssh -p 31022 opensuse@192.168.250.2` | **`ssh opensuse@192.168.250.30` (Cổng 22 chuẩn)** |
| **Chứng chỉ TLS / SAN** | Khó xin cert tự động do dính cổng NodePort | Hỗ trợ đầy đủ SAN IP + Domain qua `sslip.io` |
| **Giao tiếp Downstream Agent** | Kết nối gián tiếp qua NodePort proxy | Kết nối trực tiếp qua L2/L3 switch vật lý, độ trễ cực thấp |

---

## 3. Kiến Trúc Mạng Tổng Thể (Architecture Diagram)

```mermaid
graph TD
    Admin["Quản Trị Viên / Trình Duyệt Web"]
    Switch["Switch Mạng Vật Lý Homelab\n(VLAN 1: 192.168.250.0/24 | Gateway: 192.168.250.1)"]

    subgraph HarvesterCluster["Cụm Harvester HCI (Host: 192.168.250.2)"]
        VLANBridge["Multus Bridge Network\n('default/vlan1')"]
        
        subgraph RancherVM["Máy Ảo: rancher-server (openSUSE Leap Micro 6.2)"]
            NIC0["Card mạng: eth0 (Bridge mode)\nIP tĩnh: 192.168.250.30/24"]
            K3s["K3s Server (v1.36.4+k3s1)\nLắng nghe: :6443\nTLS SAN: rancher.192.168.250.30.sslip.io"]
            CertMgr["Jetstack cert-manager"]
            RancherApp["Rancher Manager Server (v2.10+)\nLắng nghe Ingress: :443"]
            SSHService["OpenSSH Daemon\nLắng nghe: :22"]
        end
    end

    subgraph DownstreamCluster["Cụm RKE2 Downstream (rke2-lab)"]
        CPNode["Control Plane (192.168.250.100)"]
        WKNode1["Worker 1 (192.168.250.200)"]
        WKNode2["Worker 2 (192.168.250.232)"]
        ClusterAgent["cattle-cluster-agent\n(Kết nối quản trị tới Rancher)"]
    end

    %% Routing
    Admin -->|1. HTTPS :443 (Web UI)| Switch
    Admin -->|2. Kubeconfig :6443 (K3s API)| Switch
    Admin -->|3. SSH :22| Switch
    Switch --> VLANBridge
    VLANBridge --> NIC0
    NIC0 --> RancherApp
    NIC0 --> K3s
    NIC0 --> SSHService

    %% Downstream connection
    ClusterAgent -->|4. Sync trạng thái qua https://rancher.192.168.250.30.sslip.io| Switch
    K3s --- CertMgr --- RancherApp
```

---

## 4. Cấu Hình Kỹ Thuật Chi Tiết (Technical Implementation)

Toàn bộ cấu hình được định nghĩa bằng mã nguồn GitOps tại thư mục [gitops/infrastructure/rancher-server/](file:///Users/timi/lab/lab-harvester/gitops/infrastructure/rancher-server/).

### 4.1. Cấu hình Card Mạng Máy Ảo trong Harvester VM (`03-vm.yaml`)
Để máy ảo nhận IP trực tiếp từ VLAN 1 thay vì qua NAT Masquerade, cấu hình `spec.template.spec` được thiết lập:

```yaml
spec:
  template:
    spec:
      domain:
        devices:
          autoattachPodInterface: false   # Tắt card mạng Pod NAT mặc định
          interfaces:
          - bridge: {}                    # Chế độ Bridge trực tiếp
            model: virtio
            name: nic-0
      networks:
      - multus:
          networkName: default/vlan1      # Gắn trực tiếp vào hạ tầng VLAN 1 của Harvester
        name: nic-0
```

---

### 4.2. Cơ Chế Gán IP Tĩnh Kép: Netplan v2 & NetworkManager

> [!IMPORTANT]
> **Đặc thù của openSUSE Leap Micro 6.2:**  
> Hệ điều hành openSUSE Leap Micro sử dụng **NetworkManager** làm trình quản lý mạng mặc định (chứ không phải `systemd-networkd` hay `wicked`).  
> Nếu chỉ khai báo `networkdata` chuẩn cloud-init mà không cấu hình profile cho NetworkManager, hệ thống có thể bị treo hoặc rơi về DHCP. Vì vậy, ta áp dụng cơ chế bảo đảm kép (Dual-layer Configuration).

Trong file bí mật [01-cloud-init.yaml](file:///Users/timi/lab/lab-harvester/gitops/infrastructure/rancher-server/01-cloud-init.yaml) (được giải mã tự động bằng SOPS):

#### Tầng 1: Cloud-Init `networkdata` (Netplan / V2 Format)
```yaml
stringData:
  networkdata: |
    version: 2
    ethernets:
      eth0:
        match:
          name: "e*"
        dhcp4: false
        addresses:
          - 192.168.250.30/24
        gateway4: 192.168.250.1
        nameservers:
          addresses:
            - 192.168.250.1
            - 1.1.1.1
```

#### Tầng 2: Ghi Trực Tiếp Profile NetworkManager trong `userdata`
Đảm bảo NetworkManager kích hoạt cấu hình tĩnh ngay từ giây đầu tiên của quá trình khởi động:
```yaml
write_files:
  - path: /etc/NetworkManager/system-connections/static-eth.nmconnection
    permissions: '0600'
    content: |
      [connection]
      id=static-eth
      type=ethernet
      interface-name=eth0
      permissions=

      [ethernet]

      [ipv4]
      address1=192.168.250.30/24,192.168.250.1
      dns=192.168.250.1;1.1.1.1;
      method=manual

      [ipv6]
      method=ignore
```

---

### 4.3. Tự Động Bootstrap K3s & Rancher với TLS SAN (`userdata`)

Script khởi tạo tự động `/opt/bootstrap-rancher.sh` được cloud-init sinh ra và chạy ngầm khi VM boot lần đầu:

1. **Khởi tạo K3s Server với SAN chuẩn:**
   ```bash
   curl -sfL https://get.k3s.io | \
     INSTALL_K3S_VERSION="v1.36.4+k3s1" \
     INSTALL_K3S_BIN_DIR="/usr/local/bin" \
     INSTALL_K3S_EXEC="server --tls-san rancher.192.168.250.30.sslip.io --tls-san 192.168.250.30 --write-kubeconfig-mode 644" \
     sh -
   ```
   *Cờ `--tls-san` giúp chứng chỉ TLS nội bộ của API Server `6443` chấp nhận cả tên miền `sslip.io` lẫn IP trực tiếp `192.168.250.30`.*

2. **Cài đặt Cert-Manager & Rancher Manager qua Helm:**
   ```bash
   # Cài cert-manager
   helm upgrade --install cert-manager jetstack/cert-manager \
     --namespace cert-manager \
     --set crds.enabled=true \
     --wait

   # Cài Rancher Server với hostname cố định theo IP tĩnh
   helm upgrade --install rancher rancher-stable/rancher \
     --namespace cattle-system \
     --set hostname=rancher.192.168.250.30.sslip.io \
     --set bootstrapPassword=admin \
     --set replicas=1 \
     --wait
   ```

---

## 5. Quy Trình Vận Hành & Lệnh Kiểm Tra Thực Tế

Sau khi triển khai, quản trị viên có thể kiểm tra trạng thái hoạt động của Rancher Server từ máy tính quản trị.

### 5.1. Kiểm tra kết nối mạng & Cổng dịch vụ
```bash
# 1. Ping trực tiếp vào IP tĩnh
ping -c 3 192.168.250.30

# 2. Kiểm tra các cổng chuẩn 22, 443, 6443
nc -zv -w 2 192.168.250.30 22    # OpenSSH
nc -zv -w 2 192.168.250.30 443   # Rancher Web UI
nc -zv -w 2 192.168.250.30 6443  # K3s Kubernetes API
```

### 5.2. Kiểm tra truy cập Web UI Rancher (HTTPS cổng 443)
```bash
curl -k -Iv https://rancher.192.168.250.30.sslip.io/
```
*Kỳ vọng phản hồi:*
```http
* Connected to rancher.192.168.250.30.sslip.io (192.168.250.30) port 443
* ALPN: server accepted h2
< HTTP/2 200 
< content-type: text/html; charset=utf-8
```

### 5.3. Kiểm tra cụm K3s thông qua Kubeconfig
Kho lưu trữ đã chuẩn bị sẵn file kubeconfig trực tiếp tại [gitops/infrastructure/rancher-server/rancher-k3s-kubeconfig.yaml](file:///Users/timi/lab/lab-harvester/gitops/infrastructure/rancher-server/rancher-k3s-kubeconfig.yaml):
```bash
kubectl --kubeconfig gitops/infrastructure/rancher-server/rancher-k3s-kubeconfig.yaml get nodes -o wide
```
*Kết quả:*
```text
NAME             STATUS   ROLES                  AGE    VERSION        INTERNAL-IP
rancher-server   Ready    control-plane,master   150m   v1.36.4+k3s1   192.168.250.30
```

### 5.4. Truy cập SSH vào VM bằng cổng 22
```bash
# Sử dụng mật khẩu hoặc SSH key đã cấu hình:
ssh opensuse@192.168.250.30
```

### 5.5. Theo dõi tiến trình cài đặt ban đầu (Bootstrap Logs)
Nếu cần theo dõi tiến trình cài đặt K3s và Rancher khi VM mới khởi tạo:
```bash
ssh opensuse@192.168.250.30 "sudo tail -f /var/log/rancher-bootstrap.log"
```

---

## 6. Sổ Tay Xử Lý Sự Cố (Troubleshooting Runbook)

### Sự cố 1: Máy ảo không nhận IP tĩnh 192.168.250.30
* **Hiện tượng**: Ping `192.168.250.30` báo `Host Unreachable`, máy ảo tự động nhận IP DHCP ngẫu nhiên.
* **Nguyên nhân**:
  1. Profile NetworkManager chưa được áp dụng hoặc phân quyền file sai (`chmod 600`).
  2. Cấu hình Multus Network `default/vlan1` trên Harvester chưa được gắn đúng VLAN ID trên Switch vật lý.
* **Cách khắc phục**:
  1. Mở Web VNC Console của VM `rancher-server` trong giao diện Harvester UI.
  2. Đăng nhập tài khoản `opensuse` (hoặc `root`).
  3. Kiểm tra trạng thái NetworkManager:
     ```bash
     sudo nmcli connection show
     sudo nmcli device status
     ```
  4. Nếu kết nối `static-eth` chưa kích hoạt, nạp lại cấu hình:
     ```bash
     sudo nmcli connection reload
     sudo nmcli connection up static-eth
     ```

### Sự cố 2: Lỗi TLS khi truy cập `https://rancher.192.168.250.30.sslip.io`
* **Hiện tượng**: Trình duyệt báo `ERR_SSL_PROTOCOL_ERROR` hoặc kết nối bị từ chối ở cổng 443.
* **Nguyên nhân**: Pod `rancher` trong namespace `cattle-system` chưa khởi động xong hoặc `cert-manager` chưa cấp phát Secret TLS `tls-rancher-ingress`.
* **Cách khắc phục**:
  1. Kiểm tra trạng thái các Pod trên K3s:
     ```bash
     kubectl --kubeconfig gitops/infrastructure/rancher-server/rancher-k3s-kubeconfig.yaml -n cattle-system get pods
     ```
  2. Kiểm tra chứng chỉ của Rancher:
     ```bash
     kubectl --kubeconfig gitops/infrastructure/rancher-server/rancher-k3s-kubeconfig.yaml -n cattle-system get certificate,secret
     ```

### Sự cố 3: Cụm con RKE2 Downstream báo "Waiting for API to become available"
* **Hiện tượng**: Khi provisioning cụm RKE2 qua Rancher, các node downstream không kết nối được về Rancher.
* **Nguyên nhân**: Cụm RKE2 không phân giải được tên miền `rancher.192.168.250.30.sslip.io` (do DNS upstream chặn bản ghi DNS Rebinding của `sslip.io`).
* **Cách khắc phục**:
  - Đảm bảo DNS Gateway (`192.168.250.1` hoặc Router) cho phép phân giải các tên miền `*.sslip.io`.
  - Hoặc trong cấu hình RKE2 `machine-configs`, bổ sung mapping `/etc/hosts`:
    ```text
    192.168.250.30 rancher.192.168.250.30.sslip.io
    ```

---

## 7. Tổng Kết

Việc chuẩn hóa **Rancher Management Server** sang **IP tĩnh `192.168.250.30`** và các **cổng tiêu chuẩn (443 / 6443 / 22)** mang lại các lợi ích vượt trội:
1. **Đơn giản hóa hạ tầng**: Loại bỏ hoàn toàn sự phụ thuộc vào các cổng NodePort `31443/31643/31022` và tầng proxy Harvester.
2. **Tăng tính ổn định**: Cụm Kubernetes downstream và các agent quản trị giao tiếp trực tiếp theo chuẩn doanh nghiệp.
3. **Quản trị GitOps 100%**: Mọi thông số phần cứng VM, card mạng Multus, IP tĩnh và bootstrap script đều được lưu trữ an toàn trong Git, sẵn sàng tái tạo tự động bất cứ lúc nào.
