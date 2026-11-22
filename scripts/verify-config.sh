#!/usr/bin/env bash
# 校验合并后的 .config：容器必需项在不在，paranoid network 关没关
# 用法: verify-config.sh <out/.config>
set -uo pipefail
CFG=${1:?用法: verify-config.sh <path/to/.config>}
[ -f "$CFG" ] || { echo "找不到 $CFG"; exit 2; }

# 同一个符号可能出现多行（后出现的生效），统一取最后一行
last_of() { grep -E "^(# )?${1}(=| is not set)" "$CFG" | tail -1; }

REQUIRED="
CONFIG_USER_NS
CONFIG_PID_NS
CONFIG_IPC_NS
CONFIG_CGROUP_DEVICE
CONFIG_NAMESPACES
CONFIG_NET_NS
CONFIG_UTS_NS
CONFIG_CGROUPS
CONFIG_CGROUP_SCHED
CONFIG_CPUSETS
CONFIG_MEMCG
CONFIG_OVERLAY_FS
CONFIG_VETH
CONFIG_BRIDGE
CONFIG_NF_NAT
CONFIG_IP_NF_TARGET_MASQUERADE
CONFIG_SECCOMP_FILTER
CONFIG_TUN
"

miss=0
for k in $REQUIRED; do
  line=$(last_of "$k")
  case "$line" in
    "$k=y"|"$k=m") echo "  OK   $line" ;;
    *) echo "  FAIL $k  ->  ${line:-（符号不存在）}"; miss=$((miss+1)) ;;
  esac
done

par=$(last_of CONFIG_ANDROID_PARANOID_NETWORK)
case "$par" in
  CONFIG_ANDROID_PARANOID_NETWORK=y) par_on=1 ;; *) par_on=0 ;; esac
if [ "$par_on" = 1 ]; then
  echo "  FAIL CONFIG_ANDROID_PARANOID_NETWORK 还是 =y（容器内网络会被拦）"
  miss=$((miss+1))
else
  echo "  OK   CONFIG_ANDROID_PARANOID_NETWORK 已关闭"
fi

LOCALV=$(grep -m1 '^CONFIG_LOCALVERSION=' "$CFG" | cut -d'"' -f2)
echo "  INFO CONFIG_LOCALVERSION=\"$LOCALV\"   目标 vermagic: 4.19.157-perf+"

if [ "$miss" -gt 0 ]; then
  echo
  echo "$miss 项没通过。多数是依赖没满足（USER_NS 依赖 NAMESPACES 之类），"
  echo "或者被 base config 后面的行覆盖。"
  exit 1
fi
echo
echo "配置检查通过。"
