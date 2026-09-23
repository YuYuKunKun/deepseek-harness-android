#!/data/data/com.termux/files/usr/bin/bash
# =============================================================================
# DeepSeek Harness (dsh) 一键安装脚本 — Android / Termux
# -----------------------------------------------------------------------------
# 安装 DeepSeek 官方 agent harness (@deepseek-ai/dsh) 并在 Termux 上跑起来，
# 自动完成所有 Android 兼容修复：
#   1. 安装构建依赖 (cmake/clang/make/binutils/pkg-config/python/nodejs)
#   2. node-gyp install 下载 headers 填充缓存 → 修补 common.gypi（修 node-pty 构建）
#   3. 用 android30 编译目标安装 dsh（修 koffi statx）+ 放行构建脚本（下载+编译需耐心）
#   4. 修补 link() → rename()（华为/部分 ROM 禁 hardlink，会话/附件才能持久化）
#      + write 新建文件回退 + 附件祖先遍历/清理容忍（同族 Android EACCES，见 patches/patch-dsh-android-link.js）
#   5. 修补 subprocess 终端检测（android 视同 linux）
#   6. 安装 sharp WebAssembly 回退（android-arm64 无原生预编译）
#   7. 重建 /usr/bin/dsh 包装脚本（--expose-internals，HMR 必需）
#   8. 写入启动/停止脚本 + 权限模式配置
#   9. 前端移动端适配（CSS/JS 注入、viewport、manifest standalone）
#  10. JS 性能补丁（/assets/ 内容哈希产物 immutable 缓存头）
#
# 用法：
#   bash setup.sh
# 之后：
#   bash ~/dsh/start_dsh.sh     # 启动并拉起 Chrome
#   在 Web UI (http://127.0.0.1:3080) 的 Models 页配置 DeepSeek API Key
# =============================================================================
set -euo pipefail

info()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn()  { printf '\033[1;33m[!]\033[0m %s\n' "$*"; }
ok()    { printf '\033[1;32m[v]\033[0m %s\n' "$*"; }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"   # 脚本真实目录（脚本中段会 cd，须用绝对路径）
DSH_DIR="/data/data/com.termux/files/usr/lib/node_modules/@deepseek-ai/dsh"
INSTALL_DIR="$HOME/dsh"

# ============================== 版本控制 ==============================
# 为什么钉版本：本脚本会给 dsh 打一批就地补丁（4a~4f + 前端/JS 补丁）。上游一旦改动
# 目标代码，补丁就会静默失配——之前默认装 npm latest，等于每次安装都赌上游没动过。
# 所以这里锁定一个已验证版本，并把"验证过的版本"列成白名单显式核对。
SETUP_VERSION="1.1.0"                        # 本脚本自身版本（语义变化时递增）
DSH_VERSION_DEFAULT="0.1.5-rc.2"             # 默认安装（= 当前 npm latest，也是补丁基线）
DSH_VERSION_VERIFIED="0.1.5-rc.1 0.1.5-rc.2" # 补丁集已实测通过的版本

is_verified_version() { [[ " $DSH_VERSION_VERIFIED " == *" $1 "* ]]; }
installed_dsh_version() {
  [ -f "$DSH_DIR/package.json" ] || return 0
  node -e 'try{process.stdout.write(require(process.argv[1]).version)}catch{}' \
    "$DSH_DIR/package.json" 2>/dev/null || true
}

# 目标解析优先级：
#   1) DSH_NPM      —— 完整 spec，最高优先级（CI / 特殊源 / 本地 tgz 都可）
#   2) DSH_VERSION  —— 只给版本或标签，如 0.1.5-rc.2 / latest / next
#   3) 已安装且在白名单内 —— 保持现状，避免重跑脚本时把用户降级
#   4) DSH_VERSION_DEFAULT
DSH_VERSION_SOURCE=""
if [ -n "${DSH_NPM:-}" ]; then
  DSH_VERSION_SOURCE="环境变量 DSH_NPM"
