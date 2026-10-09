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
#
# ⚠️ 关于"跑一阵就没了"：实测 8 次启动里，dsh 与旧脚本里的监控子 shell **同时消失**，
#    监控进程一次都没能写下"进程已退出"。即不是 dsh 崩了，而是**启动它的那个 Termux
#    会话被回收**，dsh 因处于同一进程组被一起带走。仅 nohup 只能挡 SIGHUP，挡不住
#    按进程组回收，所以 dsh 必须经 setsid 进入**独立会话**（见文末），并由
#    dsh-supervise.sh 记录真实退出码/信号。
set -u

PORT=3080
URL="http://127.0.0.1:${PORT}"
BASE="$HOME/dsh"
STAMP="$(date +%Y%m%d-%H%M%S)"
LOG_DIR="$BASE/storage/logs"
LOG_FILE="$LOG_DIR/dsh-$STAMP.log"     # 每次启动写新文件（不再覆盖旧日志）
LATEST_LINK="$BASE/storage/dsh.log"    # 软链到最新日志，保持旧脚本/token 提取逻辑可用
MEMLOG="$LOG_DIR/mem-$STAMP.log"
PIDFILE="$BASE/storage/dsh.pid"
KEEP_LOGS=10
mkdir -p "$BASE/storage" "$LOG_DIR"
umask 077

# 只保留最近 KEEP_LOGS 份启动日志 / 内存采样
cleanup_logs() {
  for pat in 'dsh-*.log' 'mem-*.log'; do
    ls -1t "$LOG_DIR"/$pat 2>/dev/null | tail -n +$((KEEP_LOGS + 1)) | while IFS= read -r f; do
      rm -f "$f"
    done
  done
}
cleanup_logs

# Android/Termux 无 bwrap/landlock，需放开沙箱权限模式才能执行 bash 工具
export DSH_PERMISSION_MODE=danger-full-access

if ! command -v dsh >/dev/null 2>&1; then
  echo "[dsh] 未找到 dsh 命令，请先运行 setup.sh"
  exit 1
fi

# dsh 会打印一行：dsh web: http://127.0.0.1:3080/?token=XXX (LAN: ...)
# 本脚本每次启动写 storage/logs/dsh-<时间戳>.log（保留最近 10 份），
# 并把 storage/dsh.log 软链到最新那份；restart_dsh_now.sh 则追加写 dsh_restart.log。
# 所以在两个日志里取最近写入的那个的最后一行即可。
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

# --------------------------------------------------------------- 唤醒锁
# Android 在息屏/后台时会冻结甚至回收 Termux，dsh 随之消失且日志里不留痕迹。
# 持有 wake lock 是让长连接与后台进程存活的前提。需要 Termux:API 应用 + termux-api 包，
# 缺失时只告警不阻塞启动。
if command -v termux-wake-lock >/dev/null 2>&1; then
  if termux-wake-lock 2>/dev/null; then
    echo "[dsh] 已获取唤醒锁（termux-wake-lock）"
  else
    echo "[!]  termux-wake-lock 调用失败（可能未授予 Termux:API 权限）"
  fi
else
  echo "[!]  未安装 termux-wake-lock —— 需 Termux:API 应用 + pkg install termux-api。"
  echo "     否则系统可能在息屏/后台时冻结或回收 Termux。另建议在系统设置里"
  echo "     为 Termux 关闭电池优化（一加/OPPO 等 ROM 尤其激进）。"
fi

# ------------------------------------------------- 启动前环境快照（便于事后排查）
{
  echo "=== dsh 启动 $(date '+%F %T') ==="
  free -m 2>/dev/null | head -3
  echo "-- 内存占用 Top5 (RSS KB) --"
  ps -eo rss,comm 2>/dev/null | sort -rn | head -6
} >"$LOG_FILE"

# ------------------------------------------------- 以独立会话启动（关键）
# setsid：让监督进程成为**新会话的首进程且无控制终端**，从而脱离启动它的那个
# Termux 会话的进程组。这是 dsh 能在会话关闭后继续存活的核心。
# 监督进程负责每分钟采内存，并在 dsh 退出时记录退出码/信号（旧脚本缺这条信息）。
SUPERVISE="$BASE/dsh-supervise.sh"
[ -f "$SUPERVISE" ] || SUPERVISE="$HOME/deepseek-harness-android/dsh-supervise.sh"
if [ ! -f "$SUPERVISE" ]; then
  echo "[!]  找不到 dsh-supervise.sh（应在 $BASE/ 或仓库目录），回退为简单的 nohup 启动"
  echo "     注意：这样启动的 dsh 仍留在当前会话进程组，会话关闭时可能被一起回收。"
  setsid nohup dsh web >>"$LOG_FILE" 2>&1 </dev/null &
  DSH_PID=$!
else
  setsid bash "$SUPERVISE" "$LOG_FILE" "$MEMLOG" "$PIDFILE" "$KEEP_LOGS" &
  DSH_PID=$!
fi
ln -sfn "$LOG_FILE" "$LATEST_LINK" 2>/dev/null || cp -f "$LOG_FILE" "$LATEST_LINK" 2>/dev/null
cleanup_logs    # 新建后再裁一次，保证「最新 10 份」（含本次）
echo "[dsh] 启动中 (监督进程 pid $DSH_PID)... 日志: $LOG_FILE"

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
