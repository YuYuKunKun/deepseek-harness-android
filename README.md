# DeepSeek Harness for Android/Termux

> 在 **Android 手机 Termux 环境** 原生运行 [DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness) 的一键部署项目 · One-click deployment of DeepSeek Harness on **Android/Termux**.
>
> 点击下方语言标题切换 · Click a language below to view its README.

> [!IMPORTANT]
> **适配基线：deepseek-harness `0.1.5-rc.3`**（补丁集在 `rc.1` / `rc.2` / `rc.3` 上均实测通过）。
> `setup.sh` 默认安装的就是这个**已验证版本**而不是 npm `latest`，并在安装后核对实际版本（见「三、使用」的版本控制）。
>
> ⚠️ **`0.1.5-rc.1` / `0.1.5-rc.2` 目前已经装不上了**：上游 `@deepseek-ai/cordis` 于 2026-09-22 发布 `4.0.3` / `4.0.4`，
> 而这两个 dsh 版本声明 `^4.0.2`、其子包却精确要求 `4.0.2` —— npm 会把 `dsh-web-app` 那一整层依赖**嵌套**安装，
> 于是 dsh 启动时报一长串 `plugin(s) failed to load ... could not be resolved`。`rc.3` 已把 cordis 精确锁 `4.0.2`，不受影响。
>
> 早期面向 `0.1.0-rc.x` 的性能补丁多数已作废：上游重写了 history / 实时流链路并自行实现了这些优化，
> 详见 [`patches/obsolete/README.md`](patches/obsolete/README.md)。

---

<details open>
<summary><b>🇨🇳 中文</b> · 点击收起/展开中文说明</summary>

## 这是什么

在 Android 手机上原生运行 DeepSeek Harness（`@deepseek-ai/dsh`，DeepSeek 官方的 agent harness，类 Claude Code）。通过 **Web UI**（`http://127.0.0.1:3080`）在手机浏览器里使用，agent 可在手机上真实执行 bash 命令。

> ⚠️ **需要 Termux**：必须在 Android 手机的 Termux 终端里安装运行。**不要用 Google Play 版 Termux**（已过时）。

### 一、安装 Termux

- **F-Droid（推荐）**：<https://f-droid.org/en/packages/com.termux/>
- **GitHub Releases**：<https://github.com/termux/termux-app/releases>

打开 Termux 后执行 `pkg update -y`。

### 二、一键安装

```bash
pkg install -y git
git clone https://github.com/FunnelCakes/deepseek-harness-android.git
cd deepseek-harness-android
bash setup.sh
```

> 🇨🇳 **国内用户提示**：`setup.sh` 会自动测速，npm / nodejs.org 较慢时**自动切换到 npmmirror 镜像**（仅本次会话生效，不改全局配置）。若 `git clone` 很慢或超时，请先开代理/TUN，或改用镜像 clone（如 `https://gitclone.com/github.com/FunnelCakes/deepseek-harness-android.git`）。

### 三、使用

```bash
bash ~/dsh/start_dsh.sh   # 启动并自动拉起浏览器
bash ~/dsh/stop_dsh.sh    # 停止
```

打开 <http://127.0.0.1:3080>，在 **Models** 页填入你的 **DeepSeek API Key**（存于 `~/.dsh/.credentials.yaml`，0600 权限），即可开始。

**升级 / 指定 dsh 版本**：不要在 Termux 里直接 `npm install -g @deepseek-ai/dsh@x.y.z` —— 那会丢掉 `--allow-scripts`、koffi 的 `-target aarch64-linux-android30` 和 spawn.h shim，`node-pty` / `koffi` 原生模块会缺失。必须重跑 `setup.sh`。

`setup.sh` 自带**版本控制**：它默认安装一个**已实测通过补丁的版本**，而不是 npm `latest`——因为上游一改代码，就地补丁就会失配（这正是本项目历史上最频繁的故障源）。

```bash
cd ~/deepseek-harness-android

bash setup.sh                                    # 装默认已验证版本
DSH_VERSION=0.1.5-rc.3 bash setup.sh             # 指定版本
DSH_VERSION=next bash setup.sh                    # 按 npm 标签
DSH_NPM='@deepseek-ai/dsh@0.1.5-rc.3' bash setup.sh   # 完整 spec（优先级最高）
bash ~/dsh/restart_dsh_now.sh                    # 重启，并打印带 token 的 Web UI URL
```

解析优先级：`DSH_NPM` > `DSH_VERSION` > **已安装且在白名单内的版本**（重跑脚本不会把你悄悄降级）> 默认已验证版本。脚本会：

