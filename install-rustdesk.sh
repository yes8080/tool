#!/usr/bin/env bash

set -euo pipefail

GH_PROXY="https://v4.gh-proxy.org"
CONFIG_FILE="/etc/rustdesk-install.conf"

echo "========================================"
echo " RustDesk Server Install / Upgrade"
echo "========================================"

for cmd in curl jq wget dpkg systemctl; do
command -v "$cmd" >/dev/null || {
echo "$cmd 未安装"
exit 1
}
done

echo

# --------------------------------------------------

# 域名配置

# --------------------------------------------------

if [ -f "$CONFIG_FILE" ]; then

```
source "$CONFIG_FILE"

echo "检测到已配置域名/IP:"
echo "  $DOMAIN"
echo

read -rp "是否修改？(y/N): " CHANGE_DOMAIN

if [[ "$CHANGE_DOMAIN" =~ ^[Yy]$ ]]; then

    PUBLIC_IP=$(curl -4 -fsSL https://api.ipify.org || true)

    read -rp "请输入域名或公网IP [默认:${PUBLIC_IP}]: " DOMAIN

    DOMAIN=${DOMAIN:-$PUBLIC_IP}

    echo "DOMAIN=${DOMAIN}" > "$CONFIG_FILE"

fi
```

else

```
PUBLIC_IP=$(curl -4 -fsSL https://api.ipify.org || true)

read -rp "请输入 RustDesk 服务域名或公网IP [默认:${PUBLIC_IP}]: " DOMAIN

DOMAIN=${DOMAIN:-$PUBLIC_IP}

if [ -z "$DOMAIN" ]; then
    echo "域名/IP不能为空"
    exit 1
fi

echo "DOMAIN=${DOMAIN}" > "$CONFIG_FILE"
```

fi

echo
echo "使用服务器地址:"
echo "  $DOMAIN"
echo

# --------------------------------------------------

# 获取最新版本

# --------------------------------------------------

echo "获取最新版本信息..."

JSON=$(curl -fsSL https://api.github.com/repos/rustdesk/rustdesk-server/releases/latest)

VERSION=$(echo "$JSON" | jq -r '.tag_name')

HBBS_URL=$(echo "$JSON" | jq -r '
.assets[]
| select(.name|test("^rustdesk-server-hbbs_.*_amd64\.deb$"))
| .browser_download_url
' | head -n1)

HBBR_URL=$(echo "$JSON" | jq -r '
.assets[]
| select(.name|test("^rustdesk-server-hbbr_.*_amd64\.deb$"))
| .browser_download_url
' | head -n1)

if [ -z "$HBBS_URL" ] || [ "$HBBS_URL" = "null" ]; then
echo "获取 HBBS 下载链接失败"
exit 1
fi

if [ -z "$HBBR_URL" ] || [ "$HBBR_URL" = "null" ]; then
echo "获取 HBBR 下载链接失败"
exit 1
fi

echo
echo "最新版本: $VERSION"
echo

TMP_DIR=$(mktemp -d)

cleanup() {
rm -rf "$TMP_DIR"
}

trap cleanup EXIT

cd "$TMP_DIR"

# --------------------------------------------------

# 下载

# --------------------------------------------------

echo "下载 HBBS..."

wget -q --show-progress 
"${GH_PROXY}/${HBBS_URL}" 
-O hbbs.deb

echo
echo "下载 HBBR..."

wget -q --show-progress 
"${GH_PROXY}/${HBBR_URL}" 
-O hbbr.deb

# --------------------------------------------------

# 安装升级

# --------------------------------------------------

echo
echo "安装/升级中..."

dpkg -i hbbs.deb hbbr.deb || apt-get install -fy

# --------------------------------------------------

# 创建 systemd override

# --------------------------------------------------

mkdir -p /etc/systemd/system/hbbs.service.d

cat > /etc/systemd/system/hbbs.service.d/override.conf <<EOF
[Service]
ExecStart=
ExecStart=/usr/bin/hbbs -r ${DOMAIN}:21117
EOF

systemctl daemon-reload

systemctl enable hbbs
systemctl enable hbbr

systemctl restart hbbs
systemctl restart hbbr

sleep 3

# --------------------------------------------------

# 获取公钥

# --------------------------------------------------

PUBKEY=""

for KEYFILE in 
/var/lib/rustdesk-server/id_ed25519.pub 
/opt/rustdesk/id_ed25519.pub 
/root/id_ed25519.pub
do

```
if [ -f "$KEYFILE" ]; then
    PUBKEY=$(cat "$KEYFILE")
    break
fi
```

done

# --------------------------------------------------

# 输出结果

# --------------------------------------------------

echo
echo "========================================"
echo " 安装完成"
echo "========================================"
echo

echo "客户端配置："
echo
echo "ID Server:"
echo "  $DOMAIN"
echo
echo "Relay Server:"
echo "  $DOMAIN"
echo

if [ -n "$PUBKEY" ]; then

```
echo "Key:"
echo "  $PUBKEY"
echo
```

fi

echo "服务状态："
echo

systemctl --no-pager is-active hbbs
systemctl --no-pager is-active hbbr

echo
echo "查看日志："
echo "  journalctl -u hbbs -f"
echo "  journalctl -u hbbr -f"

echo
echo "开放端口："
echo "  21115/tcp"
echo "  21116/tcp"
echo "  21116/udp"
echo "  21117/tcp"

echo
echo "完成。"
