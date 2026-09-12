#!/usr/bin/env bash
HARVESTER_IP="192.168.250.2"
SSH_PORT="31022"

echo "=== Đang theo dõi tiến trình cài đặt Rancher trên openSUSE Leap Micro 6.2 qua SSH (Ctrl+C để thoát) ==="
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -p "$SSH_PORT" "opensuse@$HARVESTER_IP" "tail -f /var/log/rancher-bootstrap.log"
