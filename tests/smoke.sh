#!/bin/sh

set -u

ROOT=$(CDPATH= cd "$(dirname "$0")/.." 2>/dev/null && pwd)
COMMON="$ROOT/files/usr/share/hnu-campus/common.sh"
MAIN="$ROOT/files/usr/sbin/hnu-campus"

TMP=$(mktemp -d "${TMPDIR:-/tmp}/hnu-campus-test.XXXXXX") || exit 1
trap 'rm -rf "$TMP"' 0 1 2 15

BIN="$TMP/bin"
RUN="$TMP/run"
CONF="$TMP/hnu-campus.conf"
DIS="$TMP/hnu-campus.disabled"
LOG="$TMP/hnu-campus.log"
mkdir -p "$BIN" "$RUN"

PASS=0
FAIL=0

ok() {
    PASS=$((PASS + 1))
}

bad() {
    FAIL=$((FAIL + 1))
    printf 'FAIL: %s\n' "$*" >&2
}

assert_eq() {
    _ae_name=$1
    _ae_got=$2
    _ae_want=$3
    if [ "$_ae_got" = "$_ae_want" ]; then
        ok
    else
        bad "$_ae_name: got [$_ae_got], want [$_ae_want]"
    fi
}

assert_contains() {
    _ac_name=$1
    _ac_file=$2
    _ac_needle=$3
    if grep -qF -- "$_ac_needle" "$_ac_file" 2>/dev/null; then
        ok
    else
        bad "$_ac_name: missing [$_ac_needle]"
    fi
}

assert_not_contains() {
    _anc_name=$1
    _anc_file=$2
    _anc_needle=$3
    if grep -qF -- "$_anc_needle" "$_anc_file" 2>/dev/null; then
        bad "$_anc_name: unexpected [$_anc_needle]"
    else
        ok
    fi
}

. "$COMMON"

assert_eq 'urlencode basic' "$(urlencode ',1,20230001@telecom')" '%2C1%2C20230001%40telecom'
assert_eq 'urlencode password' "$(urlencode 'p@ss&word=1')" 'p%40ss%26word%3D1'
assert_eq 'urlencode space' "$(urlencode 'a b')" 'a%20b'
assert_eq 'urlencode percent' "$(urlencode '100%')" '100%25'

assert_eq 'jsonp payload' "$(jsonp_payload 'dr1003({"result":1,"msg":"ok"});')" '{"result":1,"msg":"ok"}'
assert_eq 'jsonp plain json' "$(jsonp_payload '{"result":1}')" '{"result":1}'

assert_eq 'json result number' "$(json_get_number '{"result":1,"ret_code":0}' result)" '1'
assert_eq 'json result string' "$(json_get_string '{"result":"1"}' result)" '1'
assert_eq 'json msg' "$(json_get_string '{"msg":"认证成功"}' msg)" '认证成功'

assert_eq 'classify success' "$(classify_response 'dr1003({"result":1,"msg":"Portal协议认证成功！","ret_code":0});')" 'success'
assert_eq 'classify success string' "$(classify_response 'dr1003({"result":"1","msg":"ok"});')" 'success'
assert_eq 'classify online' "$(classify_response 'dr1003({"result":0,"msg":"您已在线，请勿重复登录"});')" 'online'
assert_eq 'classify ldap' "$(classify_response 'dr1003({"result":0,"msg":"错误码：ldap auth error 您输入的学号或工号有误或密码错误。"});')" 'credentials'
assert_eq 'classify limit' "$(classify_response 'dr1003({"result":0,"msg":"设备数已达上限"});')" 'limited'
assert_eq 'classify blocked' "$(classify_response 'dr1003({"result":0,"msg":"账号已冻结"});')" 'blocked'
assert_eq 'classify config' "$(classify_response 'jsonpReturn({"code":0,"msg":"404 eportal action login not found"});')" 'config'
assert_eq 'classify empty' "$(classify_response '')" 'transient'
assert_eq 'classify unknown' "$(classify_response 'dr1003({"result":0,"msg":"奇怪","ret_code":9});')" 'unknown'

assert_eq 'valid ipv4' "$(valid_ipv4 '10.68.1.23' && echo yes || echo no)" 'yes'
assert_eq 'invalid ipv4 range' "$(valid_ipv4 '10.68.1.256' && echo yes || echo no)" 'no'
assert_eq 'invalid ipv4 short' "$(valid_ipv4 '10.68.1' && echo yes || echo no)" 'no'
assert_eq 'valid host' "$(valid_host '10.2.68.30' && echo yes || echo no)" 'yes'
assert_eq 'invalid host' "$(valid_host '10.2.68.30/path' && echo yes || echo no)" 'no'
assert_eq 'valid iface' "$(valid_iface 'wan' && echo yes || echo no)" 'yes'
assert_eq 'invalid iface' "$(valid_iface 'wan;reboot' && echo yes || echo no)" 'no'
assert_eq 'mask url' "$(mask_password_url 'http://x/login?user_account=a&user_password=secret&v=1')" 'http://x/login?user_account=a&user_password=****&v=1'

cat > "$BIN/curl" <<'EOF'
#!/bin/sh
if [ "${MOCK_FAIL:-0}" = 1 ]; then
    exit 7
fi

url=''
for arg in "$@"; do
    url=$arg
done