elif [ -n "${DSH_VERSION:-}" ]; then
  DSH_NPM="@deepseek-ai/dsh@${DSH_VERSION}"
  DSH_VERSION_SOURCE="环境变量 DSH_VERSION"
else
  CURRENT_VERSION="$(installed_dsh_version)"
  if [ -n "$CURRENT_VERSION" ] && is_verified_version "$CURRENT_VERSION"; then
    DSH_NPM="@deepseek-ai/dsh@${CURRENT_VERSION}"
    DSH_VERSION_SOURCE="沿用已安装且已验证的版本 ${CURRENT_VERSION}"
  else
    DSH_NPM="@deepseek-ai/dsh@${DSH_VERSION_DEFAULT}"
    DSH_VERSION_SOURCE="默认已验证版本"
  fi
fi
# 请求的版本号（仅当 spec 形如 @deepseek-ai/dsh@<ver> 时能解析出来）
DSH_REQUESTED_VERSION=""
case "$DSH_NPM" in
  "@deepseek-ai/dsh@"*) DSH_REQUESTED_VERSION="${DSH_NPM#@deepseek-ai/dsh@}" ;;
esac
# =====================================================================

info "setup.sh v${SETUP_VERSION} · 安装目标 ${DSH_NPM}（${DSH_VERSION_SOURCE}）"
if [ -n "$DSH_REQUESTED_VERSION" ]; then
  if is_verified_version "$DSH_REQUESTED_VERSION"; then
    ok "  版本 ${DSH_REQUESTED_VERSION} 在已验证列表内（${DSH_VERSION_VERIFIED}）"
  else
    warn "  版本 ${DSH_REQUESTED_VERSION} 不在已验证列表内（${DSH_VERSION_VERIFIED}）"
    warn "  补丁可能失配；失配时脚本会如实报 WARN，不会假装成功"
  fi
else
  warn "  spec 未锁定版本（跟随 registry 的 latest 标签）"
  warn "  上游发新版后补丁可能失配；建议改为 DSH_VERSION=${DSH_VERSION_DEFAULT}"
fi

# ---------------------------------------------------------------- 1/10 依赖
info "1/10 安装构建依赖 (cmake clang make binutils pkg-config python nodejs)"
pkg update -y >/dev/null 2>&1 || true
pkg install -y cmake clang make binutils pkg-config python nodejs

command -v node >/dev/null 2>&1 || { warn "node 未安装，重试安装 nodejs..."; pkg install -y nodejs; }
NODE_VER="$(node -v | sed 's/^v//')"
info "Node.js v${NODE_VER}"

# --------------------------------------------------- 智能换源（国内用户友好）
# 检测默认 npm / nodejs.org 是否太慢，慢则自动切换到 npmmirror 镜像。
# 仅通过环境变量作用于本次安装会话，不改动全局 npm 配置。
is_slow() {
  local url="$1" t
  t=$(curl -o /dev/null -s -w '%{time_total}' --max-time 6 "$url" 2>/dev/null)
  [ -z "$t" ] && return 0
  awk -v t="$t" 'BEGIN { exit !(t > 1.0) }'
}
if is_slow "https://registry.npmjs.org/-/ping"; then
  info "默认 npm 源较慢，自动切换到 npmmirror 镜像 (registry.npmmirror.com)"
  export npm_config_registry="https://registry.npmmirror.com"
fi
if is_slow "https://nodejs.org/dist/"; then
  info "nodejs.org 较慢，node-gyp 下载 Node headers 自动切换到 npmmirror 镜像"
  export npm_config_disturl="https://npmmirror.com/mirrors/node/"
fi

# ------------------------------------------------------- 2/10 准备 gyp 补丁
info "2/10 下载 Node headers 填充 node-gyp 缓存（约 1 分钟，请稍候）"
# node-gyp 首次构建会把 node headers 解压到缓存，其中 common.gypi 引用了
# android_ndk_path 变量；Termux 无 NDK 该变量未定义 → 必须修补缓存文件。
# 这里用 `node-gyp install` 只下载 headers（远快于整树 npm install），随后打补丁。
# 若此处卡住：多为网络问题，检查能否访问 nodejs.org；超时 300s 后自动跳过并告警。
timeout 300 npx --yes node-gyp install 2>&1 | tail -3 || true

