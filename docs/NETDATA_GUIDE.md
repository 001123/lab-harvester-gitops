# Hướng Dẫn Toàn Diện Về Netdata (Kiến Trúc Parent-Child & Bypass Cloud Trên RKE2)

Tài liệu này cung cấp cẩm nang kỹ thuật chi tiết về hệ thống giám sát thời gian thực **Netdata v2.11.0** (Helm chart v3.7.173) trên cụm Kubernetes RKE2 Downstream, mô hình triển khai **100% Cục bộ (Parent - Child Streaming)**, giải pháp **Traefik Middleware Bypass Cloud Sign-in**, ma trận so sánh thực chiến với **Prometheus + Grafana**, và 3 kịch bản xử lý sự cố thực tế (Troubleshooting Runbooks).

---

## 1. Tổng Quan & Định Vị Vai Trò Của Netdata Trong Homelab

Trong cụm Homelab RKE2 đã có sẵn stack **Prometheus & Grafana** (`kube-prometheus-stack`), tại sao chúng ta vẫn cần thêm **Netdata**?

* **Prometheus & Grafana (Chiến lược dài hạn - Macro Observability)**:
  * Thu thập dữ liệu định kỳ mỗi **15 đến 30 giây**.
  * Chuyên sâu về **lưu trữ lịch sử dài hạn (7 - 30 ngày)**, phân tích xu hướng tăng trưởng dung lượng, vẽ biểu đồ tổng hợp kinh doanh bằng PromQL, và gửi cảnh báo qua Alertmanager khi dịch vụ sập.
  * **Hạn chế**: Khi hệ thống bị nghẽn CPU hoặc giật lag đột ngột trong 1-2 giây (micro-spikes), Prometheus thường bỏ lỡ mẫu dữ liệu do chu kỳ quét quá thưa.

* **Netdata (Phản ứng tức thì - Micro Troubleshooting)**:
  * Thu thập và cập nhật chỉ số với tần suất **mỗi giây một lần (per-second resolution)** với độ trễ gần như bằng 0.
  * Tự động phát hiện hàng ngàn chỉ số của nhân hệ điều hành Linux (cgroups, RAM RSS/Cache, Disk I/O wait time, Network packet drops, Socket backlog, TCP retries) mà không cần cấu hình trước.
  * **Định vị**: Netdata đóng vai trò như **ống nhòm hiển vi** để kỹ sư DevOps/SRE bật lên soi trực tiếp khi có sự cố phát sinh tại thời gian thực (Live Debugging).

---

## 2. Kiến Trúc Triển Khai End-to-End Trên Cụm RKE2

Hệ thống được thiết kế theo mô hình **Parent - Child Streaming** kết hợp định tuyến an toàn qua **Traefik Ingress**:

```mermaid
graph TD
    subgraph "Thiết Bị Người Dùng (LAN 192.168.250.0/24)"
        Browser["Trình duyệt Web (Mac/Windows/Mobile)\nĐã cài homelab-root-ca.crt"]
    end

    subgraph "Lớp Mạng Ingress VIP (192.168.250.99)"
        Traefik["Traefik Ingress Controller (Port 80/443)"]
        MW_HTTPS["Middleware: redirect-https\n(Ép HTTP sang HTTPS 443)"]
        MW_V3["Middleware: netdata-redirect-v3\n(Bắt Regex '^https?://[^/]+/?$' -> Chuyển sang '/v3/')"]
        CertSecret["Secret: netdata-tls-cert\n(Cấp tự động bởi homelab-ca-issuer)"]
    end

    subgraph "Namespace: netdata (Cụm K8s RKE2 Downstream)"
        IngressNetdata["Ingress: netdata\n(netdata.192.168.250.99.sslip.io)"]
        SvcParent["Service: netdata (ClusterIP: 19999)"]

        subgraph "Tập Trung Lưu Trữ & Hiển Thị (Parent Stateful/Deployment)"
            PodParent["Pod: netdata-parent\n- Web Server nhúng (Port 19999)\n- Engine: dbengine multi-tier"]
            PVC_DB[("PVC: netdata-parent-database (5Gi)\nStorageClass: local-path")]
            PVC_Alarms[("PVC: netdata-parent-alarms (1Gi)\nStorageClass: local-path")]
            PodParent --- PVC_DB
            PodParent --- PVC_Alarms
        end

        subgraph "Thu Thập Trạng Thái K8s (Stateful Helper)"
            PodK8sState["Pod: netdata-k8s-state\n(K8s Resource State Collector)"]
            PVC_State[("PVC: netdata-k8s-state-varlib (1Gi)\nStorageClass: local-path")]
            PodK8sState --- PVC_State
        end

        subgraph "Thu Thập Số Liệu Từng Giây (Child DaemonSet)"
            Child_CP["netdata-child\n(Control Plane: 192.168.250.123)"]
            Child_WK1["netdata-child\n(Worker 1: 192.168.250.165)"]
            Child_WK2["netdata-child\n(Worker 2: 192.168.250.223)"]
        end
    end

    %% Luồng truy cập người dùng
    Browser -->|1. HTTPS Request| Traefik
    Traefik --- MW_HTTPS
    Traefik --- MW_V3
    Traefik --- CertSecret
    Traefik -->|2. Route /v3/ (200 OK)| IngressNetdata
    IngressNetdata --> SvcParent
    SvcParent --> PodParent

    %% Luồng thu thập dữ liệu nội bộ
    Child_CP -->|Stream Metric 1s| PodParent
    Child_WK1 -->|Stream Metric 1s| PodParent
    Child_WK2 -->|Stream Metric 1s| PodParent
    PodK8sState -->|Stream K8s Cluster Data| PodParent
```

### Nguyên Lý Vận Hành Hai Tầng (Parent - Child)
1. **Child DaemonSet (Chân rết thu thập)**: Chạy trên mọi node (cả Control Plane nhờ toleration `NoSchedule`). Pod child đọc thông số từ `/proc`, `/sys`, cgroups, docker/containerd socket và stream liên tục về pod parent qua giao thức stream nhị phân tối ưu.
2. **Parent Pod (Bộ não lưu trữ & Dashboard)**: Nhận luồng metric từ tất cả các child, nén và lưu vào đĩa cứng thông qua engine `dbengine` trên Persistent Volume `local-path`, đồng thời phục vụ Web UI thống nhất cho toàn bộ cụm.

---

## 3. Phân Tích Kỹ Thuật: Giải Pháp Bypass Netdata Cloud Sign-In Bằng Traefik

### Bản Chất Lỗi "Please sign-in to continue"
Từ phiên bản **v2.x**, Netdata thay đổi chiến lược giao diện mặc định:
* Khi truy cập trang chủ `/` (`/usr/share/netdata/web/index.html`), mã nguồn JavaScript được biên dịch sẵn giá trị:
  ```javascript
  window.envSettings = {
    webpackPublicPath: "https://app.netdata.cloud",
    isLocal: false, // <-- Ép buộc người dùng kết nối Netdata Cloud
    ...
  }
  ```
  Nếu không có JWT Token đăng nhập Cloud trong `localStorage`, giao diện lập tức khóa màn hình và hiện thông báo: *"Please sign-in to continue"*.
* Tuy nhiên, bên trong container Netdata luôn đóng gói sẵn một giao diện **On-Premise Local Agent chuẩn** tại thư mục `/v3/` (`/usr/share/netdata/web/v3/index.html`):
  ```javascript
  window.envSettings = {
    webpackPublicPath: "" || (getBasename() + "/v3"),
    isLocal: true, // <-- Cho phép tải Dashboard cục bộ tức thì
    ...
  }
  ```
  Tại đây, cờ `isLocal: true` giúp hàm `loadDashboard()` kích hoạt ngay lập tức mà không đòi hỏi bất kỳ tài khoản hay kết nối ra ngoài Internet.

