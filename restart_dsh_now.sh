#!/data/data/com.termux/files/usr/bin/bash
set -u
LOG="$HOME/dsh/storage/dsh_restart.log"
mkdir -p "$HOME/dsh/storage"
umask 077
echo "$(date '+%F %T') restart begin" >> "$LOG"
pkill -f "deepseek-ai/dsh/lib/bin.js" 2>/dev/null
for i in $(seq 1 20); do
  pgrep -f "deepseek-ai/dsh/lib/bin.js" >/dev/null 2>&1 || break
  sleep 1
done
pkill -9 -f "deepseek-ai/dsh/lib/bin.js" 2>/dev/null
sleep 1
cd "$HOME/dsh" || exit 1
export DSH_PERMISSION_MODE=danger-full-access
nohup dsh web >> "$LOG" 2>&1 &
NEWPID=$!
echo "$NEWPID" > "$HOME/dsh/storage/dsh.pid"
echo "$(date '+%F %T') restarted pid=$NEWPID" >> "$LOG"
for i in $(seq 1 90); do
  if curl -s -o /dev/null --max-time 2 http://127.0.0.1:3080; then
    echo "$(date '+%F %T') ready on 3080" >> "$LOG"
    # Web UI 有浏览器认证：首次访问必须带本进程的启动 token 才能换取签名 cookie。
    # 本脚本不打开浏览器，所以把带 token 的 URL 打出来（Termux 里可直接点按）。
    AUTH_URL="$(sed -n 's/^dsh web: \(http[^ ]*\).*/\1/p' "$LOG" | tail -1)"
    if [ -n "$AUTH_URL" ]; then
      echo "$AUTH_URL"
    else
      echo "[!] 已就绪，但日志中还没出现带 token 的 URL；稍后可从 $LOG 取，或直接跑 start_dsh.sh"
    fi
    exit 0
  fi
  sleep 1
done
echo "$(date '+%F %T') TIMEOUT waiting for 3080" >> "$LOG"
exit 1