GYP_GIPI="$HOME/.cache/node-gyp/$NODE_VER/include/node/common.gypi"
if [ -f "$GYP_GIPI" ]; then
  info "修补 common.gypi: 定义 android_ndk_path 为空（修 node-pty 的 Undefined variable 错误）"
  python3 - "$GYP_GIPI" <<'PY'
import sys
p = sys.argv[1]
s = open(p, encoding='utf-8').read()
if "'android_ndk_path%': ''" not in s:
    s = s.replace("'variables': {", "'variables': {\n    'android_ndk_path%': '',", 1)
    open(p, 'w', encoding='utf-8').write(s)
print("  patched common.gypi")
PY
else
  warn "未找到 $GYP_GIPI，请确认 node 已安装；可先手动跑一次 `npm i -g @deepseek-ai/dsh` 填充缓存"
fi

# ------------------------------------------------------------- 3/10 正式安装
info "3/10 用 android30 编译目标安装 ${DSH_NPM}（下载依赖+原生编译，可能需要 5~15 分钟，请耐心等待，不要中断）"
# 处理 koffi 编译的 <spawn.h> 问题（Issue #4）：-target aarch64-linux-android30 会让 clang
# 改用 Android NDK sysroot 头文件路径，可能找不到 Termux 的 /usr/include 里的 spawn.h。
# 修复：显式加入 $PREFIX/include（含权限可读的 include 路径）；若 spawn.h 缺失则写入
# bionic 兼容 shim 并加入 include 路径，shim 权限设为 644 确保可读。
PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
EXTRA_FLAGS="-target aarch64-linux-android30 -I$PREFIX/include"
if [ ! -f "$PREFIX/include/spawn.h" ]; then
  warn "缺少 $PREFIX/include/spawn.h，写入 bionic 兼容 shim（Issue #4）"
  SPHIM_DIR="$(mktemp -d)"
  cat > "$SPHIM_DIR/spawn.h" <<'SPAWN_SHIM'
/* bionic 兼容 spawn.h shim（Issue #4：koffi 编译缺 <spawn.h>） */
#ifndef _TERMUX_SPAWN_SHIM_H
#define _TERMUX_SPAWN_SHIM_H
#include <sys/types.h>
#include <signal.h>
#ifdef __cplusplus
extern "C" {
#endif
#define POSIX_SPAWN_RESETIDS   0x01
#define POSIX_SPAWN_SETPGROUP  0x02
#define POSIX_SPAWN_SETSIGDEF  0x04
#define POSIX_SPAWN_SETSIGMASK 0x08
typedef struct { short __flags; pid_t __pgrp; sigset_t __setsigdef, __setsigmask; } posix_spawnattr_t;
typedef struct __posix_spawn_file_actions_entry {
  int __action; int __fd; int __newfd; char __path[1];
} __posix_spawn_file_actions_entry;
typedef struct { int __allocated; int __used; __posix_spawn_file_actions_entry *__actions; } posix_spawn_file_actions_t;
int posix_spawn(pid_t *__restrict, const char *__restrict,
                const posix_spawn_file_actions_t *, const posix_spawnattr_t *__restrict,
                char *const __restrict[], char *const __restrict[]);
int posix_spawn_file_actions_init(posix_spawn_file_actions_t *);
int posix_spawn_file_actions_destroy(posix_spawn_file_actions_t *);
int posix_spawn_file_actions_adddup2(posix_spawn_file_actions_t *, int, int);
#ifdef __cplusplus
}
#endif
#endif
SPAWN_SHIM
  chmod 644 "$SPHIM_DIR/spawn.h"
  EXTRA_FLAGS="$EXTRA_FLAGS -I$SPHIM_DIR"
