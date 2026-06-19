#!/usr/bin/env bash

set -euo pipefail

INSTALL_DIR="/usr/local/bin"
CONFIG_DIR="/etc/sing-box"
SERVICE_FILE="/etc/systemd/system/sing-box.service"
GH_PROXY="https://v4.gh-proxy.org"

echo "========================================"
echo " Sing-Box Install / Upgrade Script"
echo "========================================"

command -v curl >/dev/null || { echo "curl 未安装"; exit 1; }
command -v jq >/dev/null || { echo "jq 未安装，请执行: apt install -y jq"; exit 1; }
command -v wget >/dev/null || { echo "wget 未安装"; exit 1; }

echo
echo "获取最新版本信息..."

JSON=$(curl -fsSL https://api.github.com/repos/SagerNet/sing-box/releases/latest)

VERSION=$(echo "$JSON" | jq -r '.tag_name')

URL=$(echo "$JSON" | jq -r '
  .assets[]
  | select(.name|test("^sing-box-[0-9.]+-linux-amd64\\.tar\\.gz$"))
  | .browser_download_url
')

if [ -z "$URL" ] || [ "$URL" = "null" ]; then
    echo "获取下载链接失败"
    exit 1
fi

DOWNLOAD_URL="${GH_PROXY}/${URL}"
FILE_NAME=$(basename "$URL")

echo "最新版本: ${VERSION}"
echo "下载地址:"
echo "$DOWNLOAD_URL"
echo

TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

cd "$TMP_DIR"

echo "开始下载..."
wget -q --show-progress "$DOWNLOAD_URL" -O "$FILE_NAME"

echo
echo "解压文件..."
tar -xzf "$FILE_NAME"

BIN=$(find . -type f -name sing-box | head -n1)

if [ ! -f "$BIN" ]; then
    echo "未找到 sing-box 可执行文件"
    exit 1
fi

if command -v sing-box >/dev/null 2>&1; then

    CURRENT_VERSION=$(sing-box version 2>/dev/null | head -n1 || true)

    echo
    echo "检测到已安装:"
    echo "$CURRENT_VERSION"
    echo
    echo "开始升级..."

    install -m 755 "$BIN" "$INSTALL_DIR/sing-box"

    systemctl daemon-reload

    if systemctl is-enabled sing-box >/dev/null 2>&1; then
        systemctl restart sing-box
    fi

    echo
    echo "升级完成"
    sing-box version

else

    echo
    echo "未检测到 sing-box，开始安装..."

    mkdir -p "$CONFIG_DIR"

    install -m 755 "$BIN" "$INSTALL_DIR/sing-box"

    if [ ! -f "$SERVICE_FILE" ]; then

cat > "$SERVICE_FILE" <<'EOF'
[Unit]
Description=sing-box Service
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/sing-box run -c /etc/sing-box/config.json
Restart=always
RestartSec=5
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF

    fi

    if [ ! -f "$CONFIG_DIR/config.json" ]; then

cat > "$CONFIG_DIR/config.json" <<'EOF'
{
  "log": {
    "level": "info"
  }
}
EOF

    fi

    systemctl daemon-reload
    systemctl enable sing-box

    echo
    echo "安装完成"
    echo
    echo "配置文件:"
    echo "  $CONFIG_DIR/config.json"
    echo
    echo "启动服务:"
    echo "  systemctl start sing-box"
    echo
    echo "查看状态:"
    echo "  systemctl status sing-box"
    echo
    sing-box version

fi

echo
echo "完成"
