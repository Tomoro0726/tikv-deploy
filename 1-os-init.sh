#!/bin/bash

# エラー発生時にスクリプトを停止する
set -e

# ルート権限チェック
if [ "$EUID" -ne 0 ]; then
  echo "エラー: このスクリプトはroot権限で実行してください。(例: sudo ./init_tikv_os.sh)"
  exit 1
fi

echo "=== TiKV OS Initialization Script ==="

# 1. スワップの無効化
echo "[1/5] スワップ領域を無効化しています..."
swapoff -a
sed -i -e '/swap/d' /etc/fstab
sed -i -e '/none.*swap/d' /etc/fstab

# 2. CPUガバナーの設定
echo "[2/5] CPUガバナーを performance に設定しています..."
DEBIAN_FRONTEND=noninteractive apt-get update -qq
DEBIAN_FRONTEND=noninteractive apt-get install -y -qq cpufrequtils
echo 'GOVERNOR="performance"' > /etc/default/cpufrequtils
systemctl restart cpufrequtils

# 3. ファイルディスクリプタとカーネルパラメータのチューニング
echo "[3/5] limits.conf と sysctl の設定を適用しています..."
cat <<EOF > /etc/security/limits.d/99-tikv.conf
* soft nofile 1000000
* hard nofile 1000000
root soft nofile 1000000
root hard nofile 1000000
EOF

cat <<EOF > /etc/sysctl.d/99-tikv.conf
fs.file-max = 1000000
vm.swappiness = 0
net.core.somaxconn = 32768
net.ipv4.tcp_syncookies = 0
EOF
sysctl --system > /dev/null

# 4. Transparent Huge Pages (THP) の無効化
echo "[4/5] Transparent Huge Pages (THP) を無効化しています..."
cat <<EOF > /etc/systemd/system/disable-thp.service
[Unit]
Description=Disable Transparent Huge Pages (THP)

[Service]
Type=oneshot
ExecStart=/bin/sh -c "echo never > /sys/kernel/mm/transparent_hugepage/enabled"
ExecStart=/bin/sh -c "echo never > /sys/kernel/mm/transparent_hugepage/defrag"

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl start disable-thp
systemctl enable disable-thp

# 5. 時刻同期（NTP）の設定
echo "[5/5] chrony (NTP) をインストールして設定しています..."
DEBIAN_FRONTEND=noninteractive apt-get install -y -qq chrony
systemctl enable chrony
systemctl restart chrony

echo "========================================="
echo "すべての初期化処理が正常に完了しました。"
echo "========================================="

# 最終確認としていくつかのステータスを表示
echo "[確認] CPUガバナー:"
cpufreq-info | grep "current policy" | head -n 1
echo "[確認] chrony 同期ステータス:"
chronyc tracking | grep "Leap status"