fi
CFLAGS="$EXTRA_FLAGS" CXXFLAGS="$EXTRA_FLAGS" \
  npm install -g --allow-scripts=@deepseek-ai/dsh-subprocess-local,koffi,node-pty,@google/genai,protobufjs "$DSH_NPM"
# 加载自检：执行 .node 文件本身会触发 Illegal instruction（它是共享库，不是可执行文件），
# 必须用 require 真正加载 node-pty 包，才能判断产物是否可用。
if node -e 'require(process.argv[1])' "$DSH_DIR/node_modules/node-pty" >/dev/null 2>&1; then
  ok "node-pty 编译产物就位（加载自检通过）"
elif [ -f "$DSH_DIR/node_modules/node-pty/build/Release/pty.node" ]; then
  warn "  node-pty 产物存在但加载自检失败（PTY / 持久终端可能不可用）"
else
  warn "  未找到 node-pty 编译产物（PTY / 持久终端将不可用）"
fi
# 同样不能用文件存在性判断：koffi 3.x 并不在 build/koffi/android_arm64/ 下
# （终端实测该路径无 .node，但 require("koffi") 正常）——文件检查会误报缺失。
if node -e 'require(process.argv[1])' "$DSH_DIR/node_modules/koffi" >/dev/null 2>&1; then
  ok "koffi 原生模块就位（加载自检通过）"
else
  warn "  koffi 加载自检失败（dsh-subprocess-local / fs-local 等将无法加载）"
fi

# ------------------------------------------------- 3.1 安装后版本核对
# 请求的版本未必等于实际装上的（registry 解析、标签漂移、缓存等），所以以磁盘为准核对一次。
INSTALLED_VERSION="$(installed_dsh_version)"
if [ -z "$INSTALLED_VERSION" ]; then
  warn "  无法读取已安装 dsh 的版本（$DSH_DIR/package.json）"
else
  ok "  已安装 dsh 版本：${INSTALLED_VERSION}"
  if [ -n "$DSH_REQUESTED_VERSION" ] && [ "$INSTALLED_VERSION" != "$DSH_REQUESTED_VERSION" ]; then
    warn "  请求的是 ${DSH_REQUESTED_VERSION}，实际装上的是 ${INSTALLED_VERSION}（registry 解析差异？）"
  fi
  if is_verified_version "$INSTALLED_VERSION"; then
    ok "  在已验证列表内（${DSH_VERSION_VERIFIED}）"
  else
    warn "  不在已验证列表内（${DSH_VERSION_VERIFIED}）——后续补丁若失配，请以 WARN 行为准"
    warn "  可改用已验证版本重跑：DSH_VERSION=${DSH_VERSION_DEFAULT} bash setup.sh"
  fi
fi

# ------------------------------------------------------- 4/10 后端兼容补丁
info "4/10 后端兼容补丁"

# 4a: 会话持久化 link→rename（Android 禁 hardlink）
SJ="$DSH_DIR/node_modules/@deepseek-ai/dsh-session-persistence-jsonl/lib/index.js"
if grep -q "rename(tmp, finalPath)" "$SJ" 2>/dev/null; then
  ok "  session-persistence 已修补"
else
  python3 - "$SJ" <<'PY'
import re, sys
p = sys.argv[1]
s = open(p, encoding='utf-8').read()
old = 'await link(tmp, finalPath);'
if s.count(old) != 1:
    print(f"  WARN: 会话发布模式未精确匹配（命中 {s.count(old)} 处），跳过；请人工检查 {p}")
    sys.exit(0)
out = s.replace(old, 'await rename(tmp, finalPath);')
out = out.replace('import { link, mkdir,', 'import { mkdir,')
out = out.replace('realpath, rm,', 'realpath, rename, rm,')
# 写坏代码比不修更糟：确认 rename 确实已从 node:fs/promises 导入
m = re.search(r'^import \{([^}]*)\} from "node:fs/promises";$', out, re.M)
if m is None or 'rename' not in [n.strip() for n in m.group(1).split(',')]:
    print(f"  WARN: 未能确认 rename 已导入，跳过以免写入坏代码；请人工检查 {p}")
    sys.exit(0)
