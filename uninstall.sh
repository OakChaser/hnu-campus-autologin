#!/bin/sh

set -u

PURGE=0
if [ "${1:-}" = "--purge" ]; then
    PURGE=1
fi

[ "$(id -u)" = 0 ] || {
    printf 'uninstall: 请用 root 运行\n' >&2
    exit 1
}

/etc/init.d/hnu-campus stop >/dev/null 2>&1 || true
/etc/init.d/hnu-campus disable >/dev/null 2>&1 || true

rm -f /usr/sbin/hnu-campus
rm -f /usr/share/hnu-campus/common.sh
rmdir /usr/share/hnu-campus 2>/dev/null || true
rm -f /etc/init.d/hnu-campus
rm -f /etc/hotplug.d/iface/90-hnu-campus
rm -f /tmp/hnu-campus/lock /tmp/hnu-campus/state /tmp/hnu-campus/retry-after \
    /tmp/hnu-campus/last-force /tmp/hnu-campus/last-success
rmdir /tmp/hnu-campus 2>/dev/null || true

if [ -f /etc/sysupgrade.conf ]; then
    grep -vxF \
        -e '/usr/sbin/hnu-campus' \
        -e '/usr/share/hnu-campus/common.sh' \
        -e '/etc/init.d/hnu-campus' \
        -e '/etc/hotplug.d/iface/90-hnu-campus' \
        -e '/etc/hnu-campus.conf' \
        /etc/sysupgrade.conf > /etc/sysupgrade.conf.tmp 2>/dev/null || true
    mv /etc/sysupgrade.conf.tmp /etc/sysupgrade.conf
fi

if [ "$PURGE" = 1 ]; then
    rm -f /etc/hnu-campus.conf /etc/hnu-campus.log /etc/hnu-campus.log.tmp \
        /etc/hnu-campus.disabled
    printf '已卸载，并删除配置与日志。\n'
else
    rm -f /etc/hnu-campus.disabled
    printf '已卸载。配置文件保留在 /etc/hnu-campus.conf，日志保留在 /etc/hnu-campus.log。\n'
    printf '如需连配置一起删除：%s --purge\n' "$0"
fi
