#!/data/data/com.termux/files/usr/bin/bash
# 停止 DeepSeek Harness (dsh) Web 服务
set -u

# 匹配 bin.js 时用 [i] 规避 pkill 匹配到自身
if pkill -f "deepseek-ai/dsh/lib/bi[n].js" 2>/dev/null; then
  echo "[dsh] 已停止"
else
  echo "[dsh] 未发现运行中的 dsh"
fi

# 监督进程会自行发现 dsh 退出并记录退出码；这里顺手收掉残留的监督进程
pkill -f "dsh-supervise[.]sh" 2>/dev/null && echo "[dsh] 已停止监督进程"

# 释放 start_dsh.sh 申请的唤醒锁，否则 Termux 会一直被禁止休眠、白耗电
if command -v termux-wake-unlock >/dev/null 2>&1; then
  termux-wake-unlock 2>/dev/null && echo "[dsh] 已释放唤醒锁"
fi