open(p, 'w', encoding='utf-8').write(out)
print("  patched session-persistence-jsonl (link→rename)")
PY
fi

# 4b: 附件存储 link→rename
AL="$DSH_DIR/node_modules/@deepseek-ai/dsh-attachment-local/lib/index.js"
if grep -q "rename(temporary, target)" "$AL" 2>/dev/null; then
  ok "  attachment-local 已修补"
else
  python3 - "$AL" <<'PY'
import sys
p = sys.argv[1]
s = open(p, encoding='utf-8').read()
old = 'await link(temporary, target);'
if s.count(old) != 1:
    print(f"  WARN: 未找到旧形态 link(temporary, target)（命中 {s.count(old)} 处）。")
    print("        0.1.5-rc.x 的附件发布改成了 link(source, target) / link(staged.path, target)，")
    print("        本项目尚无对应回退 —— 被禁 hardlink 的 ROM 上附件保存可能失败（已知问题，")
    print("        见 README「已知问题」行与 patches/obsolete/README.md）。")
    sys.exit(0)
s = s.replace(old, 'await rename(temporary, target);')
s = s.replace('import { chmod, link, mkdir,', 'import { chmod, mkdir,')
s = s.replace('readFile, unlink }', 'readFile, rename, unlink }')
open(p, 'w', encoding='utf-8').write(s)
print("  patched attachment-local (link→rename)")
PY
fi

# 4e: 无硬链接 no-replace 发布 + 附件祖先遍历/清理容忍
#     （write 工具新建文件 / 附件保存，同 4a/4b 的 link→rename 一族的 Android EACCES 修复，
#       幂等；基于 dsh 0.1.0-rc.3/rc.6 均可。详见 patches/patch-dsh-android-link.js）
HLFIX="$SCRIPT_DIR/patches/patch-dsh-android-link.js"
if [ -f "$HLFIX" ]; then
  if node "$HLFIX" --root "$DSH_DIR/node_modules/@deepseek-ai"; then
    ok "  android 硬链接修复完成（fs-local / attachment）"
  else
    warn "  硬链接修复脚本报告异常（dsh 版本不匹配？请人工检查）"
  fi
else
  warn "  缺少 patches/patch-dsh-android-link.js，跳过硬链接修复"
fi

# 4c: subprocess 终端检测 android 视同 linux
# 0.1.5-rc.1 该判断在 lib/index.js；rc.2 起被拆进哈希命名的 chunk
# （lib/runner-launch-*.js），文件名随构建变化——所以按内容在整个 lib/ 下搜，
# 不写死文件名，找不到时明确告警而不是假装成功。
SP_DIR="$DSH_DIR/node_modules/@deepseek-ai/dsh-subprocess-local/lib"
SP_PAT='if (platform === "linux") return new LinuxProcessInspector(arch, internals);'
if grep -rq 'platform === "android"' "$SP_DIR" 2>/dev/null; then
  ok "  subprocess-local 已修补"
else
  SP="$(grep -rlF "$SP_PAT" "$SP_DIR" 2>/dev/null | head -1)"
  if [ -n "$SP" ]; then
    python3 - "$SP" <<'PY'
import sys
p = sys.argv[1]
s = open(p, encoding='utf-8').read()
old = 'if (platform === "linux") return new LinuxProcessInspector(arch, internals);'
new = 'if (platform === "linux" || platform === "android") return new LinuxProcessInspector(arch, internals);'
if s.count(old) != 1:
    print(f"  WARN: 平台判断模式未精确匹配（命中 {s.count(old)} 处），跳过；请人工检查 {p}")
    sys.exit(0)
