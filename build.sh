#!/bin/bash
# 构建「UU Remote Terminal FontFix」Xposed 模块（io.github.guoyongchang.uufont）
#
# 作用：挂钩网易 UU 远程（com.netease.uuremote）进程内的字体加载，
#       把返回的 Typeface 直接替换为随模块分发的 Maple Mono NF CN
#       （单个 ttf 即覆盖 拉丁 / 中文 / Nerd Font 图标）。
#
# 字体来源：https://github.com/subframe7536/maple-font 的 release 资产
#   MapleMono-NF-CN.zip（默认 pin 在 FONT_VER，解出 MapleMono-NF-CN-Regular.ttf，
#   并校验 sha256）。已下载的 pack 存放在 .cache/（已 gitignore），
#   所以同一个版本既不需要联网，也不需要把 20MB 的 ttf 提交进仓库。
#
#   离线/自备字体：FONT_TTF=/path/to/MapleMono-NF-CN-Regular.ttf ./build.sh
#
# 依赖：
#   - Android SDK：任意 build-tools（脚本自动选最新，需要 aapt/d8/
#     zipalign/apksigner）与任意 platforms/android-XX（取最新）
#   - JDK 8+（javac/jar/keytool）
#   - api-82.jar（Xposed API stub，已随目录提供；
#     来源 maven.aliyun.com 镜像 de.robv.android.xposed:api:82）
#
# 安装：adb install -r dist/uu-remote-terminal-fontfix-*.apk
# 启用：su -c 'sh /data/adb/modules/zygisk_vector/cli modules enable io.github.guoyongchang.uufont'
# 作用域：su -c 'sh /data/adb/modules/zygisk_vector/cli scope set io.github.guoyongchang.uufont com.netease.uuremote/0'
# 重启生效。
set -euo pipefail
cd "$(dirname "$0")"

# —— 分发的字体 ——
FONT_REPO="subframe7536/maple-font"
FONT_VER="v7.9"
FONT_TTF_NAME="MapleMono-NF-CN-Regular.ttf"
FONT_ZIP_NAME="MapleMono-NF-CN.zip"
# 上游 release 中 MapleMono-NF-CN-Regular.ttf 的 sha256（换版本时同步更新）
FONT_SHA256="bb8e8e8c263896f42555107202f1847f7a42c340a3e532df9c4d585c9794411c"

SDK="${ANDROID_SDK:-${ANDROID_HOME:-$HOME/Library/Android/sdk}}"
pick() { # pick <dir-glob> <required-file> -> 最新的可用目录
  local best=""
  for d in $1; do
    [ -e "$d/$2" ] || continue
    if [ -z "$best" ] || [ "$(basename "$d")" \> "$(basename "$best")" ]; then best="$d"; fi
  done
  printf '%s' "$best"
}

BT="$(pick "$SDK/build-tools/*" aapt)"
PLATFORM="$(pick "$SDK/platforms/android-*" android.jar)"
[ -n "$BT" ] && [ -n "$PLATFORM" ] || { echo "找不到 Android SDK (build-tools / platforms)，设置 ANDROID_SDK"; exit 1; }
AJ="$PLATFORM/android.jar"
echo "build-tools: $BT"
echo "platform   : $PLATFORM"

rm -rf build
mkdir -p build/classes build/dex build/apk/assets/fonts

echo "[1/6] 准备字体"
CACHE=".cache"
FONT_TTF_OVERRIDE="${FONT_TTF:-}"
FONT_TTF="$FONT_TTF_OVERRIDE"
if [ -z "$FONT_TTF" ]; then
  mkdir -p "$CACHE"
  ZIP="$CACHE/$FONT_VER-$FONT_ZIP_NAME"
  EXTRACTED="$CACHE/$FONT_VER-$FONT_TTF_NAME"
  if [ ! -f "$EXTRACTED" ]; then
    if [ ! -f "$ZIP" ]; then
      echo "  下载 $FONT_REPO@$FONT_VER/$FONT_ZIP_NAME (~150MB，仅首次)"
      curl -fL --retry 3 -o "$ZIP.part" \
        "https://github.com/$FONT_REPO/releases/download/$FONT_VER/$FONT_ZIP_NAME"
      mv "$ZIP.part" "$ZIP"
    fi
    unzip -o -q -j "$ZIP" "$FONT_TTF_NAME" -d "$CACHE"
    mv "$CACHE/$FONT_TTF_NAME" "$EXTRACTED"
  fi
  FONT_TTF="$EXTRACTED"
fi
ACTUAL_SHA="$(shasum -a 256 "$FONT_TTF" | cut -d' ' -f1)"
if [ -n "${FONT_TTF_OVERRIDE:-}" ]; then
  echo "  使用自备字体，跳过 sha256 校验：$FONT_TTF"
else
  if [ "$ACTUAL_SHA" != "$FONT_SHA256" ]; then
    echo "  字体 sha256 不匹配，可能版本/文件不对：" >&2
    echo "    got      $ACTUAL_SHA" >&2
    echo "    expected $FONT_SHA256" >&2
    exit 1
  fi
fi
echo "  $(basename "$FONT_TTF")  $(du -h "$FONT_TTF" | cut -f1)  sha256 ok"
cp "$FONT_TTF" "build/apk/assets/fonts/$FONT_TTF_NAME"

echo "[2/6] 资源"
cp assets/xposed_init assets/OFL.txt build/apk/assets/

echo "[3/6] javac"
javac --release 8 -nowarn -cp "$AJ:api-82.jar" -d build/classes \
  src/io/github/guoyongchang/uufont/UUFontFix.java

echo "[4/6] d8 -> classes.dex"
jar cf build/classes.jar -C build/classes .
"$BT/d8" --release --min-api 26 --lib "$AJ" --output build/dex build/classes.jar

echo "[5/6] 打包 + 对齐 + 签名"
"$BT/aapt" package -f -M AndroidManifest.xml -S res -I "$AJ" -F build/unsigned.apk
(cd build/dex && zip -q ../unsigned.apk classes.dex)
(cd build/apk && zip -qr ../unsigned.apk assets)
"$BT/zipalign" -f 4 build/unsigned.apk build/aligned.apk
if [ ! -f ks.jks ]; then
  keytool -genkeypair -keystore ks.jks -storepass android -keypass android -alias m \
    -keyalg RSA -keysize 2048 -validity 10000 -dname "CN=omp"
fi
OUT="uu-remote-terminal-fontfix.apk"
"$BT/apksigner" sign --ks ks.jks --ks-pass pass:android --key-pass pass:android \
  --out "$OUT" build/aligned.apk

echo "[6/6] 验证"
"$BT/apksigner" verify "$OUT"
echo "OK -> $(pwd)/$OUT ($(du -h "$OUT" | cut -f1))"
