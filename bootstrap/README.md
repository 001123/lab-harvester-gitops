# Hướng Dẫn Bootstrap GitOps Cho Harvester

Thư mục này chứa các kịch bản bootstrap tự động để đưa cụm **Harvester HCI** vào quản lý bởi **Flux Operator v0.60.0** và **FluxCD 2.x**.

---

## 1. Yêu cầu trước khi chạy
- Máy trạm đã cài đặt: `kubectl`, `helm`, `sops`, `age`.
- File private key của Age nằm tại `~/.config/sops/age/keys.txt`.
- Đặt file `kubeconfig.yaml` của cụm Harvester ở thư mục gốc của repository.

---

## 2. Các bước thực hiện

### Bước 1: Khởi tạo Secret SOPS Age
```bash
./bootstrap/01-setup-sops-age.sh
```
Script sẽ tạo namespace `flux-system` và đẩy secret `sops-age` lên Harvester để Flux có thể giải mã các cấu hình nhạy cảm.

### Bước 2: Cài đặt Flux Operator v0.60.0 & Kích hoạt FluxInstance
```bash
./bootstrap/02-install-flux-operator.sh
```
Script sẽ kéo Helm chart Flux Operator từ OCI registry (`ghcr.io/controlplaneio-fluxcd/charts/flux-operator`), cài đặt lên namespace `flux-system`, và kích hoạt `FluxInstance` để bắt đầu kéo cấu hình từ Git.

---

## 3. Theo dõi & Kiểm tra

- **Xem trạng thái Flux Operator**:
  ```bash
  kubectl -n flux-system get pods -l app.kubernetes.io/name=flux-operator
  ```

- **Xem trạng thái đồng bộ GitOps**:
  ```bash
  kubectl -n flux-system get fluxinstances,gitrepositories,kustomizations
  ```

- **Mở Dashboard giao diện của Flux Operator**:
  ```bash
  kubectl -n flux-system port-forward svc/flux-operator 9080:9080
  ```
  Mở trình duyệt tại [http://localhost:9080](http://localhost:9080).