open(p, 'w', encoding='utf-8').write(s.replace(old, new))
print(f"  patched subprocess-local (android→linux): {p}")
PY
  else
    warn "  未找到 subprocess-local 的平台判断模式（dsh 版本可能又变了）"
    warn "  若终端/PTY 报 'unsupported on platform android'，请手动在 $SP_DIR 下搜 LinuxProcessInspector 并让 android 走 linux 分支"
  fi
fi

# 4d: 作曲栏 普通回车=换行（不发送），Ctrl/Cmd+Enter=发送
# 安卓输入法/键盘的回车会误触发发送，改为在 composer keymap 的 Enter 命令里
# 对非加速回车返回 false，交还编辑器默认行为（=换行）。对应 apply-frontend.sh
# 注入的 enterkeyhint=newline（让输入法回车键显示"换行"）。
# 用正则容忍缩进/周边改动，避免上游微调后静默失配（0.1.5-rc.1 / rc.2 已验证）。
CB="$DSH_DIR/node_modules/@deepseek-ai/dsh-client-ui-conversation/lib/client.js"
if grep -q "dsh-android: 普通回车换行" "$CB" 2>/dev/null; then
  ok "  client-ui-conversation 回车补丁已就位"
else
  python3 - "$CB" <<'PY'
import re, sys
p = sys.argv[1]
s = open(p, encoding='utf-8').read()
# 定位 composer keymap 的 Enter 命令：先 arbitrate，再无条件 preventDefault + submit。
pattern = re.compile(
  r'(?P<i>[ \t]*)if \(handlers\.arbitrate\("enter", false\) !== "pass"\) \{\n'
  r'(?P=i)[ \t]*event\?\.preventDefault\(\);\n'
  r'(?P=i)[ \t]*return true;\n'
  r'(?P=i)\}\n'
  r'(?P=i)event\?\.preventDefault\(\);\n'
  r'(?P=i)if \(event\?\.repeat === true\) return true;\n'
  r'(?P=i)if \(!handlers\.canSubmit\(\)\) return true;\n'
  r'(?P=i)handlers\.submit\(event\?\.ctrlKey === true \|\| event\?\.metaKey === true\);\n'
)
def repl(m):
  i = m.group('i')
  return (
    f'{i}if (handlers.arbitrate("enter", false) !== "pass") {{\n'
    f'{i}\tevent?.preventDefault();\n'
    f'{i}\treturn true;\n'
    f'{i}}}\n'
    f'{i}/* dsh-android: 普通回车换行，Ctrl/Cmd+Enter 发送 */\n'
    f'{i}if (event != null && event.ctrlKey !== true && event.metaKey !== true) return false;\n'
    f'{i}event?.preventDefault();\n'
    f'{i}if (event?.repeat === true) return true;\n'
    f'{i}if (!handlers.canSubmit()) return true;\n'
    f'{i}handlers.submit(event?.ctrlKey === true || event?.metaKey === true);\n'
  )
s, n = pattern.subn(repl, s)
if n != 1:
  print(f"  WARN: 回车补丁模式未匹配（命中 {n} 处），跳过；dsh 版本可能已变化，请人工检查")
  sys.exit(0)
open(p, 'w', encoding='utf-8').write(s)
print("  patched client-ui-conversation (Enter=换行, Ctrl/Cmd+Enter=发送)")
PY
fi

# 4f: Android 上 flock 不可用 → 会话租约失败 → 会话日志完全写不出来
#   症状：会话目录里只有一个 0 字节的 session.lock，没有 session.jsonl.zstd，
#         Web UI 报 "flock is not supported on android-arm64"。
#   原因：上游只发布 darwin/linux 的预编译原生包（node-addon-system-<platform>-<arch>），
#         node-addon-system/lib/flock.js 对 platform==="android" 直接抛
#         ERR_FLOCK_UNSUPPORTED_PLATFORM；而 dsh-session-persistence-jsonl 只在
#         EAGAIN/EWOULDBLOCK 时按“锁被占用”降级，其余错误一律上抛。
#   处理：实测 bionic 本身支持 flock(2)，缺的只是预编译产物。手机上 dsh 是单进程，
#         这里采用与上游 browser worker 对 flock 完全相同的语义（桩成立即成功）。
FL="$DSH_DIR/node_modules/@deepseek-ai/node-addon-system/lib/flock.js"
if grep -q "dsh-android" "$FL" 2>/dev/null; then
  ok "  node-addon-system flock 已修补（android 单进程语义）"
