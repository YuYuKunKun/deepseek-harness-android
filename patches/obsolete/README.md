# 已作废的 JS 补丁（不要再应用）

这 4 个补丁写于 **dsh 0.1.0-rc.6 / rc.7**，目标是当时的
`dsh-host-apiproxy` + `dsh-client-runtime` 架构。npm 的 `latest`
标签现在指向 **0.1.5-rc.1**，上游已把 history / 实时流整条链路重写，
这些补丁的上下文与目标包都已不存在，强行移植等于重复实现上游功能。

保留它们只为记录历史，`apply-js-patches.sh` 不会再尝试应用。

## 逐个说明（结论均基于 0.1.5-rc.1 源码核实）

| 补丁 | 结论 | 依据 |
|---|---|---|
| `01-apiproxy-history-slim.patch` | **已被上游取代** | 见下 |
| `02-runtime-incremental-resync.patch` | **上游已实现** | `dsh-api-gateway/lib/client.js` 的 `RemoteJournalStream` |
| `03-connection-history-schema.patch` | **随之作废** | 只为承载 01 引入的 `chunkFiltered` 标志 |
| `05-client-modules-cache.patch` | **上游已实现** | `dsh-client-modules/lib/index.js` 已用 `IMMUTABLE_CACHE` |

### 01 的两半分别是什么结局

**(a) 过滤 `assistant/chunk` 流 —— 已无对象。**
0.1.5-rc.1 的持久化日志里**不再存**逐 token 的 chunk 记录：assistant 增量改由
「瞬时帧」承载，客户端在 `dsh-api-session-controller` 的 `ClientAssistantStream`
里合成 `assistant/live-chunk`，其 seq 甚至是分数
（`durableCursor + 1 - 1/(transientInGap + 1)`），从不进入 history 页。
全树搜索 `assistant/chunk` 只剩两个 session-format 迁移包（用于读旧日志）。
既然 history 页里没有 chunk 噪声，当年的「窗口瘦身」前提已不成立。

**(b) 超大 tool 结果截断 —— 已上游化为正式插件。**
- `dsh-compaction-tool-result-pruner`：marker 字符串与本补丁**完全一致**
  （`"\n\n[... tool result middle pruned ...]\n\n"`），按 `thresholdChars/headChars/tailChars`
  对 tool 结果做 head+marker+tail 裁剪（默认 8192/4096/1024），作用于模型可见的
  compaction 表面。
- `dsh-spill-policy`：按 `maxInlineBytes` 把超大纯文本结果落盘为 spill 产物，
  另有第二臂**同时约束持久化日志**的副本。

两者都是**可选插件**（默认 profile 不加载，参见各自 `Config`）。若在手机上仍嫌
history 响应过大，正确做法是在 profile 里启用它们，而不是继续维护这份补丁：

```yaml
# ~/.dsh/profiles/web/cordis.patch.yml（示例，按需调整阈值）
- id: spill-policy
  config:
    maxInlineBytes: 262144
```

### 02 为什么不需要了

0.1.5-rc.1 的 `RemoteJournalStream`（`@deepseek-ai/dsh-api-gateway/client`）已原生提供
补丁 02 想手工实现的能力，且更完整：

- 重连时**保留已发布窗口**（"The domain retains its published window during reconnection"）；
- `resumeCursor` 断点续传，新 generation 的开页追上游标后才发布替换；
- seq 不连续时走 `acceptEntry → replaceThrough` 的 gap repair，并把期间到达的
  条目排队合并（`mergeReplacement`）；
- generation 切换（`opened`/`superseded`）保证跨越重连的修复不会写坏窗口。

这比当年在 `dsh-client-runtime` 里加的 `stitching` / `liveBuffer` / `repairGap`
手写版本更严谨，因此补丁 02 属于**重复实现**。

### 若将来上游又改版

判断某补丁是否仍需应用的最快方式：在其目标包内搜索补丁引入的**唯一标记**，
例如 `chunkFiltered`、`IMMUTABLE_CACHE`。搜得到就说明上游已实现。
