#!/usr/bin/env bash
RANCHER_IP="192.168.250.30"
SSH_PORT="22"

echo "=== Đang theo dõi tiến trình cài đặt Rancher trên openSUSE Leap Micro 6.2 qua SSH (Ctrl+C để thoát) ==="
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -p "$SSH_PORT" "opensuse@$RANCHER_IP" "tail -f /var/log/rancher-bootstrap.log"
