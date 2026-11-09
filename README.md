# HNU Campus Autologin（Debian / systemd）

湖南大学校园网 Dr.COM ePortal 自动认证脚本，面向 **Debian 13 (trixie)** 及使用 systemd 的 Linux 主机（含 Raspberry Pi）。

让树莓派、服务器或始终在线的设备用自己的学号和统一身份认证密码完成网页门户登录，设备重启、断网恢复后由 systemd 自动拉起并继续巡检。

> 本项目只复用你自己的账号完成正常认证，不绕过计费、限速或设备数量限制，也不提供多设备检测规避。请遵守学校网络管理规定。

## 分支说明

- `systemd`：Debian / systemd 版本，默认分支。
- `openwrt`：原 OpenWrt / ImmortalWrt 版本（procd、hotplug、`/etc/init.d`）。

## 适用环境

- Debian 13 (trixie)，或其他使用 systemd 的现代 Debian 系发行版
- Raspberry Pi 等 arm64 / x86_64 主机
- 校园网网线接入一个网络接口（通常为 `eth0`），由 NetworkManager 或 systemd-networkd 通过 DHCP 获取 `10.x.x.x` 地址
- 湖南大学当前 Dr.COM ePortal 网页认证
- 账号：`,1,学号`，密码：统一身份认证密码
- 默认校园网出口；如使用运营商出口，可配置 `@telecom`、`@cmcc`、`@unicom`
- 需要 `curl`（推荐）或 `wget`，无需 Python 或 bash

拓扑应当是：

```text
校园网网线 -> 主机 eth0
Wi-Fi / 其他内网 -> 主机其它接口
```

脚本默认根据到门户的路由自动识别校园网接口与源 IPv4；主机存在多个默认路由时，建议在配置中显式指定 `WAN_IF='eth0'`。

## 特性

- systemd 常驻巡检，开机自启，异常自动重启
- NetworkManager 网卡事件钩子：接口 up / DHCP 变化时立即触发一次检查
- 自动探测在线状态，在线时不重复登录
- 自动获取校园网 IPv4，认证请求中的 `wlan_user_ip` 不需要手填
- 门户不可达时不会盲目提交账号密码
- 区分密码错误、设备数限制、账号冻结、门户异常等响应，分别冷却
- 文件锁避免服务、网卡事件和手动命令同时登录
- 持久日志 + syslog，日志自动轮转
- 配置与脚本分离，密码只保存在 `/etc/hnu-campus.conf`（权限 600）
- systemd 沙箱加固：`ProtectSystem=strict`、`NoNewPrivileges` 等
- 支持 `test` 脱敏查看请求、`status` 查看状态、`disable` 临时暂停

## 安装

把仓库传到主机，例如：

```sh
scp -r hnu-campus-autologin oakchaser@192.168.51.4:~
ssh oakchaser@192.168.51.4
```

在主机上执行：

```sh
cd ~/hnu-campus-autologin
git switch systemd
sudo ./install.sh
```

安装脚本会：

- 安装主脚本到 `/usr/local/sbin/hnu-campus`
- 安装公共库到 `/usr/local/share/hnu-campus/common.sh`
- 安装 systemd 单元 `/etc/systemd/system/hnu-campus.service`
- 存在 NetworkManager 时安装 `/etc/NetworkManager/dispatcher.d/90-hnu-campus`
- 首次安装时生成 `/etc/hnu-campus.conf`（权限 600）
- `systemctl daemon-reload` 并注册开机自启、启动服务

## 配置

编辑：

```sh
sudo vi /etc/hnu-campus.conf
sudo chmod 600 /etc/hnu-campus.conf
```

至少填写：

```sh
USERNAME='你的学号'
PASSWORD='你的统一身份认证密码'
```

密码建议使用 **单引号**，这样 `$`、反引号、反斜杠等字符不会被 shell 解释。如果密码本身包含单引号，改用双引号，例如：

```sh
PASSWORD="a'b"
```

常用配置：

