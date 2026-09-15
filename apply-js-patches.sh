#!/data/data/com.termux/files/usr/bin/bash
# =============================================================================
# 应用 JS 性能补丁到已安装的 dsh 运行时 bundle
# -----------------------------------------------------------------------------
# 活补丁（patches/ 下，基线 dsh 0.1.5-rc.1，rc.2 亦验证通过）：
#   04-frontend-static-cache.patch   静态资源 immutable 缓存头：/assets/ 下的
#                                    内容哈希产物永久缓存，整页重载不再重复下载
#                                    ~4.7MB bundle；index.html / manifest 仍每次校验。
#
# 已作废补丁（不再应用，见 patches/obsolete/README.md）：
#   01-apiproxy-history-slim       assistant/chunk 已不进持久化日志（改为客户端瞬时帧）；
#                                  超大 tool 结果截断已上游化为
#                                  dsh-compaction-tool-result-pruner / dsh-spill-policy
#   02-runtime-incremental-resync  上游 RemoteJournalStream 已原生保留窗口 + gap repair
#   03-connection-history-schema   仅为承载 01 的 chunkFiltered 标志，随之作废
#   05-client-modules-cache        上游 dsh-client-modules 已用 IMMUTABLE_CACHE
#
# 幂等：已应用的补丁自动跳过。活补丁无法应用时报错退出（dsh 版本可能又变了，
# 请对照 patches/obsolete/README.md 的方法重新核对）。
# =============================================================================
set -euo pipefail

DSH_PACKAGES_DIR="${DSH_PACKAGES_DIR:-/data/data/com.termux/files/usr/lib/node_modules/@deepseek-ai/dsh/node_modules/@deepseek-ai}"
HERE="$(cd "$(dirname "$0")" && pwd)"
PATCHES=(04-frontend-static-cache)

[ -d "$DSH_PACKAGES_DIR" ] || { echo "[apply-js-patches] 未找到 dsh 安装目录: $DSH_PACKAGES_DIR"; exit 1; }

# 打印 dsh 版本：补丁对不上时，这是第一个要看的信息。
DSH_DIR="$(dirname "$(dirname "$DSH_PACKAGES_DIR")")"
DSH_VER="$(node -e 'try{console.log(require(process.argv[1]).version)}catch{}' "$DSH_DIR/package.json" 2>/dev/null || true)"
echo "[apply-js-patches] dsh 版本：${DSH_VER:-未知}（活补丁基线 0.1.5-rc.1）"

applied=0; skipped=0; failed=0
for name in "${PATCHES[@]}"; do
  p="$HERE/patches/$name.patch"
  [ -f "$p" ] || { echo "  [FAIL] 缺少补丁文件 $p"; failed=$((failed+1)); continue; }
  if (cd "$DSH_PACKAGES_DIR" && patch -p1 -N -s -R --dry-run -i "$p" < /dev/null) >/dev/null 2>&1; then
    echo "  [skip] $name 已应用"
    skipped=$((skipped+1))
  elif (cd "$DSH_PACKAGES_DIR" && patch -p1 -N -s --dry-run -i "$p" < /dev/null) >/dev/null 2>&1; then
    if (cd "$DSH_PACKAGES_DIR" && patch -p1 -N -s -i "$p" < /dev/null) >/dev/null 2>&1; then
      echo "  [ok]   $name 已应用"
      applied=$((applied+1))
    else
      echo "  [FAIL] $name 应用失败"
      failed=$((failed+1))
    fi
  else
    echo "  [FAIL] $name 无法应用（dsh ${DSH_VER:-?} 与补丁基线不匹配？）"
    echo "         排查：在目标包内搜索补丁引入的唯一标记（如 IMMUTABLE_CACHE），"
    echo "               搜到即说明上游已自行实现，可把补丁移入 patches/obsolete/。"
    failed=$((failed+1))
  fi
done

[ -d "$HERE/patches/obsolete" ] && echo "  [note] patches/obsolete/ 下的补丁已作废（上游已实现或架构重写），有意跳过；详见该目录 README.md"

echo "[apply-js-patches] 完成：应用 $applied，跳过 $skipped，失败 $failed"
[ "$failed" -eq 0 ]
