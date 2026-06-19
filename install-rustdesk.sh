#!/usr/bin/env bash

set -euo pipefail

GH_PROXY="https://v4.gh-proxy.org"
CONFIG_FILE="/etc/rustdesk-install.conf"

echo "========================================"
echo " RustDesk Server Manager"
echo "========================================"
echo "1) 安装 / 升级"
echo "2) 重新安装（保留密钥）"
echo "3) 完全重装（删除密钥）"
echo "4) 修改域名 / IP"
echo "5) 卸载"
echo "========================================"
read -rp "请选择 [1-5]: " ACTION

DOMAIN=""

load_domain() {
    if [ -f "$CONFIG_FILE" ]; then
        source "$CONFIG_FILE" || true
        DOMAIN="${DOMAIN:-}"
    fi
}

save_domain() {
    echo "DOMAIN=${DOMAIN}" > "$CONFIG_FILE"
}

install_deps() {
    for c in curl jq wget dpkg systemctl; do
        command -v $c >/dev/null 2>&1 || {
            echo "缺少依赖: $c"
            exit 1
        }
    done
}

get_latest() {
    JSON=$(curl -fsSL https://api.github.com/repos/rustdesk/rustdesk-server/releases/latest)

    VERSION=$(echo "$JSON" | jq -r '.tag_name')

    HBBS_URL=$(echo "$JSON" | jq -r '
    .assets[]
    | select(.name|test("^rustdesk-server-hbbs_.*_amd64\\.deb$"))
    | .browser_download_url
    ' | head -n1)

    HBBR_URL=$(echo "$JSON" | jq -r '
    .assets[]
    | select(.name|test("^rustdesk-server-hbbr_.*_amd64\\.deb$"))
    | .browser_download_url
    ' | head -n1)

    if [ -z "$HBBS_URL" ] || [ -z "$HBBR_URL" ]; then
        echo "获取版本失败"
        exit 1
    fi
}

install_all() {

    install_deps
    load_domain

    if [ -z "$DOMAIN" ]; then
        read -rp "请输入域名或IP: " DOMAIN
        save_domain
    else
        echo "当前域名/IP: $DOMAIN"
        read -rp "是否修改? (y/N): " y
        if [[ "$y" =~ ^[Yy]$ ]]; then
            read -rp "输入新域名/IP: " DOMAIN
            save_domain
        fi
    fi

    echo "使用: $DOMAIN"

    get_latest

    TMP=$(mktemp -d)
    cd "$TMP"

    wget -q --show-progress "${GH_PROXY}/${HBBS_URL}" -O hbbs.deb
    wget -q --show-progress "${GH_PROXY}/${HBBR_URL}" -O hbbr.deb

    dpkg -i hbbs.deb hbbr.deb || apt-get install -fy

    mkdir -p /etc/systemd/system/hbbs.service.d

    cat > /etc/systemd/system/hbbs.service.d/override.conf <<EOF
[Service]
ExecStart=
ExecStart=/usr/bin/hbbs -r ${DOMAIN}:21117
EOF

    systemctl daemon-reload
    systemctl enable hbbs hbbr >/dev/null 2>&1 || true
    systemctl restart hbbs hbbr

    echo
    echo "安装完成"
}

reinstall_keep_key() {
    systemctl stop hbbs hbbr || true
    apt remove -y rustdesk-server-hbbs rustdesk-server-hbbr || true
    install_all
}

full_reset() {
    systemctl stop hbbs hbbr || true
    apt remove -y rustdesk-server-hbbs rustdesk-server-hbbr || true
    rm -rf /var/lib/rustdesk-server || true
    rm -f "$CONFIG_FILE"
    install_all
}

change_domain() {
    load_domain
    echo "当前: $DOMAIN"
    read -rp "输入新域名/IP: " DOMAIN
    save_domain
    systemctl restart hbbs hbbr || true
}

uninstall() {
    systemctl stop hbbs hbbr || true
    systemctl disable hbbs hbbr || true
    apt remove -y rustdesk-server-hbbs rustdesk-server-hbbr || true
    echo "已卸载（密钥保留在 /var/lib/rustdesk-server）"
}

case "$ACTION" in
    1) install_all ;;
    2) reinstall_keep_key ;;
    3) full_reset ;;
    4) change_domain ;;
    5) uninstall ;;
    *) echo "无效选项" ;;
esac
