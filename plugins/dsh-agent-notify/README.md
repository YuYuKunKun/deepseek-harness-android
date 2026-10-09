# dsh-agent-notify

[![npm version](https://img.shields.io/npm/v/dsh-agent-notify)](https://www.npmjs.com/package/dsh-agent-notify)
[![License](https://img.shields.io/npm/l/dsh-agent-notify)](LICENSE)
[![CI](https://github.com/chidaic/dsh-agent-notify/actions/workflows/ci.yml/badge.svg)](https://github.com/chidaic/dsh-agent-notify/actions)

DSH Web GUI 的「任务完成通知」插件：当 agent 执行完任务 / 回复完对话、或需要你做出选择（提问 / 批准 / 审阅计划）时，弹出 **Windows 系统级通知**（通知中心气泡，声音为 Windows 系统通知音）——无论你在哪个窗口都能看到。**纯系统提示：无网页内弹窗、无合成音、无额外 UI 按钮。**

纯浏览器端插件（host half 为空），无需构建工具，手写 bundle 直接加载。

## 功能

- **任务完成通知**：会话从 `running` 变为停止时，发送「任务完成」系统通知。
- **需要输入通知**：agent 提问（`question`）时发送「需要你的回答」。
- **批准 / 计划审阅通知**：`approval` / `plan-review` 时发送「需要你的批准 / 请审阅计划」。
- **系统级通知**（浏览器 Notification API，类 Codex CLI 体验）：Windows 通知中心弹出气泡，声音为 **Windows 系统通知音**（由 Windows 设置控制）；点击气泡会聚焦页面并打开对应会话。三种模式可选：`不发送` / `后台时发送` / `始终发送`（默认）。
- **自动授权**：首次点击页面时自动请求通知权限（浏览器会询问，选「允许」即可）；也可在设置页手动授权。
- **通知内容**：会话标题 + 该会话最后一条 assistant 回复的前 90 字摘要（仅当会话窗口已打开时）。每条通知都是全新气泡（不带 `tag`——Windows 上 Chrome 对同 tag 通知只静默更新不弹新气泡，这是本插件历史上「通知消失」的根因，已移除）。
- **设置入口 = DSH 官方设置界面的一级页面**：设置 → **任务提示**（注册进官方 `settings.section` slot：启用通知、是否包含子代理通知、系统通知模式、权限状态与授权、**发送测试通知**（一键诊断，显示具体结果）。设置保存在 `localStorage`（`dsh.agentNotify.settings.v3`）。页面顶部显示插件版本与当前生效配置，便于排查旧缓存。
- **诊断**：设置页的「发送测试通知」无视发送模式直接弹一条系统通知，并显示结果——「已发送 ✓」却没弹，说明问题在浏览器/Windows 通知设置（地址栏站点权限、Windows 设置 → 系统 → 通知 → 浏览器通知开关与通知声音、专注助手），与插件逻辑无关。
- **防误报**：
  - 页面加载 / 重连后，第一个列表快照只作为基线，不重放历史完成事件；
  - 重连期间发生的完成不会在恢复连接后误报；
  - 同一 pending 状态不重复通知；
  - 子代理会话默认不通知（可在设置中开启）。

## 安装

从 npm（推荐，安装走 tarball 秒级完成）：

```sh
dsh plugin --profile web add dsh-agent-notify
```

从 GitHub：

```sh
dsh plugin --profile web add github:chidaic/dsh-agent-notify
```

浏览器端 bundle 变更后**刷新页面即可**（`/plugins/dsh-agent-notify/client.js` 每次读取最新文件；若遇到旧缓存，用 Ctrl+Shift+R 硬刷新）。

## 配置

无 host 配置。浏览器端设置位于官方设置界面 →「任务提示」页面，持久化于 localStorage。

## 目录结构

```
dsh-agent-notify/
├── package.json          # dsh.client 声明（inject: dsh-client-runtime, platform: web）
├── cordis.patch.yml      # 插件行（bundle patch）
├── LICENSE               # MIT
├── CHANGELOG.md
├── .github/workflows/ci.yml  # 每次 push/PR 自动跑 npm test
├── lib/
│   ├── index.js          # host half（空 apply）
│   └── client.js         # 浏览器 bundle（手写，无构建步骤）
└── test/
    ├── client.test.cjs   # jsdom 行为测试（通知/注册/防误报/无音频代码）
    └── card.test.cjs     # 设置页真实渲染与交互测试（react-dom）
```

## 开发

- 修改 `lib/client.js` 后运行 `node --check lib/client.js` 验证语法。
- 运行 `npm test` 执行全部 jsdom 行为测试与设置页渲染测试。
- 每次行为变更请递增 `BUNDLE_VERSION`（设置页会显示，用于诊断浏览器缓存旧 bundle）。

## 许可

MIT © [chidaic](https://github.com/chidaic)