else
  python3 - "$FL" <<'PY'
import sys
p = sys.argv[1]
s = open(p, encoding='utf-8').read()
anchor = 'export async function tryLockExclusive(fd) {'
if s.count(anchor) != 1:
    print(f"  WARN: 未找到 tryLockExclusive 锚点（命中 {s.count(anchor)} 处），跳过；请人工检查 {p}")
    sys.exit(0)
inject = (
    anchor + "\n"
    "    /* [dsh-android] android 无预编译原生包，但 bionic 支持 flock(2)；\n"
    "       手机上 dsh 为单进程，采用与上游 browser worker 相同的桩语义（立即成功）。 */\n"
    "    if (process.platform === 'android')\n"
    "        return;\n"
)
open(p, 'w', encoding='utf-8').write(s.replace(anchor, inject))
print("  patched node-addon-system flock (android → 单进程语义)")
PY
fi

# ------------------------------------------------------ 5/10 sharp wasm 回退
info "5/10 安装 sharp WebAssembly 回退（android-arm64 无原生预编译）"
SHARP_VER="$(node -e "console.log(require('$DSH_DIR/node_modules/sharp/package.json').version)" 2>/dev/null || echo 0.35.3)"
if [ -d "$DSH_DIR/node_modules/@img/sharp-wasm32" ]; then
  ok "  sharp-wasm32 已就位 (v${SHARP_VER})"
else
  SWTMP="$(mktemp -d)"
  cd "$SWTMP"
  npm init -y >/dev/null 2>&1
  npm install "@img/sharp-wasm32@$SHARP_VER" >/dev/null 2>&1
  mkdir -p "$DSH_DIR/node_modules/@img"
  cp -r node_modules/@img/sharp-wasm32 "$DSH_DIR/node_modules/@img/"
  cp -r node_modules/@emnapi "$DSH_DIR/node_modules/" 2>/dev/null || true
  cd "$HOME"
  rm -rf "$SWTMP"
  ok "  sharp-wasm32@${SHARP_VER} 已安装"
fi

# ------------------------------------------------------ 6/10 dsh 包装脚本
info "6/10 重建 /usr/bin/dsh 包装脚本（--expose-internals，HMR 必需）"
rm -f /data/data/com.termux/files/usr/bin/dsh
cat > /data/data/com.termux/files/usr/bin/dsh <<'EOF'
#!/data/data/com.termux/files/usr/bin/sh
exec node --expose-internals /data/data/com.termux/files/usr/lib/node_modules/@deepseek-ai/dsh/lib/bin.js "$@"
EOF
chmod +x /data/data/com.termux/files/usr/bin/dsh
dsh --version && ok "dsh $(dsh --version) 可用"

# ----------------------------------------------------- 7/10 启动/停止脚本
info "7/10 写入启动/停止脚本到 $INSTALL_DIR"
mkdir -p "$INSTALL_DIR/storage"
cp "$SCRIPT_DIR/start_dsh.sh" "$INSTALL_DIR/start_dsh.sh"
cp "$SCRIPT_DIR/stop_dsh.sh"  "$INSTALL_DIR/stop_dsh.sh"
chmod +x "$INSTALL_DIR/start_dsh.sh" "$INSTALL_DIR/stop_dsh.sh"
# restart_dsh_now.sh 供补丁后重启用；它的输出里会打印带 token 的 Web UI URL。
if [ -f "$SCRIPT_DIR/restart_dsh_now.sh" ]; then
  cp "$SCRIPT_DIR/restart_dsh_now.sh" "$INSTALL_DIR/restart_dsh_now.sh"
  chmod +x "$INSTALL_DIR/restart_dsh_now.sh"
