#!/bin/bash
set -e

# ルート権限チェック
if [ "$EUID" -ne 0 ]; then
  echo "エラー: root権限で実行してください。(例: sudo ./setup_ssh_keys.sh <GitHubユーザー名>)"
  exit 1
fi

# 引数チェック
if [ -z "$1" ]; then
  echo "エラー: GitHubのユーザー名を引数に指定してください。"
  echo "使用方法: sudo ./setup_ssh_keys.sh <GitHubユーザー名>"
  exit 1
fi

GITHUB_USERNAME="$1"

echo "GitHub ($GITHUB_USERNAME) からSSH公開鍵を取得しています..."

# 必要なパッケージ(curl)のインストール
DEBIAN_FRONTEND=noninteractive apt-get update -qq
DEBIAN_FRONTEND=noninteractive apt-get install -y -qq curl

# .sshディレクトリの作成と権限設定
mkdir -p /root/.ssh
chmod 700 /root/.ssh

# 公開鍵を取得して authorized_keys に追記
if curl -sLf "https://github.com/${GITHUB_USERNAME}.keys" >> /root/.ssh/authorized_keys; then
  chmod 600 /root/.ssh/authorized_keys
  echo "✅ SSH公開鍵の配置が完了しました。(/root/.ssh/authorized_keys)"
else
  echo "❌ エラー: GitHubユーザー '$GITHUB_USERNAME' の公開鍵が取得できませんでした。"
  echo "ユーザー名が正しいか、GitHubに公開鍵が登録されているか確認してください。"
  exit 1
fi