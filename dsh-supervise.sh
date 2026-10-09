#!/data/data/com.termux/files/usr/bin/bash
# =============================================================================
# [dsh-android] dsh 的独立会话监督进程
# -----------------------------------------------------------------------------
# 由 start_dsh.sh 通过 setsid 启动，负责：
#   1. 启动 dsh web；
#   2. 每分钟采一次内存/swap/dsh RSS（便于事后判断"卡死"还是"被杀"）；
#   3. 等 dsh 退出后**记录退出码与终止信号**——这是原脚本缺失的关键信息。
#
# 为什么整个文件要存在：
#   实测 8 次启动里，dsh 与旧脚本里那个监控子 shell **同时消失**，且监控进程
#   一次都没能写下"进程已退出"那行。也就是说不是 dsh 崩了，而是**启动它的那个
#   Termux 会话被回收**——内核按进程组回收，dsh 因为在同一进程组里被一起带走。
#   仅用 nohup 只能挡 SIGHUP，挡不住这种情况；必须 setsid 另开会话。
#
# 用法（由 start_dsh.sh 调用，一般不手工执行）：
#   setsid bash dsh-supervise.sh <dsh日志> <mem日志> <pid文件> [保留份数]
# =============================================================================
set -u

LOG="${1:?需要 dsh 日志路径}"
MEMLOG="${2:?需要内存日志路径}"
PIDFILE="${3:?需要 pid 文件路径}"
KEEP="${4:-10}"

export DSH_PERMISSION_MODE="${DSH_PERMISSION_MODE:-danger-full-access}"

# 彻底脱离终端：setsid 已经给了新会话，这里再把三个标准流钉死，
# 保证会话被销毁时不会有任何"终端已消失"的副作用。
exec >>"$LOG" 2>&1 </dev/null

echo "=== [supervise] 启动 dsh $(date '+%F %T')  (会话 sid=$$) ==="

dsh web &
pid=$!
echo "$pid" >"$PIDFILE" 2>/dev/null
echo "[supervise] dsh pid=$pid"

# 以 5 秒为节拍检查存活，每 60 秒才写一条内存采样。
# 这样 dsh 一旦退出，最多 5 秒就会被察觉并记录退出码——早期版本用 sleep 60 轮询，
# 退出后最长要等一分钟才落盘，期间若监督进程被一并清掉就永远看不到原因。
TICK=5
SAMPLE_EVERY=$((60 / TICK))
tick=0
while kill -0 "$pid" 2>/dev/null; do
  if [ $((tick % SAMPLE_EVERY)) -eq 0 ]; then
    {
      printf '%s ' "$(date '+%F %T')"
      free -m 2>/dev/null | awk 'NR==2{printf "mem_used=%sMB free=%sMB avail=%sMB ",$3,$4,$7}'
      free -m 2>/dev/null | awk 'NR==3{printf "swap_used=%sMB ",$3}'
      awk -v p="$pid" '$1=="VmRSS:"{printf "dsh_rss=%s%s ",$2,$3}' "/proc/$pid/status" 2>/dev/null
      echo
    } >>"$MEMLOG" 2>/dev/null
    # 先裁到 KEEP-1 份再写本次 → 目录里恒为 ≤KEEP 份
    ls -1t "$(dirname "$MEMLOG")"/mem-*.log 2>/dev/null | tail -n +"$KEEP" | while IFS= read -r f; do
      rm -f "$f"
    done
  fi
  tick=$((tick + 1))
  sleep "$TICK"
done

# dsh 是本站的子进程，所以 wait 能拿到真实退出状态
wait "$pid" 2>/dev/null
rc=$?
if [ "$rc" -gt 128 ]; then
  echo "$(date '+%F %T') dsh 已退出 rc=$rc（被信号 $((rc - 128)) 终止：137=KILL 多为系统回收，143=TERM，129=HUP）" >>"$MEMLOG" 2>/dev/null
else
  # 注意：dsh 自己注册了 SIGTERM/SIGINT 处理器并优雅退出，因此"被 kill -TERM"
  # 通常记为 rc=0 而不是 143，别把它误读成"正常结束"。
  echo "$(date '+%F %T') dsh 已退出 rc=$rc（自行退出或启动失败；dsh 捕获 SIGTERM 后会以 0 优雅退出）" >>"$MEMLOG" 2>/dev/null
fi
echo "[supervise] dsh 已退出 rc=$rc $(date '+%F %T')"
