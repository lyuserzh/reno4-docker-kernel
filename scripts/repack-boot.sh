#!/usr/bin/env bash
# 用原厂 boot.img 作底本，只换 kernel，其余（ramdisk / dtb / cmdline / header 版本 / 页大小 / 基址）原样保留
# 用法: repack-boot.sh <原厂boot.img> <新Image> <输出boot.img> [mkbootimg源码目录]
set -euo pipefail

BOOT_IN=${1:?原厂 boot.img}
KERNEL_IMG=${2:?新编的 Image}
BOOT_OUT=${3:?输出 boot.img}
MK=${4:-mkbootimg}

W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT

echo "[1/4] 拆原厂 boot.img"
python3 "$MK/unpack_bootimg.py" --boot_img "$BOOT_IN" --out "$W/u" --format=mkbootimg > "$W/args.txt" || {
  echo "unpack_bootimg 失败，输出："; sed -n '1,40p' "$W/args.txt"; exit 1;
}
ARGS=$(grep -m1 -- '--header_version' "$W/args.txt" || true)
if [ -z "$ARGS" ]; then
  echo "没解析到 boot header，原始输出："; sed -n '1,60p' "$W/args.txt"; exit 1
fi
echo "    原参数: $(printf '%s' "$ARGS" | grep -oE -- '--header_version [0-9]|--pagesize 0x[0-9a-f]+' | tr '\n' ' ')"

echo "[2/4] 按原 kernel 的压缩格式处理新 Image"
magic=$(od -An -tx1 -N4 "$W/u/kernel" | tr -d ' \n')
case "$magic" in
  1f8b*)        echo "    原 kernel = gzip";  gzip -9 -n -c "$KERNEL_IMG" > "$W/kernel.new" ;;
  04224d18*)    echo "    原 kernel = lz4";   lz4 -9 -l -c "$KERNEL_IMG" > "$W/kernel.new" ;;
  fd377a585a*)  echo "    原 kernel = xz";    xz -9 -c "$KERNEL_IMG" > "$W/kernel.new" ;;
  *)            echo "    原 kernel = 裸 Image"; cp "$KERNEL_IMG" "$W/kernel.new" ;;
esac
mv "$W/kernel.new" "$W/u/kernel"

echo "[3/4] 用同样的 header 参数重打包"
CMD="python3 \"$MK/mkbootimg.py\" $ARGS --output \"$BOOT_OUT\""
echo "    $CMD"

echo "[4/4] 执行"
eval "$CMD"

echo
ls -l "$BOOT_IN" "$BOOT_OUT"
echo
echo "自检：新镜像里的 kernel 大小 $(stat -c%s "$W/u/kernel") 字节（原 $(stat -c%s "$BOOT_IN") 字节的 boot 内）"
echo "注意：原 boot.img 若带 AVB footer，这里不会重签，刷之前处理 vbmeta，"
echo "      例如: fastboot --disable-verity --disable-verification flash vbmeta vbmeta.img"
echo "      或:  avbtool add_hash_footer --image $BOOT_OUT --partition_name boot \\"
echo "             --partition_size <原 boot 分区字节数> --key testkey_rsa2048.pem --algorithm SHA256_RSA2048"