case "$url" in
    *generate_204*)
        if [ "${MOCK_STATE:-online}" = online ]; then
            exit 0
        fi
        printf '%s' '<html>login</html>'
        ;;
    *success.txt*)
        if [ "${MOCK_STATE:-online}" = online ]; then
            printf '%s' 'success'
        else
            printf '%s' '<html>login</html>'
        fi
        ;;
    *connecttest.txt*)
        if [ "${MOCK_STATE:-online}" = online ]; then
            printf '%s' 'Microsoft Connect Test'
        else
            printf '%s' '<html>login</html>'
        fi
        ;;
    *hotspot-detect.html*)
        if [ "${MOCK_STATE:-online}" = online ]; then
            printf '%s' '<HTML><HEAD><TITLE>Success</TITLE></HEAD></HTML>'
        else
            printf '%s' '<html>login</html>'
        fi
        ;;
    *eportal/portal/login*)
        if [ -f "${MOCK_DIR:-/tmp}/login-response" ]; then
            cat "${MOCK_DIR:-/tmp}/login-response"
        else
            printf '%s' 'dr1003({"result":1,"msg":"Portal协议认证成功！","ret_code":0});'
        fi
        ;;
    *eportal/portal/logout*)
        if [ -f "${MOCK_DIR:-/tmp}/logout-response" ]; then
            cat "${MOCK_DIR:-/tmp}/logout-response"
        else
            printf '%s' 'dr1003({"result":1,"msg":"注销成功","ret_code":0});'
        fi
        ;;
    *eportal/*)
        printf '%s' '<html>EPortal</html>'
        ;;
    *)
        exit 7
        ;;
esac
EOF
chmod 755 "$BIN/curl"

cat > "$BIN/logger" <<'EOF'
#!/bin/sh
exit 0
EOF
chmod 755 "$BIN/logger"

cat > "$CONF" <<EOF
ENABLED=1
USERNAME='20230001'
PASSWORD='p@ss&word=1'
ACCOUNT_PREFIX=',1,'
ISP_SUFFIX=''
PORTAL_HOST='10.2.68.30'
PORTAL_PORT='801'
WAN_IF='wan'
WAN_IP='10.68.1.23'
USER_MAC='000000000000'
CHECK_INTERVAL='1'
OFFLINE_CONFIRM='1'
RETRY_BASE='1'
RETRY_MAX='2'
AUTH_COOLDOWN='1'
LIMIT_COOLDOWN='1'
BLOCKED_COOLDOWN='1'
FORCE_RELOGIN_HOURS='0'
HTTP_TIMEOUT='2'
HTTP_CONNECT_TIMEOUT='1'
LOG_FILE='$LOG'
LOG_MAX_KB='256'
EOF

run_hnu() {
    HNU_CAMPUS_CONFIG="$CONF" \
    HNU_CAMPUS_RUNTIME="$RUN" \
    HNU_CAMPUS_DISABLE="$DIS" \
    HNU_CAMPUS_COMMON="$COMMON" \
    HNU_CAMPUS_NO_NETWORK="${HNU_CAMPUS_NO_NETWORK:-0}" \
    MOCK_DIR="$TMP" \
    MOCK_STATE="${MOCK_STATE:-online}" \
    MOCK_FAIL="${MOCK_FAIL:-0}" \
    PATH="$BIN:$PATH" \
    "$MAIN" "$@"
}

: > "$LOG"
MOCK_STATE=online HNU_CAMPUS_NO_NETWORK=0 run_hnu test > "$TMP/test.out" 2>&1
assert_contains 'test masks password' "$TMP/test.out" 'user_password=****'
assert_contains 'test encodes account' "$TMP/test.out" '%2C1%2C20230001'
assert_contains 'test detects wan ip' "$TMP/test.out" 'WAN IP: 10.68.1.23'

: > "$LOG"
MOCK_STATE=online run_hnu check > "$TMP/online.out" 2>&1
assert_eq 'online check exit' "$?" '0'
assert_not_contains 'online check skips login' "$LOG" '认证成功'

: > "$LOG"
MOCK_STATE=offline run_hnu check > "$TMP/offline.out" 2>&1
assert_eq 'offline check exit' "$?" '0'
assert_contains 'offline check logs in' "$LOG" '认证成功'

: > "$LOG"
MOCK_STATE=offline MOCK_FAIL=1 run_hnu check > "$TMP/transport.out" 2>&1
assert_eq 'transport failure exit' "$?" '1'
assert_contains 'transport failure message' "$LOG" '门户不可达'
unset MOCK_FAIL

printf '%s' 'dr1003({"result":0,"msg":"错误码：ldap auth error 您输入的学号或工号有误或密码错误。"});' > "$TMP/login-response"
: > "$LOG"
MOCK_STATE=offline run_hnu login > "$TMP/cred.out" 2>&1
assert_eq 'credential failure exit' "$?" '3'
assert_contains 'credential failure message' "$LOG" '学号或密码错误'

: > "$LOG"
MOCK_STATE=online run_hnu login > "$TMP/cred-online.out" 2>&1
assert_eq 'explicit login reports credential failure while online' "$?" '3'

printf '%s' 'dr1003({"result":0,"msg":"设备数已达上限"});' > "$TMP/login-response"
: > "$LOG"
MOCK_STATE=offline run_hnu login > "$TMP/limit.out" 2>&1
assert_eq 'limit failure exit' "$?" '4'
assert_contains 'limit failure message' "$LOG" '设备数'

: > "$LOG"
MOCK_STATE=offline run_hnu logout > "$TMP/logout.out" 2>&1
assert_eq 'logout exit' "$?" '0'
assert_contains 'logout message' "$LOG" '注销成功'

: > "$LOG"
HNU_CAMPUS_NO_NETWORK=1 run_hnu status > "$TMP/status.out" 2>&1
assert_contains 'status wan ip' "$TMP/status.out" 'WAN IP: 10.68.1.23'
assert_contains 'status account mask' "$TMP/status.out" '2023****'

printf 'passed=%s failed=%s\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
