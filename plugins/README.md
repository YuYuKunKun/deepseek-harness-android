# plugins/

本目录存放**随仓库分发的第三方 dsh 插件**。与 `patches/` 下的补丁不同，这里的插件是完整源码，
会随 `setup.sh` 一起部署。

## dsh-agent-notify

上游：[chidaic/dsh-agent-notify](https://github.com/chidaic/dsh-agent-notify)（MIT）· 本地版本 **1.0.0**

作用：agent 完成任务、或需要你输入/批准时，通过浏览器 Notification API 弹出**系统级通知**
（无网页内弹窗、无合成音），点击气泡直达会话。纯浏览器端插件，宿主侧 `apply` 为空。

### ⚠️ 本目录内的副本带有本地修复

**上游 npm 上发布的 1.0.0 在 0.1.5 及以后的 dsh 上无法加载**，因此不能直接 `dsh plugin add dsh-agent-notify`。
原因：它的客户端 bundle 顶部有一句

```js
factory: (require) => {
  require('@deepseek-ai/dsh-client-runtime/client')   // 该包在 0.1.1-rc.2 之后已被上游移除
```

而客户端模块加载器的 `require` 对未注册模块是**直接抛错**（`dsh-client-modules` 的 `makeRequire`：
既不在平台 seed、也没有已注册 factory 时 `throw`）。这行位于 factory 顶部、在 `apply` 自身的
`try/catch` **之前**，一旦抛出整个模块加载失败，插件完全不工作。

本地改动（两处，见 `git log` / 与上游 diff）：

| 文件 | 改动 |
|---|---|
| `lib/client.js` | 把那句 require 包进 `try/catch`——旧架构仍生效，新架构不再炸 |
| `package.json` | `dsh.client.inject` 由死包 `@deepseek-ai/dsh-client-runtime` 改为现代包：`@deepseek-ai/dsh-api-session-controller`（提供 `ctx.sessions`）、`@deepseek-ai/dsh-client-ui-slots`（提供 `ctx.slots`）、`@deepseek-ai/dsh-client-connection`（`connection/reset` 事件源） |

`try/catch` 是向后兼容的，不影响旧架构上的行为。**若上游修好，应改用官方版本并删除本目录副本。**

### 安装（本地目录，pnpm `link:`）

```bash
mkdir -p ~/dsh-plugins
cp -r plugins/dsh-agent-notify ~/dsh-plugins/
dsh plugin --profile web add "link:$HOME/dsh-plugins/dsh-agent-notify"
bash ~/dsh/start_dsh.sh     # 重启后生效
```

`dsh plugin` 是 pnpm 的透传，所以 `link:` / `file:` / `github:` 等 pnpm 协议都可用。
`add` 会同时把它加进 profile 的 `dsh.profile.bundles`，从而应用插件自带的 `cordis.patch.yml`
（它插入 `id: agent-notify` 那一行）。

用完后可在「设置 → 任务提示」里调整通知选项（`window.__agentNotify.test()` 可发一条测试通知）。

## dsh-web-mobile

上游：[mexiaosqwq/dsh-web-mobile](https://github.com/mexiaosqwq/dsh-web-mobile)（MIT）

**本仓库不维护、也不 vendor 它的副本**——上游持续维护且已适配新架构（v3.0.5 的 peer 范围已含
`>=0.2.0-rc.1 <0.3.0-0`），直接从 npm 或 GitHub 安装即可：

```bash
dsh plugin --profile web add dsh-web-mobile
# 或
dsh plugin --profile web add github:mexiaosqwq/dsh-web-mobile
```

> 若 `plugins/dsh-web-mobile/` 出现在工作区里，那只是本地用来比对的 clone，未纳入版本控制。
