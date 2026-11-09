#!/bin/sh

LC_ALL=C
export LC_ALL

urlencode() {
    printf '%s' "$1" | awk '
        BEGIN {
            for (i = 1; i < 256; i++) {
                ord[sprintf("%c", i)] = i
            }
        }
        {
            for (i = 1; i <= length($0); i++) {
                c = substr($0, i, 1)
                if (c ~ /[A-Za-z0-9._~-]/) {
                    printf "%s", c
                } else {
                    printf "%%%02X", ord[c]
                }
            }
        }
    '
}

jsonp_payload() {
    _jp_body=$1
    _jp_body=${_jp_body#*(}
    _jp_body=${_jp_body%%)*}
    printf '%s' "$_jp_body"
}

json_get_string() {
    printf '%s' "$1" | sed -n "s/.*\"$2\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p" | head -n 1
}

json_get_number() {
    printf '%s' "$1" | sed -n "s/.*\"$2\"[[:space:]]*:[[:space:]]*\(-\{0,1\}[0-9][0-9]*\).*/\1/p" | head -n 1
}

classify_response() {
    _cr_body=$1

    if [ -z "$_cr_body" ]; then
        echo transient
        return 0
    fi

    case "$_cr_body" in
        *"404 Not Found"*|*"系统发生错误"*)
            echo config
            return 0
            ;;
    esac

    _cr_payload=$(jsonp_payload "$_cr_body")
    _cr_result=$(json_get_number "$_cr_payload" result)
    _cr_result_s=$(json_get_string "$_cr_payload" result)
    _cr_msg=$(json_get_string "$_cr_payload" msg)

    if [ "$_cr_result" = "1" ] || [ "$_cr_result_s" = "1" ]; then
        echo success
        return 0
    fi

    case "$_cr_body" in
        *认证成功*|*登录成功*)
            echo success
            return 0
            ;;
        *已经在线*|*已在线*)
            echo online
            return 0
            ;;
    esac

    case "$_cr_msg" in
        *ldap*|*LDAP*|*Ldap*|*学号或工号有误*|*密码错误*|*密码不正确*|*密码有误*|*账号或密码错误*|*用户不存在*|*账号不存在*|*未开户*)
            echo credentials
            ;;
        *已经在线*|*已在线*|*终端IP已在线*|*重复登录*)
            echo online
            ;;
        *设备数*|*终端数*|*数量*|*超过*|*上限*|*限制*|*绑定*|*其他终端*|*会话冲突*|*MAC*|*mac地址*)
            echo limited
            ;;
        *冻结*|*暂停*|*封禁*|*停机*|*欠费*|*锁定*|*禁用*|*销户*|*不允许*|*时段*)
            echo blocked
            ;;
        *认证成功*|*登录成功*|*已经成功*|*successlogin*)
            echo success
            ;;
        *繁忙*|*超时*|*失败*|*错误*|*异常*|*无法获取*)
            echo transient
            ;;
        *)
            case "$_cr_body" in
                *'"code":0'*'"msg":"404'*)
                    echo config
                    ;;
                *)
                    echo unknown
                    ;;
            esac
            ;;
    esac
}

valid_ipv4() {
    case "${1:-}" in
        ''|*[!0-9.]*)
            return 1
            ;;
    esac

    printf '%s' "$1" | awk -F. '
        NF != 4 { exit 1 }
        {
            for (i = 1; i <= 4; i++) {
                if ($i == "" || $i < 0 || $i > 255) exit 1
            }
        }
    '
}

valid_host() {
    case "${1:-}" in
        ''|-*|*[!A-Za-z0-9._-]*)
            return 1
            ;;
    esac
    return 0
}

valid_iface() {
    case "${1:-}" in
        ''|-*|*[!A-Za-z0-9_.-]*)
            return 1
            ;;
    esac
    return 0
}

is_uint() {
    case "${1:-}" in
        ''|*[!0-9]*)
            return 1
            ;;
    esac
    return 0
}

mask_password_url() {
    printf '%s' "$1" | sed 's/\([?&]user_password=\)[^&]*/\1****/'
}

mask_account() {
    case "${1:-}" in
        '')
            printf '%s' '未配置'
            ;;
        *)
            printf '%s****' "$(printf '%s' "$1" | cut -c 1-4)"
            ;;
    esac
}