| 配置项 | 默认值 | 说明 |
|---|---|---|
| `ENABLED` | `1` | 总开关，`0` 为永久停用 |
| `USERNAME` | 空 | 学号，不含 `,1,` |
| `PASSWORD` | 空 | 统一身份认证密码 |
| `ACCOUNT_PREFIX` | `,1,` | HNU 当前账号前缀，通常不要改 |
| `ISP_SUFFIX` | 空 | 校园网出口留空；电信填 `@telecom` |
| `PORTAL_HOST` | `10.2.68.30` | 认证门户地址 |
| `PORTAL_PORT` | `801` | 认证门户端口 |
| `WAN_IF` | 空 | 留空自动识别；多网卡建议填 `eth0` |
| `WAN_IP` | 空 | 留空自动获取；自动识别错误时才手填 |
| `USER_MAC` | `000000000000` | 与 HNU 网页请求一致；可改为 `auto` |
| `FORCE_RELOGIN_HOURS` | `6` | 每 N 小时兜底重认证一次；`0` 关闭 |
| `CHECK_URLS` | 多个探测地址 | 任一符合预期即认为在线 |
| `LOG_FILE` | `/var/log/hnu-campus.log` | 持久日志路径 |

修改配置后重启服务：

```sh
sudo systemctl restart hnu-campus
```

## 使用

先查看即将发送的请求（密码自动打码，不会真的登录）：

```sh
sudo hnu-campus test
```

确认 `user_account` 中出现 `%2C1%2C学号`，且 `WAN IP` 是校园网分配的地址。

立即认证并查看详细过程：

```sh
sudo hnu-campus check -v
```

成功时日志中会出现：

```text
认证成功（IP=10.x.x.x，Portal协议认证成功！）
```

查看状态和最近日志：

```sh
hnu-campus status
sudo journalctl -u hnu-campus -f
tail -n 30 /var/log/hnu-campus.log
```

常用命令：

```sh
sudo hnu-campus check        # 检查一次，离线或到达兜底时间时登录
sudo hnu-campus login        # 强制登录一次
sudo hnu-campus logout       # 尝试注销当前 WAN IP 的会话
hnu-campus status            # 查看服务、在线状态、WAN IP 和最近日志（无需 root）
sudo hnu-campus test         # 打印脱敏请求，不发送
sudo hnu-campus enable       # 恢复自动认证
sudo hnu-campus disable      # 暂停自动认证，不注销当前会话
```

服务管理：

```sh
sudo systemctl status hnu-campus
sudo systemctl restart hnu-campus
sudo systemctl stop hnu-campus
sudo systemctl disable hnu-campus      # 取消开机自启
systemctl is-enabled hnu-campus        # 查看是否开机自启
```

临时换设备时：

```sh
sudo hnu-campus disable
sudo hnu-campus logout
# 在另一台设备上登录
# 回到本机后恢复：
sudo hnu-campus enable
```

## 工作方式

1. 读取配置并校验账号、门户地址、接口参数。
2. 用多个 HTTP 探测点判断是否真正在线；连续失败达到 `OFFLINE_CONFIRM` 次才认为离线。
3. 在线时只记录状态，不重复登录；每 `FORCE_RELOGIN_HOURS` 小时做一次幂等兜底认证。
4. 离线时优先使用配置的 `WAN_IF`，否则通过 `ip route get <门户>` 和默认路由找到校园网接口与 IPv4。
5. 确认门户可达后，按 HNU 当前参数发送登录请求，密码和账号由脚本做 URL 编码。
6. 解析 `dr1003({...})` 响应，按结果进入不同冷却：
   - 密码错误：30 分钟
   - 设备数 / MAC 绑定限制：10 分钟
   - 账号冻结 / 欠费 / 时段限制：30 分钟
   - 门户接口异常：10 分钟
   - 普通网络异常：指数退避，最长 10 分钟
7. systemd 常驻巡检；NetworkManager 网卡 up / DHCP 变化时 dispatcher 额外触发一次检查。

认证参数对应：

```text
callback=dr1003
login_method=1
user_account=,1,学号
user_password=URL 编码后的密码
wlan_user_ip=校园网 IPv4
wlan_user_ipv6=
wlan_user_mac=000000000000
wlan_ac_ip=
wlan_ac_name=
jsVersion=4.2.1
terminal_type=2
lang=zh-cn
v=2012
```

## 排查

### 配置文件仍是示例

日志或 `status` 提示 `USERNAME 不能为空`、`PASSWORD 不能为空`：

```sh
sudo vi /etc/hnu-campus.conf
sudo systemctl restart hnu-campus
```

### 取不到 WAN IP / 选错网卡

```sh
ip -4 addr
ip route get 10.2.68.30
ip route show default
```

确认网线插在预期接口且已 DHCP 成功。多网卡环境下显式指定：

```sh
WAN_IF='eth0'
```

如仍不正确，可临时填写：

