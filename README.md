# UU Remote Terminal FontFix

**直接替换** 网易 UU 远程（`com.netease.uuremote`）内置终端的字体为 **Maple Mono NF CN**。

替换后终端里只剩一套字体，于是同时解决三件事：

- 拉丁字母 / 数字 / 符号 → Maple Mono（圆角等宽、带连字）
- 中文 → 与英文严格 2:1 等宽的 CJK 字面，不再走系统回退字体
- Nerd Font 图标（tmux 状态栏、oh-my-zsh / starship / p10k 主题等）→ 不再显示为彩色小方块 □

- 形式：**LSPosed 模块**（APK，**自包含字体** —— 不改系统字体，不需要 Magisk 字体模块）
- 适用：UU 远程 Android 版（4.42 实测；其他 4.x 理论上通用）
- 前提：任意 LSPosed 系框架（LSPosed / Vector / KernelSU + Zygisk Next 等），Android 9+（API 26+）

## 下载

- 最新 APK：[`dist/uu-remote-terminal-fontfix-v1.1.1.apk`](dist/uu-remote-terminal-fontfix-v1.1.1.apk)
- 打包下载（APK + 本说明）：[`dist/uu-remote-terminal-fontfix-v1.1.1.zip`](dist/uu-remote-terminal-fontfix-v1.1.1.zip)
- 或见仓库 Releases 页

## 原来是什么字体

UU 终端用 `Typeface.Builder` / `Typeface.CustomFallbackBuilder` 加载**随包自带的字体**
`res/ak/a.ttf`（Courier New Bold 派生，不含 Nerd 字形，中文靠系统回退）。它不跟随系统字体变化，
也不走 `createFromAsset`，所以换系统字体、换输入法、装 Magisk 字体模块对它都没用。

## 现在是什么字体

`MapleMono-NF-CN-Regular.ttf`，一个文件里同时包含：

| 覆盖范围 | 说明 |
|---|---|
| 拉丁 / 数字 / 符号 | Maple Mono 本体，圆角等宽，带连字 |
| 中文（CJK） | 全字集，2:1 严格等宽，与英文对齐 |
| Nerd Fonts v3 | Powerline / Devicons / Font Awesome / Material 等图标 |

所以模块只需要把这**一个** `Typeface` 塞给终端，中英文与图标就是同一套字面，
不会再出现「英文换了、中文还是系统字体」的错位。

字体取自上游项目 [subframe7536/maple-font](https://github.com/subframe7536/maple-font)
的 release 资产 `MapleMono-NF-CN.zip`（当前 pin 在 `v7.9`，构建时校验 sha256），不随仓库提交。

## 原理

模块挂钩 UU 进程内的字体加载路径，把返回值**直接替换**为随 APK 分发的 Maple Mono NF CN
（首次使用时解出一份到目标进程缓存再加载，之后按大小命中复用）：

| 挂钩点 | 说明 |
|---|---|
| `Typeface.Builder.build()` | 实测主路径（v3 日志计数 780+ 次）|
| `Typeface$CustomFallbackBuilder.build()` | AndroidX TypefaceCompat 的 API 29+ 路径 |
| `Typeface.create(String, int)` | 家族名含 `courier` 时替换 |
| `Typeface.createFromAsset` / `createFromFile` / `Resources.getFont` | 兜底 |

加载优先级：模块内置字体 → `/system/fonts/DroidSansMono.ttf`（若系统已被字体模块覆盖）→ `monospace` 兜底。

> 单文件字体，字重只有 Regular；终端里的粗体由系统合成（fake bold）。
> 更在意真粗体的话，可自备 `FONT_TTF=MapleMono-NF-CN-Bold.ttf` 构建（并同步改代码里的文件名）。

## 安装

1. 安装 APK：`adb install uu-remote-terminal-fontfix-v1.1.1.apk`（或在设备上直接点开安装）
2. 打开 LSPosed / Vector 管理器 → 模块 → **启用「UU Remote Terminal FontFix」**
3. **作用域**：模块已内置推荐作用域（`com.netease.uuremote`），开启后一般已自动勾选；若没勾，手动勾上 `UU远程`
4. **重启设备**（至少重启 UU 远程进程）

## 验证

打开 UU 远程 → 设备 → 终端 → 任意会话：中文与英文是同一套字面，Nerd 图标正常显示。

日志（管理器"日志"页，或 `/data/adb/lspd/log/modules_*.log`）：

```
[UUFontFix] 注入 com.netease.uuremote
[UUFontFix] 内置字体就绪(bundled(①a)): true
[UUFontFix] 命中 Builder.build()
```

命令行验证：

```bash
su -c 'grep -h -i uufontfix /data/adb/lspd/log/modules_*.log | tail -10'
```

## 停用 / 卸载

- 管理器里关闭模块 + 重启；或直接卸载 APK。
- 卸载后 UU 终端字体会恢复为自带字体，无残留（缓存里的字体文件随应用缓存清理）。

## 从源码构建

```bash
./build.sh
```

- 需要 Android SDK（自动选最新 build-tools 的 aapt/d8/zipalign/apksigner 与最新 platforms/android-XX）+ JDK 8+
- 首次构建会从 `subframe7536/maple-font` release 下载 `MapleMono-NF-CN.zip`（~150MB，解出其中的
  Regular 并校验 sha256），结果缓存在 `.cache/`（已 gitignore）
- 已有字体可跳过下载：`FONT_TTF=/path/to/MapleMono-NF-CN-Regular.ttf ./build.sh`
- 换字体版本：改 `build.sh` 顶部的 `FONT_VER` / `FONT_SHA256`

`api-82.jar`（Xposed API stub）已随目录附带（取自 Aliyun Maven 镜像 `de.robv.android.xposed:api:82`）。

构建产物：`uu-remote-terminal-fontfix.apk`。

## 许可

- 模块代码：MIT
- 字体：Maple Mono（SIL OFL 1.1，见 `assets/OFL.txt`，即上游 release 的 `LICENSE.txt`）
  + Nerd Fonts 补丁（MIT）+ CJK 字形（SIL OFL 1.1）
- 本项目为第三方社区模块，与网易无关；"UU远程"相关权利归其各自权利人所有。
