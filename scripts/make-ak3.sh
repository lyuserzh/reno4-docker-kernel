#!/usr/bin/env bash
# 用现成能刷的 AnyKernel3 包当模板，只把里面的 Image 换成新编的，可选把模块一起塞进去
# 用法: make-ak3.sh <模板.zip> <新Image> <输出.zip> [模块目录]
set -euo pipefail

TPL=${1:?模板 AnyKernel3 zip（例如 Reno4_5G_KSU_kernel_4.19.157.zip）}
IMG=${2:?新编的 Image}
OUT=${3:?输出 zip}
MODDIR=${4:-}

W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT

echo "[1/4] 解模板"
python3 - "$TPL" "$W" <<'PY'
import sys, zipfile
zipfile.ZipFile(sys.argv[1]).extractall(sys.argv[2])
PY

echo "[2/4] 换 Image（$(stat -c%s "$IMG") 字节）"
cp "$IMG" "$W/Image"

if [ -n "$MODDIR" ] && [ -d "$MODDIR" ]; then
  echo "[3/4] 塞入模块 -> modules/vendor/lib/modules/"
  mkdir -p "$W/modules/vendor/lib/modules"
  n=0
  while IFS= read -r ko; do cp "$ko" "$W/modules/vendor/lib/modules/"; n=$((n+1)); done \
    < <(find "$MODDIR" -name '*.ko' | sort)
  echo "    共 $n 个 .ko"
  sed -i 's/^do\.modules=0/do.modules=1/' "$W/anykernel.sh"
  grep -n 'do.modules' "$W/anykernel.sh"
else
  echo "[3/4] 不带模块（沿用机内现有 /vendor/lib/modules）"
  sed -i 's/^do\.modules=1/do.modules=0/' "$W/anykernel.sh"
fi

echo "[4/4] 重新打包（用 python，手机/Actions 都不依赖 zip 命令）"
rm -f "$OUT"
python3 - "$W" "$OUT" <<'PY'
import os, sys, zipfile
root, out = sys.argv[1], sys.argv[2]
with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
    for dirpath, _, files in os.walk(root):
        for f in sorted(files):
            if f == ".DS_Store":
                continue
            p = os.path.join(dirpath, f)
            z.write(p, os.path.relpath(p, root))
print("写入", out, os.path.getsize(out), "字节")
PY
ls -l "$OUT"

echo
echo "刷：把 $OUT 拷到手机，KernelFlasher / Magisk 里选它，或 TWRP 直接刷。"
echo "注意：内核带了新模块时 do.modules=1，AK3 会用 systemless 方式覆盖 /vendor/lib/modules，"
echo "      前提是机器有 root（Magisk/KernelSU）。"