fi

# 权限模式：Android 上 bwrap/landlock 命名空间沙箱不可用，bash 工具需
# danger-full-access 才能执行。写入 profile 配置层 + 启动脚本环境变量双保险。
PROFILE_PATCH="$HOME/.dsh/profiles/web/cordis.patch.yml"
mkdir -p "$(dirname "$PROFILE_PATCH")"
if ! grep -q "danger-full-access" "$PROFILE_PATCH" 2>/dev/null; then
  cat > "$PROFILE_PATCH" <<'YAML'
# Android/Termux：bwrap/landlock 命名空间沙箱不可用，需放开权限模式才能执行 bash 工具
- id: sandbox-policy
  config:
    mode: danger-full-access
YAML
  ok "  权限模式已写入 $PROFILE_PATCH"
fi

# ------------------------------------------------------- 8/10 前端适配(可选)
# 8/9 步是可选增强：失败只告警，不能让整轮安装中止（否则连完成横幅都看不到）。
if [ -f "$SCRIPT_DIR/apply-frontend.sh" ]; then
  info "8/10 应用前端移动端适配"
  bash "$SCRIPT_DIR/apply-frontend.sh" || warn "前端适配失败（可稍后手动重跑 apply-frontend.sh）"
fi

# -------------------------------------------------- 9/10 JS 性能补丁(可选)
if [ -f "$SCRIPT_DIR/apply-js-patches.sh" ]; then
  info "9/10 应用 JS 性能补丁（静态资源 immutable 缓存）"
  # 把已验证版本列表传下去，避免两个脚本各自硬编码基线而漂移
  DSH_PATCH_BASELINE="$DSH_VERSION_VERIFIED" \
    bash "$SCRIPT_DIR/apply-js-patches.sh" || warn "JS 性能补丁未全部应用（不影响基本使用，详见 apply-js-patches.sh 输出）"
fi

# ------------------------------------------------- 版本记录（便于事后排查）
# 回答"这台机器是哪次、用哪个版本的脚本、装的哪个 dsh"——升级或换机后不用靠记忆。
mkdir -p "$INSTALL_DIR"
GIT_REV="$(git -C "$SCRIPT_DIR" rev-parse --short HEAD 2>/dev/null || true)"
GIT_DIRTY=""
if [ -n "$GIT_REV" ] && ! git -C "$SCRIPT_DIR" diff --quiet 2>/dev/null; then GIT_DIRTY=" (有未提交改动)"; fi
cat > "$INSTALL_DIR/INSTALL-INFO.txt" <<EOF
setup.sh 版本    : v${SETUP_VERSION}${GIT_REV:+  git ${GIT_REV}${GIT_DIRTY}}
安装目标 spec    : ${DSH_NPM}
目标来源         : ${DSH_VERSION_SOURCE}
实际安装版本     : ${INSTALLED_VERSION:-未知}
已验证版本列表   : ${DSH_VERSION_VERIFIED}
权限模式         : danger-full-access
安装时间         : $(date '+%F %T %z')
EOF
ok "  安装记录已写入 $INSTALL_DIR/INSTALL-INFO.txt"

# ---------------------------------------------------------------- 10/10 完成
info "10/10 完成 🎉"
cat <<EOF

安装完成！接下来：
  1) 启动服务:    bash ~/dsh/start_dsh.sh
  2) 打开 Chrome: http://127.0.0.1:3080
  3) 在 Web UI 的 Models 页面填入 DeepSeek API Key
  4) 停止服务:    bash ~/dsh/stop_dsh.sh

注意：
  - 服务只监听 127.0.0.1（本机），不走局域网。
  - API Key 存于 ~/.dsh/.credentials.yaml（0600 权限），不进日志。
  - danger-full-access 关闭了进程沙箱（Android 无替代），仅建议个人设备使用。
  - 升级 dsh 或 Node 后需重跑本脚本。
EOF
