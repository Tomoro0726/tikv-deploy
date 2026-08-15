#!/bin/bash
set -e

# ==========================================
# TiUP クラスタメタデータ バックアップスクリプト
# ==========================================

# 日時を用いたバックアップファイル名の定義
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
BACKUP_DIR="${HOME}/tiup_backups"
BACKUP_FILE="${BACKUP_DIR}/tiup_cluster_backup_${TIMESTAMP}.zip"
TIUP_HOME="${HOME}/.tiup"
CLUSTER_DATA_DIR="${TIUP_HOME}/storage/cluster/clusters"

echo "=== TiUP Backup Script ==="

# 1. バックアップ対象が存在するか確認
if [ ! -d "$CLUSTER_DATA_DIR" ]; then
  echo "❌ エラー: TiUPのクラスタデータが見つかりません。"
  echo "パス: $CLUSTER_DATA_DIR が存在するか確認してください。"
  exit 1
fi

# 2. バックアップ保存先ディレクトリの作成
mkdir -p "$BACKUP_DIR"

# 3. zip コマンドの確認とインストール
if ! command -v zip &> /dev/null; then
    echo "zipコマンドが見つかりません。インストールしています..."
    sudo apt-get update -qq && sudo apt-get install -y -qq zip
fi

echo "抽出対象: $CLUSTER_DATA_DIR"
echo "バックアップファイルを生成中..."

# ~/.tiup に移動して相対パスで圧縮（復元時に元の構造に戻しやすくするため）
cd "$TIUP_HOME"

# クラスタ運用に必須のディレクトリのみを再帰的に圧縮
# (meta.yaml, トポロジ情報, 各ノードへのSSH秘密鍵が含まれます)
zip -r "$BACKUP_FILE" "storage/cluster/clusters" > /dev/null

# 4. セキュリティ保護 (SSH鍵が含まれるため、自分以外読み取れないようにする)
chmod 600 "$BACKUP_FILE"

echo "=========================================================="
echo " ✅ バックアップが正常に完了しました！"
echo " 保存先: $BACKUP_FILE"
echo "=========================================================="
echo " ⚠️ 重要 ⚠️"
echo " このZIPファイルには、各TiKVノードのroot権限でアクセス可能な"
echo " 【SSH秘密鍵 (id_rsa)】 がプレーンテキストで含まれています。"
echo " USBメモリ等にコピーする際は、漏洩しないよう厳重に管理してください。"
echo "=========================================================="