#!/usr/bin/env bash

set -euo pipefail

GH_PROXY="https://v4.gh-proxy.org"
CONFIG_FILE="/etc/rustdesk-install.conf"

echo "========================================"
echo " RustDesk Server Manager (Fixed Version)"
echo "========================================"
echo "1) 安装 / 升级"
echo "2) 重新安装（保留密钥）"
echo "3) 完全重装（删除密钥）"
echo "4) 修改域名 / IP"
echo "5) 卸载"
echo "========================================"

read -rp "请选择 [1-5]: " ACTION

install_deps() {
    for c in curl jq wget dpkg systemctl; do
        command -v $c >/dev/null 2>&1 || {
            echo "缺少依赖: $c"
            exit 1
        }
    done
}

detect_service() {
    # 自动识别 systemd service 名
    if systemctl list-unit-files | grep -q "rustdesk-hbbs"; then
        HBBS_SVC="rustdesk-hbbs"
        HBBR_SVC="rustdesk-hbbr"
    else
        HBBS_SVC="hbbs"
        HBBR_SVC="hbbr"
    fi
}

load_domain() {
    if [ -f "$CONFIG_FILE" ]; then
        source "$CONFIG_FILE" || true
    fi
    DOMAIN="${DOMAIN:-}"
}

save_domain() {
    echo "DOMAIN=${DOMAIN}" > "$CONFIG_FILE"
}

get_latest() {
    JSON=$(curl -fsSL https://api.github.com/repos/rustdesk/rustdesk-server/releases/latest)

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
}

install_all() {

    install_deps
    detect_service
    load_domain

    if [ -z "$DOMAIN" ]; then
        read -rp "请输入域名或IP: " DOMAIN
        save_domain
    else
        echo "当前: $DOMAIN"
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

    systemctl daemon-reload

    systemctl enable $HBBS_SVC $HBBR_SVC >/dev/null 2>&1 || true

    systemctl restart $HBBS_SVC $HBBR_SVC

    echo "安装完成"
}

reinstall_keep_key() {
    detect_service
    systemctl stop $HBBS_SVC $HBBR_SVC 2>/dev/null || true
    apt remove -y rustdesk-server-hbbs rustdesk-server-hbbr 2>/dev/null || true
    install_all
}

full_reset() {
    detect_service
    systemctl stop $HBBS_SVC $HBBR_SVC 2>/dev/null || true
    apt remove -y rustdesk-server-hbbs rustdesk-server-hbbr 2>/dev/null || true
    rm -rf /var/lib/rustdesk-server 2>/dev/null || true
    rm -f "$CONFIG_FILE"
    install_all
}

change_domain() {
    load_domain
    echo "当前: $DOMAIN"
    read -rp "新域名/IP: " DOMAIN
    save_domain

    detect_service
    systemctl restart $HBBS_SVC $HBBR_SVC 2>/dev/null || true
}

uninstall() {
    detect_service
    systemctl stop $HBBS_SVC $HBBR_SVC 2>/dev/null || true
    systemctl disable $HBBS_SVC $HBBR_SVC 2>/dev/null || true
    apt remove -y rustdesk-server-hbbs rustdesk-server-hbbr 2>/dev/null || true
    echo "已卸载（密钥保留）"
}

case "$ACTION" in
    1) install_all ;;
    2) reinstall_keep_key ;;
    3) full_reset ;;
    4) change_domain ;;
    5) uninstall ;;
    *) echo "无效选项" ;;
esac
