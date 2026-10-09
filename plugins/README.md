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

本地改动（三处）：

| 文件 | 改动 |
|---|---|
| `lib/client.js` | 把那句 require 包进 `try/catch`——旧架构仍生效，新架构不再炸 |
| `lib/client.js` | **设置页注册改用 `ctx.slots.inject('settings.section', …)`**（详见下节） |
| `package.json` | `dsh.client.inject` 由死包 `@deepseek-ai/dsh-client-runtime` 改为现代包：`@deepseek-ai/dsh-api-session-controller`（提供 `ctx.sessions`）、`@deepseek-ai/dsh-client-ui-slots`（提供 `ctx.slots`）、`@deepseek-ai/dsh-client-connection`（`connection/reset` 事件源） |

`try/catch` 是向后兼容的，不影响旧架构上的行为。**若上游修好，应改用官方版本并删除本目录副本。**

### 改动二：设置页注册必须走 `slots.inject`

上游用的是裸注册：

```js
ctx.slots.register({ name: 'settings.section', id: 'agent-notify', … }, SettingsCard)
```

但 `settings.section` 是**惰性声明**的插槽——由设置界面那个入口在挂载时才声明。而
`dsh-client-ui-slots` 的 `register()` 对未声明的插槽**直接抛错**：

```js
if (!rec?.spec) throw new Error(`slot "${options.name}" is not declared (a parent entry's children table must declare it)`);
```

插件在 `apply` 阶段就注册，那时入口尚未挂载 → 必然抛错 → 被自身 `catch` 吞掉 →
**「设置 → 任务提示」永远不出现**，表现为「插件完全没反应」。

正确写法（取自 dsh 自带文档 `packages/client/ui-settings/src/client/contract/slots.ts:57`）：

```js
ctx.slots.inject('settings.section', () => ctx.slots.register({ … }, SettingsCard))
```

`inject` 会等插槽声明后再执行回调。

### ⚠️ 移动端（Android Chrome）无法发系统通知

**这一条不是插件的 bug，是平台限制**，两个叠加的原因：

1. **`new Notification()` 在移动端浏览器会抛 `TypeError`。** MDN 明确写道：
   > This constructor throws a `TypeError` when called in nearly all mobile browsers. Instead, you need to register a service worker and use `ServiceWorkerRegistration.showNotification()`.
   （见 [MDN: Notification() constructor](https://developer.mozilla.org/en-US/docs/Web/API/Notification/Notification)、[Chrome issue #481856](https://crbug.com/481856)）
2. **替代路径也不存在**：`showNotification()` 需要 service worker，而 dsh 的前端**并未注册任何 service worker**
   （`dsh-web-frontend/dist` 里 `serviceWorker` 出现 0 次）。

所以在手机上点击「发送测试通知」会得到一条明确说明，而**不是**静默失败：

> 发送失败：本浏览器不支持 Notification 构造器。移动端只能靠 service worker 的 showNotification()
> 发系统通知，而当前 dsh 没有注册 service worker —— 故在手机上无法发系统通知（与权限设置无关）。

即：**该插件的「系统级通知」能力实际上仅限桌面端 Chrome/Edge。** 想在 Android 上用，需要给 dsh
补一个 service worker（可由插件的宿主半边注册 webServer 路由来提供，再用
`registration.showNotification()` 发送）——那是一项独立改动，尚未实现。

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

> 本仓库**不保存它的源码副本**。早期为比对曾在 `plugins/dsh-web-mobile/` 放过一份 clone，
> 已删除——需要看源码时按上面的仓库地址自行 clone 即可。
