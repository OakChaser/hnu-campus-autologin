# HNU Campus Autologin

湖南大学校园网 Dr.COM ePortal 自动认证脚本，面向 **OpenWrt / ImmortalWrt** 路由器。

让路由器用自己的学号和统一身份认证密码完成网页门户登录，宿舍里的电脑、手机、平板通过路由器上网，不再需要每台设备单独打开认证页。

> 本项目只复用你自己的账号完成正常认证，不绕过计费、限速或设备数量限制，也不提供多设备检测规避。请遵守学校网络管理规定。

## 适用环境

- OpenWrt 21.02 及以上（建议 23.05 / 24.10）
- 校园网网线插在路由器 **WAN 口**，WAN 通过 DHCP 获取 `10.68.x.x` 地址
- 湖南大学当前 Dr.COM ePortal 网页认证
- 账号：`,1,学号`，密码：统一身份认证密码
- 默认校园网出口；如使用运营商出口，可配置 `@telecom`、`@cmcc`、`@unicom`
- 不需要 LuCI，也不需要 Python、bash 或额外软件包

拓扑应当是：

```text
校园网网线 -> OpenWrt WAN
电脑 / 手机 -> OpenWrt LAN 或 WiFi
```

不要在路由器和另一台设备上同时用同一个账号分别登录；如果学校限制单会话，两边可能互相挤下线。

脚本优先使用 `curl`，没有 `curl` 时自动使用 OpenWrt 自带的 `wget` / `uclient-fetch`。

## 特性

- 自动探测在线状态，在线时不重复登录
- 自动获取 WAN IPv4，认证请求中的 `wlan_user_ip` 不需要手填
- 门户不可达时不会盲目提交账号密码
- 区分密码错误、设备数限制、账号冻结、门户异常等响应，分别冷却
- procd 常驻巡检，WAN `ifup` 时由 hotplug 立即触发一次检查
- 文件锁避免定时任务、hotplug 和手动命令同时登录
- 持久日志 + syslog，日志自动轮转
- 配置与脚本分离，密码只保存在 `/etc/hnu-campus.conf`（权限 600）
- 支持 `test` 脱敏查看请求、`status` 查看状态、`disable` 临时暂停

## 安装

把整个目录传到路由器，例如：

```sh
scp -r hnu-campus-autologin root@192.168.1.1:/tmp/
ssh root@192.168.1.1
```

在路由器上执行：

```sh
sh /tmp/hnu-campus-autologin/install.sh
```

安装脚本会：

- 安装主脚本到 `/usr/sbin/hnu-campus`
- 安装公共库到 `/usr/share/hnu-campus/common.sh`
- 安装 procd 服务和 WAN hotplug 脚本
- 首次安装时生成 `/etc/hnu-campus.conf`
- 把相关文件写入 `/etc/sysupgrade.conf`
- 注册开机自启并启动服务

## 配置

编辑：

```sh
vi /etc/hnu-campus.conf
chmod 600 /etc/hnu-campus.conf
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
| `WAN_IF` | `wan` | OpenWrt 逻辑 WAN 接口 |
| `WAN_IP` | 空 | 留空自动获取；自动识别错误时才手填 |
| `USER_MAC` | `000000000000` | 与 HNU 网页请求一致；可改为 `auto` |
| `FORCE_RELOGIN_HOURS` | `6` | 每 N 小时兜底重认证一次；`0` 关闭 |
| `CHECK_URLS` | 多个探测地址 | 任一符合预期即认为在线 |
| `LOG_FILE` | `/etc/hnu-campus.log` | 持久日志路径 |

修改配置后重启服务：

```sh
/etc/init.d/hnu-campus restart
```

## 使用

先查看即将发送的请求（密码自动打码，不会真的登录）：

```sh
hnu-campus test
```

确认 `user_account` 中出现 `%2C1%2C学号`，且 `WAN IP` 是 `10.68.x.x`。

立即认证并查看详细过程：

```sh
hnu-campus check -v
```

成功时日志中会出现：

```text
认证成功（IP=10.68.x.x，Portal协议认证成功！）
```

查看状态和最近日志：

```sh
hnu-campus status
tail -n 30 /etc/hnu-campus.log
logread | grep hnu-campus
```

常用命令：

```text
hnu-campus check        检查一次，离线或到达兜底时间时登录
hnu-campus login        强制登录一次
hnu-campus logout       尝试注销当前 WAN IP 的会话
hnu-campus status       查看服务、在线状态、WAN IP 和最近日志
hnu-campus test         打印脱敏请求，不发送
hnu-campus enable       恢复自动认证
hnu-campus disable      暂停自动认证，不注销当前会话
```

临时换设备时：

```sh
hnu-campus disable
hnu-campus logout
# 在另一台设备上登录
# 回到路由器后恢复：
hnu-campus enable
```

## 工作方式

1. 读取配置并校验账号、门户地址、WAN 参数。
2. 用多个 HTTP 探测点判断是否真正在线；连续失败达到 `OFFLINE_CONFIRM` 次才认为离线。
3. 在线时只记录状态，不重复登录；每 `FORCE_RELOGIN_HOURS` 小时做一次幂等兜底认证。
4. 离线时通过默认路由和 `ubus` / `ifstatus` / `ip addr` 自动找到 WAN IPv4。
5. 确认门户可达后，按 HNU 当前参数发送登录请求，密码和账号由脚本做 URL 编码。
6. 解析 `dr1003({...})` 响应，按结果进入不同冷却：
   - 密码错误：30 分钟
   - 设备数 / MAC 绑定限制：10 分钟
   - 账号冻结 / 欠费 / 时段限制：30 分钟
   - 门户接口异常：10 分钟
   - 普通网络异常：指数退避，最长 10 分钟
7. procd 常驻巡检；WAN `ifup` 时 hotplug 额外触发一次检查。

认证参数对应：

```text
callback=dr1003
login_method=1
user_account=,1,学号
user_password=URL 编码后的密码
wlan_user_ip=WAN IPv4
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

