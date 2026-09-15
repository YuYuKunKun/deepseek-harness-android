#!/data/data/com.termux/files/usr/bin/bash
# 启动 DeepSeek Harness (dsh) 原生 Web UI 并在本机 Chrome 打开
#
# ⚠️ 关于 token：dsh 的 Web UI 有浏览器认证。首次访问必须带上进程启动 token
#    （dsh 启动时打印的 "dsh web: http://127.0.0.1:3080/?token=XXX"），
#    它用于种下 30 天有效的签名 cookie；之后浏览器凭 cookie 访问裸地址即可。
#    token 换 cookie 后服务端会 302 到干净的 "/"，所以地址栏里看不到 token
#    是正常的 —— 不代表 token 没传过去。
#    token 每个 dsh 进程一个，因此本脚本从启动日志里取回它，
#    而不是打开裸 URL（无 cookie 时裸 URL 只会返回 401）。
set -u

PORT=3080
URL="http://127.0.0.1:${PORT}"
BASE="$HOME/dsh"
LOG_FILE="$BASE/storage/dsh.log"
mkdir -p "$BASE/storage"
umask 077

# Android/Termux 无 bwrap/landlock，需放开沙箱权限模式才能执行 bash 工具
export DSH_PERMISSION_MODE=danger-full-access

if ! command -v dsh >/dev/null 2>&1; then
  echo "[dsh] 未找到 dsh 命令，请先运行 setup.sh"
  exit 1
fi

# dsh 会打印一行：dsh web: http://127.0.0.1:3080/?token=XXX (LAN: ...)
# dsh 可能由 start_dsh.sh（写 dsh.log，截断）或 restart_dsh_now.sh
# （写 dsh_restart.log，追加）启动，所以两个日志都看，取最近写入的那个里的最后一行。
auth_url() {
  for f in $(ls -t "$BASE/storage/dsh.log" "$BASE/storage/dsh_restart.log" 2>/dev/null); do
    local u
    u="$(sed -n 's/^dsh web: \(http[^ ]*\).*/\1/p' "$f" 2>/dev/null | tail -1)"
    if [ -n "$u" ]; then printf '%s\n' "$u"; return 0; fi
  done
  return 1
}

open_ui() {
  local target
  if target="$(auth_url)"; then
    echo "[dsh] 打开（带 token）: $target"
    termux-open-url "$target"
  else
    echo "[!]  日志里还没有带 token 的 URL，先打开裸地址；若页面 401，"
    echo "     几秒后重跑本脚本，或手动取 URL："
    echo "     grep -o 'http://127.0.0.1:3080/?token=[^ ]*' $LOG_FILE | tail -1"
    termux-open-url "$URL"
  fi
}

# 已在运行 -> 直接打开：token 行仍在日志里，可再次换取 cookie（幂等）
if curl -s -o /dev/null --max-time 2 "$URL"; then
  echo "[dsh] 已在运行，打开 Chrome"
  open_ui
  exit 0
fi

nohup dsh web >"$LOG_FILE" 2>&1 &
echo "[dsh] 启动中 (pid $!)... 日志: $LOG_FILE"

for i in $(seq 1 30); do
  if curl -s -o /dev/null --max-time 2 "$URL"; then
    # 端口已绑定，但 "dsh web: <带 token 的 URL>" 那行可能稍晚才刷出来，最多再等 10s
    for j in $(seq 1 10); do
      auth_url >/dev/null && break
      sleep 1
    done
    echo "[dsh] 就绪，打开 Chrome"
    open_ui
    exit 0
  fi
  sleep 1
done

echo "[dsh] 启动超时，最近日志："
tail -20 "$LOG_FILE"
echo "[dsh] 若提示缺少模型密钥，请在 Web UI 的 Models 页面配置 DeepSeek API Key"
exit 1
