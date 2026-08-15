#!/bin/bash
set -e

if [ "$EUID" -ne 0 ]; then
  echo "エラー: このスクリプトはroot権限で実行してください。(例: sudo ./init_disks_tikv.sh)"
  exit 1
fi

echo "=========================================================="
echo " ⚠️ 警告: OSが使用しているディスク以外の【すべてのディスク】"
echo " を強制的に XFS でフォーマットします。"
echo " 既存のデータはすべて失われます。"
echo "=========================================================="
read -p "続行しますか？ (y/N): " confirm
if [[ "$confirm" != [yY] && "$confirm" != [yY][eE][sS] ]]; then
  echo "キャンセルしました。"
  exit 0
fi

# 必要なパッケージのインストール
DEBIAN_FRONTEND=noninteractive apt-get update -qq
DEBIAN_FRONTEND=noninteractive apt-get install -y -qq xfsprogs iproute2

# 自身のIPアドレスとホスト名を取得
# (外部へルーティングされる際のデフォルトIPを取得します)
HOST_IP=$(ip route get 1.1.1.1 | awk -F"src " 'NR==1{split($2,a," ");print a[1]}')
HOSTNAME=$(hostname)

echo "----------------------------------------------------------"
echo "Host IP   : $HOST_IP"
echo "Hostname  : $HOSTNAME"
echo "----------------------------------------------------------"

SSD_COUNT=0
HDD_COUNT=0
PORT=20160
STATUS_PORT=20180
TOPOLOGY_FILE="/tmp/tikv_topology_snippet.yaml"

# 出力用ファイルの初期化
echo "tikv_servers:" > "$TOPOLOGY_FILE"

# 物理ディスクの一覧を取得 (TYPE=disk)
# lsblk の ROTA フラグ: 0=SSD, 1=HDD
while read -r DISK ROTA; do
  DEV_PATH="/dev/$DISK"

  # そのディスク、または配下のパーティションが現在OSにマウントされているかチェック
  MOUNTPOINTS=$(lsblk -n -o MOUNTPOINT "$DEV_PATH" | grep -v '^\s*$' || true)
  if [ -n "$MOUNTPOINTS" ]; then
    echo "[スキップ] $DEV_PATH はOSまたは他の用途で使用されています（マウントポイントあり）。"
    continue
  fi

  # SSDかHDDかの判定
  if [ "$ROTA" -eq 0 ]; then
    DISK_TYPE="ssd"
    SSD_COUNT=$((SSD_COUNT+1))
    MOUNT_POINT="/data/ssd${SSD_COUNT}"
  else
    DISK_TYPE="hdd"
    HDD_COUNT=$((HDD_COUNT+1))
    MOUNT_POINT="/data/hdd${HDD_COUNT}"
  fi

  echo "[$DISK_TYPE] $DEV_PATH を初期化して $MOUNT_POINT にマウントします..."

  # XFSでフォーマット (-f で強制)
  mkfs.xfs -f -i size=512 "$DEV_PATH" > /dev/null

  # マウントポイントの作成とマウント
  mkdir -p "$MOUNT_POINT"
  mount -t xfs -o nodelalloc,noatime "$DEV_PATH" "$MOUNT_POINT"

  # fstabへの追記 (再起動後もマウントさせるためUUIDを使用)
  UUID=$(blkid -s UUID -o value "$DEV_PATH")
  if ! grep -q "$UUID" /etc/fstab; then
    echo "UUID=$UUID $MOUNT_POINT xfs defaults,nodelalloc,noatime 0 2" >> /etc/fstab
  fi

  # トポロジーファイル（YAML）への設定ブロック追記
  cat <<EOF >> "$TOPOLOGY_FILE"
  - host: $HOST_IP
    port: $PORT
    status_port: $STATUS_PORT
    data_dir: "${MOUNT_POINT}/tikv-data"
    config:
      server.labels: { host: "$HOSTNAME", disk: "$DISK_TYPE" }
EOF

  # 同じPC内でポートが競合しないようにインクリメント
  PORT=$((PORT+1))
  STATUS_PORT=$((STATUS_PORT+1))

done < <(lsblk -n -d -o NAME,ROTA,TYPE | awk '$3=="disk" {print $1, $2}')

echo ""
echo "=========================================================="
echo " ✅ ディスクの初期化とマウントが完了しました！"
echo " 管理用PCの topology.yaml に以下の内容を貼り付けてください。"
echo "=========================================================="
cat "$TOPOLOGY_FILE"
echo "=========================================================="