### Giải Pháp GitOps Tự Động Hóa Với Traefik Middleware
Thay vì can thiệp sửa file HTML tĩnh bên trong container (dễ mất khi pod bị xóa hoặc nâng cấp phiên bản), chúng ta xử lý triệt để ngay tại tầng **Ingress Controller (Traefik)**:

1. **Định nghĩa Middleware `netdata-redirect-v3`** tại [04-traefik-middleware.yaml](file:///Users/timi/lab/lab-harvester/gitops/platform/cluster-issuers/04-traefik-middleware.yaml):
   ```yaml
   apiVersion: traefik.io/v1alpha1
   kind: Middleware
   metadata:
     name: netdata-redirect-v3
     namespace: kube-system
   spec:
     redirectRegex:
       regex: "^https?://[^/]+/?$"
       replacement: "/v3/"
       permanent: false
   ```
   * **`regex: "^https?://[^/]+/?$"`**: Chỉ khớp duy nhất khi người dùng gõ domain gốc (ví dụ `https://netdata.192.168.250.99.sslip.io` hoặc có thêm dấu gạch chéo `/`).
   * **Bảo toàn API backend**: Các request gọi API của frontend như `/api/v1/...`, `/api/v3/...` hoặc đường dẫn tài sản `/v3/...` **không khớp regex**, do đó được truyền thẳng đến Netdata server mà không bị loop redirect.

2. **Gắn Middleware vào Ingress Netdata** tại [03c-netdata.yaml](file:///Users/timi/lab/lab-harvester/gitops/applications/03c-netdata.yaml):
   ```yaml
   annotations:
     traefik.ingress.kubernetes.io/router.middlewares: kube-system-redirect-https@kubernetescrd,kube-system-netdata-redirect-v3@kubernetescrd
   ```
   * Khi người dùng nhập địa chỉ vào trình duyệt, Traefik sẽ thực hiện chuỗi:
     `HTTP 80 -> HTTPS 443 -> HTTP 307 Redirect sang /v3/ -> Trả về giao diện Local Dashboard (200 OK)`.

---

## 4. Cấu Trúc Tích Hợp GitOps Argo CD

Toàn bộ hệ thống Netdata được điều phối tự động thông qua file manifest GitOps [03c-netdata.yaml](file:///Users/timi/lab/lab-harvester/gitops/applications/03c-netdata.yaml).

### Thông Số Cấu Hình Trọng Tâm
* **Argo CD Sync Wave**: `"3"` (Được triển khai sau `cert-manager` wave 1 và `cluster-issuers` wave 2 để đảm bảo có sẵn Root CA ký chứng chỉ TLS).
* **Quản lý Namespace**: `namespace: netdata` trên cluster `rke2-cluster`, kích hoạt `CreateNamespace=true`.
* **Phân Bổ Tài Nguyên (Tối ưu cho phần cứng Homelab i5)**:
  * `parent pod`:
    * Request: `100m CPU`, `256Mi RAM`
    * Limit: `500m CPU`, `1024Mi RAM`
    * Lưu trữ: `5Gi` Database + `1Gi` Alarms trên `local-path`.
  * `child daemonset`:
    * Request: `50m CPU`, `128Mi RAM`
    * Limit: `250m CPU`, `384Mi RAM`
  * `k8sState pod`:
    * Request: `50m CPU`, `128Mi RAM`
    * Limit: `200m CPU`, `256Mi RAM`
    * Lưu trữ: `1Gi` trên `local-path`.
* **Tích Hợp Chứng Chỉ TLS**:
  * Issuer: `cert-manager.io/cluster-issuer: homelab-ca-issuer`
  * Secret lưu chứng chỉ: `netdata-tls-cert` (đạt ổ khóa xanh tức thì khi import `homelab-root-ca.crt`).

---

## 5. Ma Trận So Sánh Thực Chiến: Netdata vs Prometheus + Grafana

| Tiêu Chí So Sánh | Netdata (`https://netdata...`) | Prometheus + Grafana (`https://grafana...`) |
| :--- | :--- | :--- |
| **Tần suất thu thập mẫu (Resolution)** | **1 giây (Per-second real-time)** | **15 - 30 giây (Scrape interval)** |
| **Độ trễ hiển thị (Latency)** | **Tức thì (< 1 giây)** | Có độ trễ nhất định (15 - 60 giây) |
| **Mục đích sử dụng chính** | **Khắc phục sự cố nóng (Live Troubleshooting)** | **Giám sát tổng quan & Phân tích xu hướng (Long-term Ops)** |
| **Thời gian lưu trữ dữ liệu** | Ngắn hạn đến trung hạn (1 - 7 ngày) | Dài hạn (7 - 90 ngày hoặc nhiều năm với Thanos/Cortex) |
| **Khả năng tùy biến Dashboard** | Tự động sinh dashboard thông minh (Zero-config) | Rất cao, tự vẽ dashboard theo ý thích bằng PromQL |
| **Cảnh báo (Alerting)** | Hàng trăm rule có sẵn theo dõi phần cứng/HĐH | Tùy biến rule linh hoạt qua Alertmanager & Grafana Alerts |
| **Công cụ truy vấn** | Giao diện đồ họa tương tác trực tiếp | Ngôn ngữ truy vấn mạnh mẽ **PromQL** |
| **Tài nguyên tiêu tốn** | Cực kỳ nhẹ, tối ưu bằng mã nguồn C | Tốn RAM hơn khi nạp nhiều Time-Series Metrics |

> [!TIP]
> **Quy Tắc Vàng Khi Vận Hành Homelab**:
> * Muốn biết: *"Hệ thống tuần qua có ổn không? Ổ cứng còn bao nhiêu ngày thì đầy? Dịch vụ có bị rớt lúc nửa đêm không?"* ➔ **Mở Grafana**.
> * Muốn biết: *"Tại sao trang web vừa bấm bị đơ 2 giây? Pod nào đang ngốn nghẽn CPU lúc này? Worker 1 có bị nghẽn đĩa không?"* ➔ **Mở Netdata**.

---

## 6. Cẩm Nang Xử Lý Sự Cố Thực Tế (3 Kịch Bản Thực Chiến)

### Kịch Bản 1: Node Bị Spike CPU & Ứng Dụng Gián Đoạn Từng Giây
* **Hiện tượng**: Bạn vào web thấy có lúc phản hồi cực nhanh, nhưng thỉnh thoảng bị quay tròn trong 3-5 giây. Grafana biểu đồ CPU 1 phút nhìn chỉ thấy tải tăng nhẹ.
* **Quy trình xử lý với Netdata**:
  1. Mở `https://netdata.192.168.250.99.sslip.io`.
  2. Chọn node nghi vấn ở menu bên trái (ví dụ `rke2-lab-wk-5mhbb-75g6m`).
  3. Nhìn vào mục **System Overview ➔ CPU**: Kéo chuột chọn khoảng thời gian 10 giây xảy ra độ trễ.
  4. Mở mục **Applications ➔ Apps** hoặc **Containers**: Netdata sẽ phân tích ngay lập tức tiến trình cụ thể nào (ví dụ `traefik`, `node`, `java`, `cgroups`) chiếm dụng 100% CPU trong đúng giây đó.

### Kịch Bản 2: Pod Liên Tục Khởi Động Lại Do Tràn Bộ Nhớ (OOMKilled)
* **Hiện tượng**: Lệnh `kubectl get pods` hiển thị trạng thái `CrashLoopBackOff` với lỗi `OOMKilled` (Exit Code 137), nhưng trong Grafana đường vẽ Memory chưa chạm đỉnh Limit.
* **Quy trình xử lý với Netdata**:
  1. Vào Netdata Dashboard ➔ Tìm đến mục **Kubernetes / Containers**.
  2. Chọn container đang bị restart.
  3. Quan sát đồ thị **Memory Details**: Phân tích tỷ lệ giữa **RSS (Resident Set Size)** và **Page Cache/Buffers**.
  4. Nếu RSS tăng dốc đứng liên tục mà không giải phóng ➔ Phát hiện chính xác ứng dụng bị rò rỉ bộ nhớ (Memory Leak) để fix bug mã nguồn hoặc nâng `resources.limits.memory` trong manifest.

### Kịch Bản 3: Nghẽn Tốc Độ Đọc/Ghi Ổ Đĩa (Disk I/O Bottleneck / High I/O Wait)
* **Hiện tượng**: CPU hệ thống sử dụng dưới 20% nhưng toàn bộ máy ảo và pod đều phản hồi rất chậm chạp.
* **Quy trình xử lý với Netdata**:
  1. Vào Netdata ➔ Mục **Disks ➔ Disk I/O & Latency**.
  2. Kiểm tra chỉ số **await** (thời gian chờ trung bình cho mỗi I/O request):
     * Bình thường (SSD/NVMe): `< 5ms`.
     * Cảnh báo nghẽn (Bottleneck): `> 20ms - 50ms`.
  3. Kiểm tra mục **Disk Backlog / Utilization**: Nếu đĩa chạm 100% utilization, chuyển sang tab **Processes** để tìm tiến trình nào đang ghi log liên tục hoặc database đang thực hiện full table scan.

---

## 7. Lệnh Vận Hành & Khắc Phục Lỗi Nhanh (Cheat Sheet)

### Kiểm Tra Trạng Thái Pods & PVCs
```bash
# Xem trạng thái toàn bộ pods trong namespace netdata trên cụm RKE2
kubectl --kubeconfig ./gitops/infrastructure/rke2-cluster/rke2-kubeconfig.yaml -n netdata get pods -o wide

# Kiểm tra dung lượng và trạng thái gắn đĩa PVC
kubectl --kubeconfig ./gitops/infrastructure/rke2-cluster/rke2-kubeconfig.yaml -n netdata get pvc
```

### Kiểm Tra Ingress, Middlewares & Chứng Chỉ TLS
```bash
# Kiểm tra Ingress và các annotations Traefik
kubectl --kubeconfig ./gitops/infrastructure/rke2-cluster/rke2-kubeconfig.yaml -n netdata get ingress netdata -o yaml

# Kiểm tra Middleware redirect-v3 trong kube-system
kubectl --kubeconfig ./gitops/infrastructure/rke2-cluster/rke2-kubeconfig.yaml -n kube-system get middleware netdata-redirect-v3

# Kiểm tra trạng thái cấp chứng chỉ SSL bởi Root CA
kubectl --kubeconfig ./gitops/infrastructure/rke2-cluster/rke2-kubeconfig.yaml -n netdata get certificate netdata-tls-cert
```

### Test Kết Nối Trực Tiếp Bằng Curl
```bash
# Kiểm tra redirect HTTP 307 từ root sang /v3/
curl -Iv --cacert homelab-root-ca.crt https://netdata.192.168.250.99.sslip.io/

# Kiểm tra mã HTTP 200 tải thành công của Dashboard On-premise
curl -s -o /dev/null -w "HTTP Code: %{http_code}\n" --cacert homelab-root-ca.crt https://netdata.192.168.250.99.sslip.io/v3/
```

### Khởi Động Lại Nhanh Khi Cần
```bash
# Restart Parent Pod
kubectl --kubeconfig ./gitops/infrastructure/rke2-cluster/rke2-kubeconfig.yaml -n netdata rollout restart deployment/netdata-parent

# Restart Child DaemonSet trên các Node
kubectl --kubeconfig ./gitops/infrastructure/rke2-cluster/rke2-kubeconfig.yaml -n netdata rollout restart daemonset/netdata-child
```
