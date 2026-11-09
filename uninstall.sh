#!/bin/sh

set -u

PURGE=0
if [ "${1:-}" = "--purge" ]; then
    PURGE=1
fi

[ "$(id -u)" = 0 ] || {
    printf 'uninstall: 请用 root 运行（sudo ./uninstall.sh）\n' >&2
    exit 1
}

systemctl stop hnu-campus.service >/dev/null 2>&1 || true
systemctl disable hnu-campus.service >/dev/null 2>&1 || true

rm -f /usr/local/sbin/hnu-campus
rm -f /usr/local/share/hnu-campus/common.sh
rmdir /usr/local/share/hnu-campus 2>/dev/null || true
rm -f /etc/systemd/system/hnu-campus.service
rm -f /etc/NetworkManager/dispatcher.d/90-hnu-campus
rm -rf /run/hnu-campus

systemctl daemon-reload >/dev/null 2>&1 || true

if [ "$PURGE" = 1 ]; then
    rm -f /etc/hnu-campus.conf /etc/hnu-campus.disabled \
        /var/log/hnu-campus.log /var/log/hnu-campus.log.tmp
    printf '已卸载，并删除配置与日志。\n'
else
    rm -f /etc/hnu-campus.disabled
    printf '已卸载。配置文件保留在 /etc/hnu-campus.conf，日志保留在 /var/log/hnu-campus.log。\n'
    printf '如需连配置、日志一起删除：sudo %s --purge\n' "$0"
fi
