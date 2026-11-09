#!/bin/sh

set -u

SRC_DIR=$(CDPATH= cd "$(dirname "$0")" 2>/dev/null && pwd)

say() {
    printf '%s\n' "$*"
}

fail() {
    printf 'install: %s\n' "$*" >&2
    exit 1
}

[ "$(id -u)" = 0 ] || fail "请用 root 运行此安装脚本（sudo ./install.sh）"
[ -f /etc/debian_version ] || fail "没有检测到 Debian（缺少 /etc/debian_version）"
command -v systemctl >/dev/null 2>&1 || fail "没有检测到 systemd"
[ -d "$SRC_DIR/files" ] || fail "找不到项目文件目录: $SRC_DIR/files"
[ -f "$SRC_DIR/config/hnu-campus.conf.example" ] || fail "找不到配置模板"

mkdir -p /usr/local/sbin /usr/local/share/hnu-campus /etc/systemd/system \
    || fail "创建目录失败"

install -m 755 "$SRC_DIR/files/usr/local/sbin/hnu-campus" \
    /usr/local/sbin/hnu-campus || fail "安装主脚本失败"
install -m 644 "$SRC_DIR/files/usr/local/share/hnu-campus/common.sh" \
    /usr/local/share/hnu-campus/common.sh || fail "安装 common.sh 失败"
install -m 644 "$SRC_DIR/files/etc/systemd/system/hnu-campus.service" \
    /etc/systemd/system/hnu-campus.service || fail "安装 systemd 单元失败"

if [ -d /etc/NetworkManager/dispatcher.d ]; then
    install -m 755 -o root -g root \
        "$SRC_DIR/files/etc/NetworkManager/dispatcher.d/90-hnu-campus" \
        /etc/NetworkManager/dispatcher.d/90-hnu-campus \
        || fail "安装 NetworkManager dispatcher 失败"
    say "已安装 NetworkManager 网卡事件钩子"
fi

if [ -f /etc/hnu-campus.conf ]; then
    chmod 600 /etc/hnu-campus.conf || fail "无法设置配置文件权限"
    say "保留已有配置: /etc/hnu-campus.conf"
else
    install -m 600 "$SRC_DIR/config/hnu-campus.conf.example" \
        /etc/hnu-campus.conf || fail "生成配置文件失败"
    say "已生成配置: /etc/hnu-campus.conf"
fi

if ! command -v curl >/dev/null 2>&1 \
    && ! command -v wget >/dev/null 2>&1 \
    && ! command -v uclient-fetch >/dev/null 2>&1
then
    say "警告: 没有找到 curl 或 wget，认证无法发送请求。请安装 curl。"
fi

systemctl daemon-reload || fail "systemd daemon-reload 失败"
systemctl enable --now hnu-campus.service >/dev/null 2>&1 || true

say ""
say "安装完成。"
say ""
if grep -q -e '你的学号' -e '你的统一身份认证密码' /etc/hnu-campus.conf 2>/dev/null; then
    say "配置仍是示例，服务会在后台等待配置。请执行："
else
    say "如果账号密码已经填好，服务已启动。请执行："
fi
say "  sudo vi /etc/hnu-campus.conf"
say "  sudo chmod 600 /etc/hnu-campus.conf"
say "  sudo systemctl restart hnu-campus"
say ""
say "检查请求（密码会打码，不会发送登录）："
say "  sudo hnu-campus test"
say ""
say "立即认证并查看结果："
say "  sudo hnu-campus check -v"
say ""
say "查看状态、日志和开机自启："
say "  hnu-campus status"
say "  sudo journalctl -u hnu-campus -f"
say "  tail -n 30 /var/log/hnu-campus.log"
say "  systemctl is-enabled hnu-campus"