日志或 `status` 提示 `USERNAME 不能为空`、`PASSWORD 不能为空`，或 install 提示配置仍是示例：

```sh
vi /etc/hnu-campus.conf
/etc/init.d/hnu-campus restart
```

### 取不到 WAN IP

```sh
ip -4 addr
ip route show default
```

确认网线插在 WAN 口，且 WAN 已经 DHCP 成功。如果接口名不是 `wan`，修改 `WAN_IF`；如果自动识别仍不对，可以临时填写：

```sh
WAN_IP='10.68.x.x'
```

### 门户不可达

```sh
wget -q -O - http://10.2.68.30:801/eportal/ | head
```

如果这里没有响应，脚本也不会提交账号密码。检查校园网是否要求先打开认证页、门户地址是否变更。

### 提示学号或密码错误

- 确认使用的是 **统一身份认证密码**，不是其他系统密码。
- 先在一台电脑的浏览器里手动登录，确认账号密码正确。
- 检查 `USERNAME` 是否只填了学号，不要自己再加 `,1,`。
- `ACCOUNT_PREFIX` 保持 `,1,`。
- 密码里有特殊字符时，确认配置使用了正确的引号。

### 提示设备数已达上限 / MAC 绑定

把其他已经登录该账号的设备下线，等待几分钟后重试。不要把账号分享给他人。某些情况下把 `USER_MAC` 改为 `auto` 可以匹配路由器 WAN MAC：

```sh
USER_MAC='auto'
```

### 提示已经在线

这是正常成功状态，说明该 WAN IP 已经有有效会话，脚本不会重复建立会话。

### 服务启动了但没有认证

```sh
hnu-campus status
tail -n 50 /etc/hnu-campus.log
```

检查是否执行过 `hnu-campus disable`，或配置中 `ENABLED=0`。

### 认证请求失败

```sh
command -v curl
command -v wget
command -v uclient-fetch
```

至少需要一个。OpenWrt 通常自带 `wget` 或 `uclient-fetch`。

### 改了配置不生效

```sh
/etc/init.d/hnu-campus restart
```

如果刚修好密码但还在冷却期，重启不一定立即重试。可以执行：

```sh
hnu-campus login      # 忽略冷却，立即尝试一次
hnu-campus enable     # 清除冷却并恢复自动认证
```

`hnu-campus test` 会读取当前配置，可以用它快速确认请求。

### 升级固件后文件丢失

安装脚本已把文件加入 `/etc/sysupgrade.conf`。如果仍然丢失，重新运行 `install.sh` 即可。配置文件默认保留。

## 卸载

```sh
sh /tmp/hnu-campus-autologin/uninstall.sh
```

保留配置和日志。连配置、日志一起删除：

```sh
sh /tmp/hnu-campus-autologin/uninstall.sh --purge
```

## 安全说明

- `/etc/hnu-campus.conf` 含明文密码，必须保持 `600`。
- 不要提交真实配置、日志或带学号的截图到 GitHub。
- 日志里不会打印密码，但 `test` 会显示账号（密码已打码）；`status` 会显示打码账号。
- 建议只允许可信设备访问路由器管理界面和 SSH。
- 不要把账号提供给他人，不要用于商业共享或其他违反校规的用途。

## 限制

- 只适用于当前 HNU Dr.COM ePortal 网页认证，不适用于 PPPoE、802.1X、IPv6-only 或需要验证码 / 2FA 的场景。
- 路由器必须直接接校园网 WAN；如果路由器后面还有一层 NAT，`wlan_user_ip` 会不匹配。
- 学校修改门户地址、参数或认证协议后，脚本可能需要同步调整配置。
- 首次运行或每 `FORCE_RELOGIN_HOURS` 小时会做一次兜底认证。门户已在线时通常返回“已经在线”，不会重复建立会话。
- 本项目不保证学校的多设备检测策略，也不提供规避手段。

## 开发与测试

本地静态检查和模拟测试：

```sh
dash -n files/usr/sbin/hnu-campus
dash -n files/usr/share/hnu-campus/common.sh
sh tests/smoke.sh
```

`tests/smoke.sh` 使用模拟 `curl` 和配置，不访问真实门户，覆盖：

- URL 编码
- JSONP / JSON 解析
- 成功、已在线、密码错误、设备限制、账号冻结、门户 404、未知响应分类
- IPv4、主机名、接口名校验
- 在线跳过登录、离线登录、密码错误退出码、注销、状态输出

真实登录需要你自己的账号密码，在路由器上执行：

```sh
hnu-campus test
hnu-campus check -v
```

## 致谢

认证参数参考了社区公开的湖南大学门户登录记录。项目本身与学校、Dr.COM 无隶属关系。

## License

MIT