- 安装前打印目标版本、来源、是否在已验证白名单内（不在就明确告警）；
- 安装后按磁盘上的 `package.json` **核对实际装上的版本**，与请求不符或在白名单外都会告警；
- 把结果写进 `~/dsh/INSTALL-INFO.txt`（setup.sh 版本、git 版本、目标 spec、实际版本、时间），换机或升级后不必靠记忆。

白名单与默认版本定义在 `setup.sh` 顶部的 `DSH_VERSION_VERIFIED` / `DSH_VERSION_DEFAULT` 两个变量里，新增验证通过的版本时改这一处即可（`apply-js-patches.sh` 的基线由 `setup.sh` 传入，不再各自硬编码）。

### 四、setup.sh 自动修复的 Android 兼容问题

| 问题 | 现象 | 修复 |
|---|---|---|
| node-pty 无法编译 | `Undefined variable android_ndk_path` | 修补 node-gyp 缓存 `common.gypi` |
| koffi 无法编译 | `statx` 相关 `__u32` 编译错误 | `-target aarch64-linux-android30` |
| npm 拦截构建脚本 | node-pty/koffi 无产物 | `--allow-scripts` 放行 |
| `link()` 被禁（SELinux） | 会话/附件保存、write 工具新建文件报 `EACCES` | 会话发布改 `rename()`、write 新建文件回退"O_EXCL 占位+rename"、附件祖先遍历/清理容忍（`patches/patch-dsh-android-link.js`，幂等）。**⚠️ 已知问题（待设备确认）**：`dsh-attachment-local` 在 0.1.5-rc.1 上有两处 `link()`（内容寻址别名 / 不覆盖发布）**尚未覆盖**——补丁脚本只匹配旧形态 `link(temporary, target)`。被禁硬链接的 ROM 上附件保存可能仍报 `ATTACHMENT_WRITE_FAILED` |
| PTY 终端检测失败 | `unsupported on platform android` | subprocess 把 android 视同 linux |
| sharp 无法加载 | `Could not load sharp module` | 安装 `@img/sharp-wasm32` wasm 回退 |
| HMR 启动崩溃 | `--expose-internals is required` | 包装脚本加 `--expose-internals` |
| bash 工具不可用 | `SANDBOX_UNAVAILABLE` | 权限模式设 `danger-full-access` |
| 前端不适配竖屏 | 桌面布局、触控目标小等 | `apply-frontend.sh` 注入移动端 CSS/JS |
| 软键盘遮挡输入框 | 输入法弹出后输入框被键盘盖住 | `visualViewport` 跟随：键盘弹出时整页（含输入框）抬到键盘上方，收回时还原 |
| 局域网 HTTP 缺少 Web Crypto API | `crypto.randomUUID is not a function` | 注入基于 `crypto.getRandomValues()` 的 UUID v4 回退 |
| 上下文大时重进/切回卡顿 | 冷重进、从外部应用切回要等很久 | **0.1.5-rc.1 起上游已重写**：assistant 增量改为客户端瞬时帧（不再进持久化日志），`RemoteJournalStream` 原生保留窗口 + gap repair。本项目原先 3 个补丁已作废（`patches/obsolete/`） |
| 整页重载重复下载 JS | 每次刷新重下 ~4.7MB bundle | `apply-js-patches.sh` 给 `/assets/` 下内容哈希产物加 immutable 缓存头（`index.html` / manifest 仍每次校验）；插件 bundle 上游已自带 |
| PWA 沉浸模式键盘不跟随 | fullscreen 下软键盘覆盖、视口不收缩，composer 被盖住 | manifest display 改 `standalone`（需重装 PWA，恢复系统栏+正常键盘行为）|

### 五、安全说明

- 服务只监听 `127.0.0.1`（本机），不走局域网。
- API Key 存 `~/.dsh/.credentials.yaml`（0600），不进日志、不进进程环境。
- `danger-full-access` 关闭了进程沙箱（Android 无 bwrap/landlock 替代），agent 可执行任意命令——仅建议个人设备使用。
- 升级 dsh 或 Node 后需重跑 `setup.sh`。

### 六、常见问题

- **页面白屏/打不开**：确认在 Termux 环境；看日志 `~/dsh/storage/dsh.log`。
- **`AbortSignal.any is not a function`**：浏览器过旧，`apply-frontend.sh` 已注入 polyfill。
- **`crypto.randomUUID is not a function`**：局域网 HTTP 或旧版 WebView 不暴露该 API，`apply-frontend.sh` 已注入安全随机 UUID v4 回退。
- **模型没反应**：检查 Models 页 API Key 与 `~/.dsh/.credentials.yaml`。
- **换机/重装**：重跑 `bash setup.sh`。

### 七、作者测试环境与兼容性

