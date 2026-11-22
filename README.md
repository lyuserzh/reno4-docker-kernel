# PDPM00 / Reno4 5G 带 Docker 支持的内核 —— 实测数据版

设备：PDPM00（SM7250 / lito），Android 12，机内 `4.19.157-perf+`
底本：`boot_Reno4_5G_4.19.157_stockcfg.img`（96MB 分区 dump）
参考包：`Reno4_5G_KSU_kernel_4.19.157.zip`（AnyKernel3）

## 一、两份文件拆出来的事实

| 项 | 实测值 |
|---|---|
| boot 头 | `ANDROID!`，header_version **2**，os 12.0.0，patch 2023-11 |
| pagesize / base | 0x1000 / 0x00000000 |
| offsets | kernel 0x8000，ramdisk 0x01000000，tags 0x100，dtb 0x01f00000 |
| boot 内 kernel | 38,873,104 字节，**未压缩**（裸 Image），`4.19.157-perf+ #6` |
| ramdisk | 1,006,310 字节 |
| dtb | 10,552,865 字节（多 dtb 打包在 boot 里） |
| AVB | 尾部有 `AVBf` footer，RSA4096 自签，`flags=0`（校验开启） |
| 原镜像大小 | 50,442,240 字节，分区 96MB |
| AK3 包里的 Image | 38,940,688 字节，`4.19.157-perf+ #8`，clang **11.0.5 (r399163b)** |
| AK3 配置 | `do.devicecheck=0`、`do.modules=0`、`do.systemless=1`、`IS_SLOT_DEVICE=1` |

**关键：镜像内嵌了 IKCONFIG**，所以完整 `.config` 已提取到 `config/reno4-4.19.157-working.config`（6217 行、1906 个 CONFIG_）。不用再猜配置。

## 二、真实配置里的容器相关项

已有：`NET_NS` `UTS_NS` `CGROUPS` `MEMCG` `CPUSETS` `CGROUP_SCHED` `CGROUP_FREEZER` `CGROUP_BPF` `OVERLAY_FS` `VETH` `BRIDGE` `NF_NAT` `IP_NF_TARGET_MASQUERADE` `SECCOMP_FILTER` `TUN` `FUSE_FS` `PSI`

缺 4 个（`config/docker-android.fragment` 就补这 4 行 + 关 1 项）：

```
CONFIG_USER_NS=y
CONFIG_PID_NS=y
CONFIG_IPC_NS=y
CONFIG_CGROUP_DEVICE=y
# CONFIG_ANDROID_PARANOID_NETWORK is not set   ← 原来 =y，会按 gid 拦 socket
```

## 三、三条硬结论

1. **vermagic 必须一字不差**。`CONFIG_MODVERSIONS=y`，机内模块要的 vermagic 是 `4.19.157-perf+ SMP preempt mod_unload modversions aarch64`。所以：
   - 源码必须 merge 到 `v4.19.157`（官方公开源码只有 4.19.81）；
   - 编译时 `LOCALVERSION=-perf+`（工作流已写死），否则少了 `+` 模块全废。
2. **工具链对不上**。原作者用 clang 11.0.5（r399163b），现在镜像站只剩 r416183b（clang 12）。能用，但 `MODVERSIONS` 的 CRC 可能有出入 → 一旦 WiFi/触摸挂，就带上编出来的 `modules.tar.gz` 一起刷（AK3 `do.modules=1`）。
3. **不用重签 AVB**。原 boot 有自签 footer 且校验开启，而你机器能跑它，说明 **vbmeta 校验早已关掉**。所以我们重打包出来的 boot 不带有效签名也能启动，走你现在这套刷法即可。

## 四、跑 GitHub Actions

1. Fork `https://github.com/oppo-source/Reno4-5G`。
2. 把本目录的 `.github/`、`config/`、`scripts/` 推到仓库根。
3. Actions → `build-reno4-docker-kernel` → Run workflow：
   - `merge_stable` 保持 `v4.19.157`
   - `boot_img_url` 填 `boot_Reno4_5G_4.19.157_stockcfg.img` 的直链（出 `boot-docker.img`）
   - `ak3_template_url` 填 `Reno4_5G_KSU_kernel_4.19.157.zip` 的直链（出可直刷 zip）
4. 产物：`Image`、`boot-docker.img`、`reno4-docker-ak3.zip`、`modules.tar.gz`、`.config`。

## 五、刷

优先 AK3 zip（跟你现在的方式一样，KernelFlasher / Magisk 直接刷）：

```bash
# 只要内核
bash scripts/make-ak3.sh Reno4_5G_KSU_kernel_4.19.157.zip Image reno4-docker-ak3.zip
# 内核 + 新模块（CRC 对不上时用）
bash scripts/make-ak3.sh Reno4_5G_KSU_kernel_4.19.157.zip Image reno4-docker-ak3.zip modules/lib/modules
```

本机已实测：用模板包换 Image 后重打包，`Image`/`anykernel.sh`/`tools/magiskboot`/`update-binary` 全部完整，输出 20MB，结构和原包一致。

走 fastboot 的话：

```bash
bash scripts/repack-boot.sh boot_Reno4_5G_4.19.157_stockcfg.img Image boot-docker.img mkbootimg
fastboot flash boot boot-docker.img
```

`repack-boot.sh` 已用真实 mkbootimg 验证：header 参数原样继承、ramdisk 与 dtb 逐字节不变、新 kernel 正确替换、magic 仍是 `ANDROID!`。

## 六、验证容器能力

```bash
su
zcat /proc/config.gz | grep -E 'USER_NS|PID_NS|IPC_NS|CGROUP_DEVICE|PARANOID'
unshare -Urn sh -c 'ip link add v0 type veth peer name v1 && echo veth-ok'
```

`/proc/config.gz` 能直接读，是因为这内核开了 `CONFIG_IKCONFIG_PROC=y`。

## 七、文件清单

- `.github/workflows/build-kernel.yml` —— 全流程，参数已按 PDPM00 预填
- `config/reno4-4.19.157-working.config` —— 从你机器内核里提取的完整可用配置
- `config/docker-android.fragment` —— 只补 4 项 + 关 paranoid network
- `scripts/verify-config.sh` —— 编译前卡配置（实测：原配置报 5 项不合格，补后通过）
- `scripts/repack-boot.sh` —— 以原 boot 为底本换核（实测通过）
- `scripts/make-ak3.sh` —— 用你的 AK3 模板包出直刷 zip（实测通过）

## 附录：原机 cmdline

```
console=ttyMSM0,115200,n8 earlycon=msm_geni_serial,0x888000 androidboot.hardware=qcom
androidboot.console=ttyMSM0 androidboot.memcg=1 lpm_levels.sleep_disabled=1
video=vfb:640x400,bpp=32,memsize=3072000 msm_rtb.filter=0x237 service_locator.enable=1
androidboot.usbcontroller=a600000.dwc3 swiotlb=2048 cgroup.memory=nokmem,nosocket
loop.max_part=7 kpti=off buildvariant=user
```