```sh
WAN_IP='10.x.x.x'
```

### 门户不可达

```sh
curl -v http://10.2.68.30:801/eportal/
```

如果这里没有响应，脚本也不会提交账号密码。检查校园网是否要求先打开认证页、门户地址是否变更。

### 提示学号或密码错误

- 确认使用的是 **统一身份认证密码**，不是其他系统密码。
- 先在一台电脑的浏览器里手动登录，确认账号密码正确。
- 检查 `USERNAME` 是否只填了学号，不要自己再加 `,1,`。
- `ACCOUNT_PREFIX` 保持 `,1,`。
- 密码里有特殊字符时，确认配置使用了正确的引号。

### 提示设备数已达上限 / MAC 绑定

把其他已经登录该账号的设备下线，等待几分钟后重试。不要把账号分享给他人。某些情况下把 `USER_MAC` 改为 `auto` 可以匹配接口 MAC：

```sh
USER_MAC='auto'
```

### 提示已经在线

这是正常成功状态，说明该 IP 已经有有效会话，脚本不会重复建立会话。

### 服务启动了但没有认证

```sh
hnu-campus status
sudo journalctl -u hnu-campus -n 100 --no-pager
tail -n 50 /var/log/hnu-campus.log
```

检查是否执行过 `hnu-campus disable`，或配置中 `ENABLED=0`。

### 认证请求失败

```sh
command -v curl
command -v wget
curl -V
```

至少需要一个。Debian 建议安装 `curl`：

```sh
sudo apt install curl
```

### 改了配置不生效

```sh
sudo systemctl restart hnu-campus
```

如果刚修好密码但还在冷却期，重启不一定立即重试。可以执行：

```sh
sudo hnu-campus login      # 忽略冷却，立即尝试一次
sudo hnu-campus enable     # 清除冷却并恢复自动认证
```

### 查看 systemd 沙箱是否拦截

```sh
sudo systemctl status hnu-campus
sudo systemd-analyze security hnu-campus.service
```

如果日志显示权限被拒绝，检查 `ReadWritePaths` 是否包含日志和运行时目录。

## 卸载

```sh
cd ~/hnu-campus-autologin
sudo ./uninstall.sh
```

保留配置和日志。连配置、日志一起删除：

```sh
sudo ./uninstall.sh --purge
```

## 安全说明

- `/etc/hnu-campus.conf` 含明文密码，必须保持 `600`。
- 不要提交真实配置、日志或带学号的截图到 GitHub。
- 日志里不会打印密码，但 `test` 会显示账号（密码已打码）；`status` 会显示打码账号。
- 建议只允许可信设备访问主机 SSH。
- 不要把账号提供给他人，不要用于商业共享或其他违反校规的用途。

## 限制

- 只适用于当前 HNU Dr.COM ePortal 网页认证，不适用于 PPPoE、802.1X、IPv6-only 或需要验证码 / 2FA 的场景。
- 主机必须直接接校园网接口；如果前面还有一层 NAT，`wlan_user_ip` 会不匹配。
- 学校修改门户地址、参数或认证协议后，脚本可能需要同步调整配置。
- 首次运行或每 `FORCE_RELOGIN_HOURS` 小时会做一次兜底认证。门户已在线时通常返回“已经在线”，不会重复建立会话。

## 开发与测试

本地静态检查和模拟测试（不访问真实门户、不需要 root）：

```sh
dash -n files/usr/local/sbin/hnu-campus
dash -n files/usr/local/share/hnu-campus/common.sh
sh tests/smoke.sh
systemd-analyze verify files/etc/systemd/system/hnu-campus.service
```

`tests/smoke.sh` 使用模拟 `curl` 和临时配置，覆盖：

- URL 编码
- JSONP / JSON 解析
- 成功、已在线、密码错误、设备限制、账号冻结、门户 404、未知响应分类
- IPv4、主机名、接口名校验
- 在线跳过登录、离线登录、密码错误退出码、注销、状态输出

手工验证（不写入系统、不使用 root）：

```sh
export HNU_CAMPUS_CONFIG=$PWD/tests/tmp/hnu-campus.conf
export HNU_CAMPUS_RUNTIME=$PWD/tests/tmp/run
export HNU_CAMPUS_NO_NETWORK=1
sh files/usr/local/sbin/hnu-campus status
```

真实登录需要你自己的账号密码，在主机上执行：

```sh
sudo hnu-campus test
sudo hnu-campus check -v
```

## License

MIT