- **测试设备**：华为 Mate 60（ALN-AL80），HarmonyOS 4.2.0（build 4.2.0.186），**无 root**，Termux（Node v26，aarch64）。
- 不同手机 / ROM 的差异可能导致额外问题，例如：部分 ROM 通过 SELinux 禁用 `link()` 系统调用（会话持久化已改用 `rename()` 修复；**附件路径见上表「已知问题」**）、命名空间沙箱权限不同、bwrap/landlock 是否可用等。
- `setup.sh` 覆盖了通用 Android 场景，但个别机型可能需要额外适配。

**欢迎提 issue / PR 适配更多环境**：如果你在其它品牌、系统版本或 root 状态下遇到问题，欢迎在 [Issues](https://github.com/FunnelCakes/deepseek-harness-android/issues) 提交，或提交 Pull Request 补充对应机型的修复。

### 参考

- [deepseek-ai/deepseek-harness](https://github.com/deepseek-ai/deepseek-harness)
- [deepseek-harness Discussion #136 — Android/Termux 部署](https://github.com/deepseek-ai/deepseek-harness/discussions/136)
- [deepseek-harness Discussion #248 — Android 禁 hardlink（link→rename 提案）](https://github.com/deepseek-ai/deepseek-harness/discussions/248)
- [Termux Wiki](https://wiki.termux.com/)

</details>

---

<details>
<summary><b>🇬🇧 English</b> · click to expand/collapse</summary>

## What is this

Run [DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness) (`@deepseek-ai/dsh`, DeepSeek's official agent harness, Claude Code–like) natively on Android. Use it through the **Web UI** at `http://127.0.0.1:3080` in your mobile browser; the agent can run real bash commands on the phone.

> ⚠️ **Termux required**: install and run inside the **Termux terminal on your Android phone**. Do **NOT** use the Google Play version (outdated).

### 1. Install Termux

- **F-Droid (recommended)**: <https://f-droid.org/en/packages/com.termux/>
- **GitHub Releases**: <https://github.com/termux/termux-app/releases>

Run `pkg update -y` after opening Termux.

### 2. One-click setup

```bash
pkg install -y git
git clone https://github.com/FunnelCakes/deepseek-harness-android.git
cd deepseek-harness-android
bash setup.sh
```

> `setup.sh` auto-detects slow npm / nodejs.org and switches to the npmmirror mirror when needed (session-only, doesn't change your global config).

### 3. Usage

```bash
bash ~/dsh/start_dsh.sh   # start & auto-open browser
bash ~/dsh/stop_dsh.sh    # stop
```

Open <http://127.0.0.1:3080>, enter your **DeepSeek API Key** in the **Models** page (stored at `~/.dsh/.credentials.yaml`, mode 0600), and start chatting.

**Upgrading / pinning a dsh version**: do **not** run `npm install -g @deepseek-ai/dsh@x.y.z` directly in Termux — that drops `--allow-scripts`, koffi's `-target aarch64-linux-android30`, and the spawn.h shim, leaving `node-pty` / `koffi` without native binaries. Re-run `setup.sh` instead.

`setup.sh` has **version control built in**: it installs a version the patch set is actually verified against, instead of whatever npm `latest` happens to be — because upstream code changes silently invalidate the in-place patches (historically this project's most frequent failure).

```bash
cd ~/deepseek-harness-android

bash setup.sh                                    # default verified version
DSH_VERSION=0.1.5-rc.3 bash setup.sh             # explicit version
DSH_VERSION=next bash setup.sh                    # npm dist-tag
DSH_NPM='@deepseek-ai/dsh@0.1.5-rc.3' bash setup.sh   # full spec (highest precedence)
bash ~/dsh/restart_dsh_now.sh                    # restart, then prints the tokenized Web UI URL
```

Precedence: `DSH_NPM` > `DSH_VERSION` > **installed version if it is on the verified list** (re-running never silently downgrades you) > the pinned default. The script:

- prints the target version, why it was chosen, and whether it is on the verified whitelist before installing (loud warning when it is not);
- verifies the **actually installed** version from `package.json` afterwards, warning if it differs from the request or is off-list;
- records everything in `~/dsh/INSTALL-INFO.txt` (setup.sh version, git revision, target spec, installed version, timestamp).

The whitelist and default live in `DSH_VERSION_VERIFIED` / `DSH_VERSION_DEFAULT` at the top of `setup.sh` — add a newly verified version in that one place (`apply-js-patches.sh` receives the baseline from `setup.sh` instead of hardcoding its own).

### 4. Android issues auto-fixed by setup.sh

| Issue | Symptom | Fix |
|---|---|---|
| node-pty fails to build | `Undefined variable android_ndk_path` | patch node-gyp cache `common.gypi` |
| koffi fails to build | `statx` `__u32` compile error | `-target aarch64-linux-android30` |
| npm blocks build scripts | no node-pty/koffi output | allow via `--allow-scripts` |
| `link()` blocked (SELinux) | `EACCES` saving sessions/attachments, and when `write` tool creates a new file | session publish uses `rename()`; new-file write falls back to "O_EXCL reserve + rename"; attachment ancestor-walk & cleanup tolerate EACCES/ENOENT (`patches/patch-dsh-android-link.js`, idempotent). **⚠️ Known issue (pending device confirmation)**: on 0.1.5-rc.1 `dsh-attachment-local` has two `link()` calls (content-addressed alias / no-replace publish) that are **not covered** — the patcher only matches the old `link(temporary, target)` shape. On ROMs that block hard links, saving attachments may still fail with `ATTACHMENT_WRITE_FAILED` |
| PTY terminal detection fails | `unsupported on platform android` | treat android as linux in subprocess |
| sharp fails to load | `Could not load sharp module` | install `@img/sharp-wasm32` wasm fallback |
| HMR crashes on start | `--expose-internals is required` | wrapper script adds `--expose-internals` |
| bash tool unavailable | `SANDBOX_UNAVAILABLE` | permission mode `danger-full-access` |
| Frontend not mobile-ready | desktop layout, small touch targets | `apply-frontend.sh` injects mobile CSS/JS |
| Soft keyboard covers the input | input box hidden behind the IME when it opens | `visualViewport`-driven follow: page (incl. input) lifts above the keyboard on open, restores on close |
| Web Crypto API missing over LAN HTTP | `crypto.randomUUID is not a function` | inject a UUID v4 fallback based on `crypto.getRandomValues()` |
| Lag re-entering / switching back with big context | cold re-entry and app-return stall for seconds | **Rewritten upstream as of 0.1.5-rc.1**: assistant deltas became client-side transient frames (never in the durable log), and `RemoteJournalStream` retains the window and repairs gaps natively. This project's 3 patches are retired (`patches/obsolete/`) |
| Page reload re-downloads JS | ~4.7MB bundles re-fetched every refresh | `apply-js-patches.sh` adds immutable cache headers to the content-hashed `/assets/` build output (`index.html` / manifest still revalidate); plugin bundles are immutable upstream |
| PWA immersive-mode keyboard not followed | soft keyboard overlays without shrinking the viewport; composer stays covered | manifest `display` → `standalone` (reinstall the PWA; restores system bars + normal keyboard behavior) |

### 5. Security notes

- The service listens only on `127.0.0.1` (local, not LAN).
- API Key is stored at `~/.dsh/.credentials.yaml` (0600), never in logs or process env.
- `danger-full-access` disables the process sandbox (no bwrap/landlock on Android); the agent can run any command — personal devices only.
- Re-run `setup.sh` after upgrading dsh or Node.

### 6. FAQ

- **Blank screen / cannot open**: make sure it's Termux; check `~/dsh/storage/dsh.log`.
- **`AbortSignal.any is not a function`**: old browser; `apply-frontend.sh` injects a polyfill.
- **`crypto.randomUUID is not a function`**: LAN HTTP and older WebViews may not expose the API; `apply-frontend.sh` injects a secure UUID v4 fallback.
- **Model not responding**: check the API Key in Models page and `~/.dsh/.credentials.yaml`.
- **Reinstall / new device**: re-run `bash setup.sh`.

### 7. Author's test environment & compatibility

- **Tested device**: Huawei Mate 60 (ALN-AL80), HarmonyOS 4.2.0 (build 4.2.0.186), **no root**, Termux (Node v26, aarch64).
- Different phones / ROMs may behave differently, e.g. some ROMs block the `link()` syscall via SELinux (session persistence is fixed by switching to `rename()`; **see the "Known issue" row above for attachments**), namespace-sandbox permissions vary, and bwrap/landlock may or may not be available.
- `setup.sh` covers the common Android cases, but specific devices may need extra tweaks.

**Issues & PRs welcome**: if you hit a problem on another brand / OS version / root state, please open an [issue](https://github.com/FunnelCakes/deepseek-harness-android/issues) or submit a pull request with a fix for your environment.

### References

- [deepseek-ai/deepseek-harness](https://github.com/deepseek-ai/deepseek-harness)
- [deepseek-harness Discussion #136 — Android/Termux deployment](https://github.com/deepseek-ai/deepseek-harness/discussions/136)
- [deepseek-harness Discussion #248 — hardlinks blocked on Android (link→rename proposal)](https://github.com/deepseek-ai/deepseek-harness/discussions/248)
- [Termux Wiki](https://wiki.termux.com/)

</details>

---

## License

MIT
