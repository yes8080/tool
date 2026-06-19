#!/usr/bin/env bash

set -euo pipefail

GH_PROXY="https://v4.gh-proxy.org"
CONFIG_FILE="/etc/rustdesk-install.conf"

echo "========================================"
echo " RustDesk Server Production Installer"
echo "========================================"
echo "1) 安装 / 升级"
echo "2) 重新安装（保留密钥）"
echo "3) 完全重装（删除密钥）"
echo "4) 修改域名 / IP"
echo "5) 卸载"
echo "========================================"

read -rp "请选择 [1-5]: " ACTION

# =========================
# 自动识别 service 名
# =========================
detect_service() {
    if systemctl list-unit-files | grep -q "rustdesk-hbbs"; then
        HBBS="rustdesk-hbbs"
        HBBR="rustdesk-hbbr"
    else
        HBBS="hbbs"
        HBBR="hbbr"
    fi
}

# =========================
# 读取配置
# =========================
load_config() {
    if [ -f "$CONFIG_FILE" ]; then
        source "$CONFIG_FILE"
    fi
    DOMAIN="${DOMAIN:-}"
}

save_config() {
    echo "DOMAIN=$DOMAIN" > "$CONFIG_FILE"
}

# =========================
# 安装依赖
# =========================
install_deps() {
    apt update -y
    apt install -y curl wget jq ufw dpkg
}

# =========================
# 放行防火墙
# =========================
setup_firewall() {
    ufw allow 21116/tcp || true
    ufw allow 21116/udp || true
    ufw allow 21117/tcp || true
    ufw reload || true
}

# =========================
# 获取最新版本
# =========================
get_latest() {
    JSON=$(curl -fsSL https://api.github.com/repos/rustdesk/rustdesk-server/releases/latest)

    HBBS_URL=$(echo "$JSON" | jq -r '
    .assets[]
    | select(.name|test("hbbs.*amd64\\.deb$"))
    | .browser_download_url
    ' | head -n1)

    HBBR_URL=$(echo "$JSON" | jq -r '
    .assets[]
    | select(.name|test("hbbr.*amd64\\.deb$"))
    | .browser_download_url
    ' | head -n1)
}

# =========================
# 安装核心
# =========================
install_all() {

    install_deps
    detect_service
    load_config

    if [ -z "$DOMAIN" ]; then
        read -rp "请输入服务器 IP 或域名: " DOMAIN
        save_config
    else
        echo "当前配置: $DOMAIN"
        read -rp "是否修改? (y/N): " y
        if [[ "$y" =~ ^[Yy]$ ]]; then
            read -rp "请输入新的 IP 或域名: " DOMAIN
            save_config
        fi
    fi

    echo "使用地址: $DOMAIN"

    setup_firewall
    get_latest

    TMP=$(mktemp -d)
    cd "$TMP"

    wget -q --show-progress "${GH_PROXY}/${HBBS_URL}" -O hbbs.deb
    wget -q --show-progress "${GH_PROXY}/${HBBR_URL}" -O hbbr.deb

    dpkg -i hbbs.deb hbbr.deb || apt -f install -y

    systemctl daemon-reload

    systemctl enable $HBBS $HBBR >/dev/null 2>&1 || true

    systemctl restart $HBBS $HBBR

    echo "安装完成"
}

# =========================
# 重新安装（保留密钥）
# =========================
reinstall_keep() {
    detect_service
    systemctl stop $HBBS $HBBR 2>/dev/null || true
    apt remove -y rustdesk-server-hbbs rustdesk-server-hbbr 2>/dev/null || true
    install_all
}

# =========================
# 完全重装
# =========================
full_reset() {
    detect_service
    systemctl stop $HBBS $HBBR 2>/dev/null || true
    apt purge -y rustdesk-server-hbbs rustdesk-server-hbbr 2>/dev/null || true
    rm -rf /var/lib/rustdesk-server || true
    rm -f "$CONFIG_FILE"
    install_all
}

# =========================
# 修改 IP / 域名
# =========================
change_domain() {
    load_config
    echo "当前: $DOMAIN"
    read -rp "输入新的 IP / 域名: " DOMAIN
    save_config

    detect_service
    systemctl restart $HBBS $HBBR 2>/dev/null || true
}

# =========================
# 卸载
# =========================
uninstall() {
    detect_service
    systemctl stop $HBBS $HBBR 2>/dev/null || true
    systemctl disable $HBBS $HBBR 2>/dev/null || true
    apt purge -y rustdesk-server-hbbs rustdesk-server-hbbr
    rm -f "$CONFIG_FILE"
    echo "已卸载"
}

# =========================
# 路由
# =========================
case "$ACTION" in
    1) install_all ;;
    2) reinstall_keep ;;
    3) full_reset ;;
    4) change_domain ;;
    5) uninstall ;;
    *) echo "无效选项" ;;
esac
