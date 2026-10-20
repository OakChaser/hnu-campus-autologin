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

[ "$(id -u)" = 0 ] || fail "请用 root 运行此安装脚本"
[ -f /etc/rc.common ] || fail "没有检测到 OpenWrt（缺少 /etc/rc.common）"
[ -d "$SRC_DIR/files" ] || fail "找不到项目文件目录: $SRC_DIR/files"
[ -f "$SRC_DIR/config/hnu-campus.conf.example" ] || fail "找不到配置模板"

mkdir -p /usr/share/hnu-campus /etc/init.d /etc/hotplug.d/iface || fail "创建目录失败"

cp "$SRC_DIR/files/usr/sbin/hnu-campus" /usr/sbin/hnu-campus || fail "复制主脚本失败"
cp "$SRC_DIR/files/usr/share/hnu-campus/common.sh" /usr/share/hnu-campus/common.sh || fail "复制 common.sh 失败"
cp "$SRC_DIR/files/etc/init.d/hnu-campus" /etc/init.d/hnu-campus || fail "复制 init 脚本失败"
cp "$SRC_DIR/files/etc/hotplug.d/iface/90-hnu-campus" /etc/hotplug.d/iface/90-hnu-campus || fail "复制 hotplug 脚本失败"

chmod 755 /usr/sbin/hnu-campus /etc/init.d/hnu-campus /etc/hotplug.d/iface/90-hnu-campus || fail "无法设置脚本权限"
chmod 644 /usr/share/hnu-campus/common.sh || fail "无法设置公共库权限"

if [ -f /etc/hnu-campus.conf ]; then
    chmod 600 /etc/hnu-campus.conf || fail "无法设置配置文件权限"
    say "保留已有配置: /etc/hnu-campus.conf"
else
    cp "$SRC_DIR/config/hnu-campus.conf.example" /etc/hnu-campus.conf || fail "复制配置模板失败"
    chmod 600 /etc/hnu-campus.conf || fail "无法设置配置文件权限"
    say "已生成配置: /etc/hnu-campus.conf"
fi

touch /etc/sysupgrade.conf 2>/dev/null || true
for _file in \
    /usr/sbin/hnu-campus \
    /usr/share/hnu-campus/common.sh \
    /etc/init.d/hnu-campus \
    /etc/hotplug.d/iface/90-hnu-campus \
    /etc/hnu-campus.conf
do
    if ! grep -qxF "$_file" /etc/sysupgrade.conf 2>/dev/null; then
        printf '%s\n' "$_file" >> /etc/sysupgrade.conf
    fi
done

if ! command -v curl >/dev/null 2>&1 \
    && ! command -v wget >/dev/null 2>&1 \
    && ! command -v uclient-fetch >/dev/null 2>&1
then
    say "警告: 没有找到 curl、wget 或 uclient-fetch，认证无法发送请求。"
fi

/etc/init.d/hnu-campus enable >/dev/null 2>&1 || true
/etc/init.d/hnu-campus restart >/dev/null 2>&1 || true

say ""
say "安装完成。"
say ""
if grep -q -e '你的学号' -e '你的统一身份认证密码' /etc/hnu-campus.conf 2>/dev/null; then
    say "配置仍是示例，服务会在后台等待配置。请执行："
else
    say "如果账号密码已经填好，服务已启动。请执行："
fi
say "  vi /etc/hnu-campus.conf"
say "  chmod 600 /etc/hnu-campus.conf"
say "  /etc/init.d/hnu-campus restart"
say ""
say "检查请求（密码会打码，不会发送登录）："
say "  /usr/sbin/hnu-campus test"
say ""
say "立即认证并查看结果："
say "  /usr/sbin/hnu-campus check -v"
say ""
say "查看状态和日志："
say "  /usr/sbin/hnu-campus status"
say "  tail -n 30 /etc/hnu-campus.log"
