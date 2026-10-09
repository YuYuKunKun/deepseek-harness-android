/**
 * dsh-agent-notify — browser half (hand-written bundle, no build step).
 *
 * What it does:
 *   1. Subscribes to the client sessions list snapshot.
 *   2. When a session flips running:true -> false  -> "task done" system
 *      notification.
 *   3. When a session gains a pending interaction (question / approval /
 *      plan-review) -> "needs your input" system notification.
 *   4. All notices go through the OS-level notification center (browser
 *      Notification API) — no in-page popups, no synthesized sounds.
 *      Clicking a system notification focuses the page and opens the owning
 *      session. The bubble's sound is the Windows notification sound.
 *   5. Settings live as a first-level page in the official DSH settings
 *      surface (`settings.section` slot — Settings → 任务提示, the same
 *      mechanism as Settings → 宠物): notifications / subagents / system
 *      mode / permission / test button. Persisted in localStorage.
 *
 * Failure policy: nothing here may take the web shell down — every DOM
 * interaction is guarded, and subscription errors degrade to console logs.
 */
window.__ModuleLoader__.load({
  id: 'dsh-agent-notify',
  factory: (require) => {
    // 旧架构（0.1.1-rc.2 及更早）里 dsh-client-runtime 同时提供 React、会话与插槽服务，
    // 这里 require 一次是为了让它先注册。新架构（0.1.5+ / 0.2.x）已移除该包，相关能力
    // 拆成 dsh-api-session-controller / dsh-client-ui-slots 等，改由 package.json 的
    // dsh.client.inject 声明加载顺序。
    //
    // 关键：必须容错。客户端的 require 对未注册模块是**直接抛错**（见 dsh-client-modules
    // 的 makeRequire：既不在平台 seed、也无 factory 时 throw），而这行位于本 factory 顶部、
    // 在 apply 的 try/catch 之前 —— 一旦抛出，整个模块加载失败，插件完全不工作。
    try {
      require('@deepseek-ai/dsh-client-runtime/client')
    } catch (error) {
      // 新架构下该包不存在，属预期情况
      console.debug('[dsh-agent-notify] dsh-client-runtime 不存在（新架构），已跳过')
    }
    const React = require('react')
    var module = { exports: {} }
    var exports = module.exports

    /** Bump on every behavioral change; shown in the settings page for diagnosing stale bundles. */
    const BUNDLE_VERSION = '1.0.7'
    try {
      console.log('[dsh-agent-notify] bundle v' + BUNDLE_VERSION + ' loaded')
    } catch (error) { /* ignore */ }

    // ------------------------------------------------------------------ settings
    // v3: synthesized-sound options removed entirely (pure system notices).
    const SETTINGS_KEY = 'dsh.agentNotify.settings.v3'
    const DEFAULT_SETTINGS = {
      enabled: true,
      subagents: false,
      // System-level notifications (browser Notification API): 'off' never
      // sends, 'background' sends only while the page is hidden (you are in
      // another window), 'always' sends for every event.
      system: 'always',
    }

    function loadSettings() {
      const base = Object.assign({}, DEFAULT_SETTINGS)
      try {
        const raw = localStorage.getItem(SETTINGS_KEY)
        if (!raw) return base
        const parsed = JSON.parse(raw)
        if (typeof parsed.enabled === 'boolean') base.enabled = parsed.enabled
        if (typeof parsed.subagents === 'boolean') base.subagents = parsed.subagents
        if (parsed.system === 'off' || parsed.system === 'background' || parsed.system === 'always') {
          base.system = parsed.system
        }
      } catch (error) {
        console.warn('[dsh-agent-notify] settings read failed:', error)
      }
      return base
    }

    const settings = loadSettings()

    function saveSettings() {
      try {
        localStorage.setItem(SETTINGS_KEY, JSON.stringify(settings))
      } catch (error) {
        console.warn('[dsh-agent-notify] settings write failed:', error)
      }
    }

    // ---------------------------------------------------------------- card styles
    const STYLE_ID = 'dsh-agent-notify-style'

    function ensureStyle() {
      if (typeof document === 'undefined') return
      if (document.getElementById(STYLE_ID) !== null) return
      const style = document.createElement('style')
      style.id = STYLE_ID
      style.setAttribute('data-plugin', 'dsh-agent-notify')
      style.textContent = `
.dan-card { font-size: 13px; line-height: 1.5; max-width: 560px; }
.dan-card h3 { margin: 0 0 4px; font-size: 14px; font-weight: 600; }
.dan-card .dan-card-desc { margin: 0 0 10px; color: var(--dsw-alias-label-secondary, rgba(128, 128, 128, 0.9)); font-size: 12px; }
.dan-card-row { display: flex; align-items: center; justify-content: space-between; gap: 12px; padding: 6px 0; min-height: 28px; }
.dan-card-row + .dan-card-row { border-top: 1px solid var(--dsw-specific-divider, rgba(128, 128, 128, 0.15)); }
.dan-card-row > label { display: flex; align-items: center; gap: 8px; cursor: pointer; flex: 1; min-width: 0; }
.dan-card-row .dan-card-hint { font-size: 11px; color: var(--dsw-alias-label-secondary, rgba(128, 128, 128, 0.9)); }
.dan-card input[type="checkbox"] { accent-color: #4f8cff; width: 14px; height: 14px; margin: 0; cursor: pointer; flex: none; }
.dan-card select { background: var(--dsw-specific-input-bg, rgba(128, 128, 128, 0.12)); color: inherit;
  border: 1px solid var(--dsw-specific-input-border, rgba(128, 128, 128, 0.35)); border-radius: 6px;
  font-size: 12px; padding: 3px 6px; cursor: pointer; max-width: 140px; }
.dan-card button.dan-card-btn { border: 1px solid var(--dsw-specific-input-border, rgba(128, 128, 128, 0.35));
  background: transparent; color: inherit; border-radius: 6px; padding: 3px 10px; font-size: 12px; cursor: pointer; }
.dan-card button.dan-card-btn:hover { background: var(--dsw-specific-sidebar-nav-item-hover, rgba(128, 128, 128, 0.12)); }
.dan-card .dan-card-perm { font-size: 11px; color: var(--dsw-alias-label-secondary, rgba(128, 128, 128, 0.9)); white-space: nowrap; }
`
      document.head.appendChild(style)
    }

    function truncate(text, max) {
      if (text.length <= max) return text
      return text.slice(0, max - 1).trimEnd() + '…'
    }

    // ------------------------------------------------- system-level notifications
    const SYSTEM_MODES = {
      off: '不发送',
      background: '后台时发送',
      always: '始终发送',
    }

    function systemNotificationSupported() {
      return typeof window !== 'undefined' && 'Notification' in window
    }

    function systemPermission() {
      if (!systemNotificationSupported()) return 'unsupported'
      return window.Notification.permission // 'granted' | 'denied' | 'default'
    }

    /** Ask the browser for notification permission (must run from a user gesture). */
    function requestSystemPermission() {
      if (!systemNotificationSupported()) return Promise.resolve('unsupported')
      try {
        return Promise.resolve(window.Notification.requestPermission())
      } catch (error) {
        console.warn('[dsh-agent-notify] permission request failed:', error)
        return Promise.resolve('denied')
      }
    }

    /** Whether the current settings want a system notification for this event. */
    function shouldSendSystemNotification() {
      if (!settings.enabled) return false
      if (settings.system === 'off') return false
      if (settings.system === 'always') return true
      // 'background': only while the page is hidden (user is in another window).
      return typeof document !== 'undefined' && document.hidden === true
    }

    /**
     * Push a Windows/system-level notification (browser Notification API).
     * Clicking it focuses the page and opens the owning session.
     *
     * No `tag` on purpose: on Windows, Chrome replaces a still-listed
     * notification with the same tag by updating it in place — the bubble
     * never re-pops. A stale entry in the notification center therefore
     * silently swallows every later notification with that tag. Without a
     * tag every notice is a fresh bubble.
     */
    function sendSystemNotification(kind, title, detail, sessionId) {
      if (!shouldSendSystemNotification()) return
      if (systemPermission() !== 'granted') return
      try {
        const body = detail && detail !== '' ? detail : title
        const notification = new window.Notification(title, {
          body: truncate(body, 200),
        })
        notification.onclick = () => {
          try {
            window.focus()
            if (
              sessionId && ctxRef && ctxRef.sessions &&
              typeof ctxRef.sessions.open === 'function'
            ) {
              ctxRef.sessions.open(sessionId)
            }
          } catch (error) { /* ignore */ }
          try { notification.close() } catch (error) { /* ignore */ }
        }
      } catch (error) {
        console.warn('[dsh-agent-notify] system notification failed:', error)
      }
    }

    /**
     * Diagnostic: send a system notification regardless of the configured send
     * mode (permission still applies). Returns a short result string so the
     * settings page can show exactly what happened.
     */
    function sendTestNotification() {
      if (systemPermission() === 'denied') return '权限被拒绝：点地址栏 🔒 → 网站设置 → 通知 → 允许'
      if (systemPermission() === 'default') return '未授权：再点一次本按钮触发浏览器询问'
      if (systemPermission() === 'unsupported') return '浏览器不支持系统通知（请用 Edge / Chrome）'
      try {
        const notification = new window.Notification('测试通知', {
          body: '如果你看到这条消息，系统通知链路正常 ✓',
        })
        notification.onclick = () => {
          try { window.focus() } catch (error) { /* ignore */ }
          try { notification.close() } catch (error) { /* ignore */ }
        }
        return '已发送 ✓（若未弹出，检查 Windows 通知设置与专注助手）'
      } catch (error) {
        console.warn('[dsh-agent-notify] test notification failed:', error)
        return '发送失败：' + (error && error.message ? error.message : String(error))
      }
    }

    // Ask for notification permission on the first user gesture (browsers
    // require a gesture for the permission prompt). Asked at most once.
    let permissionAsked = false
    function maybeAskPermission() {
      if (permissionAsked) return
      if (!systemNotificationSupported()) return
      if (settings.system === 'off') return
      if (window.Notification.permission !== 'default') return
      permissionAsked = true
      requestSystemPermission().then((permission) => {
        if (permission === 'granted') {
          sendSystemNotification('done', '系统通知已授权', '任务完成时将弹出系统级通知')
        }
      })
    }
    if (typeof document !== 'undefined') {
      document.addEventListener('pointerdown', maybeAskPermission, { passive: true })
      document.addEventListener('keydown', maybeAskPermission, { passive: true })
    }

    // ------------------------------------------------------------------- card UI
    /**
     * The settings page registered into the official `settings.section` slot
     * (Settings → 任务提示). Built with plain createElement — no JSX, no
     * build step. Reads/writes the bundle-level settings object and persists
     * to localStorage; component state only drives re-renders.
     */
    function SettingsCard() {
      const [state, setState] = React.useState({
        enabled: settings.enabled,
        subagents: settings.subagents,
        system: settings.system,
        perm: systemPermission(),
      })
      const update = (patch) => {
        Object.assign(settings, patch)
        saveSettings()
        setState((prev) => ({ ...prev, ...patch }))
      }
      const refreshPerm = () => setState((prev) => ({ ...prev, perm: systemPermission() }))

      const e = React.createElement
      const row = (labelText, control, hint) =>
        e('div', { className: 'dan-card-row', key: labelText },
          e('label', null, control, labelText),
          hint !== undefined ? e('span', { className: 'dan-card-hint' }, hint) : null)

      const cb = (checked, onChange) =>
        e('input', {
          type: 'checkbox',
          checked,
          onChange: (ev) => onChange(ev.target.checked),
        })

      const permLabel =
        state.perm === 'granted' ? '✓ 已授权' :
        state.perm === 'denied' ? '✕ 已拒绝' :
        state.perm === 'unsupported' ? '浏览器不支持' : '未授权'

      return e('div', { className: 'dan-card' },
        e('h3', null, '通知设置（agent 完成提醒）'),
        e('p', { className: 'dan-card-desc' },
          'agent 执行完任务或需要你输入 / 批准时，弹出 Windows 系统通知（声音为系统通知音，由 Windows 设置控制）。'),
        e('p', { className: 'dan-card-desc', style: { marginTop: '4px', fontSize: '11px' } },
          '版本 v' + BUNDLE_VERSION + ' · 当前：通知 ' + (state.enabled ? '开' : '关') +
          ' · 系统通知 ' + SYSTEM_MODES[state.system] + ' · 权限 ' + permLabel),
        row('启用通知', cb(state.enabled, (v) => {
          update({ enabled: v })
          if (v) sendSystemNotification('done', '通知已开启', '任务完成时将弹出系统通知')
        })),
        row('包含子代理通知', cb(state.subagents, (v) => update({ subagents: v }))),
        row('系统通知', e('select', {
          value: state.system,
          onChange: (ev) => update({ system: ev.target.value }),
        }, Object.keys(SYSTEM_MODES).map((mode) =>
          e('option', { value: mode, key: mode }, SYSTEM_MODES[mode])))),
        row('权限', e('span', { className: 'dan-card-perm' }, permLabel),
          state.perm === 'denied' ? '被拒绝：点地址栏 🔒 图标 → 网站设置 → 通知 → 允许' : ''),
        row('测试', e('button', {
          className: 'dan-card-btn',
          onClick: () => {
            const send = () => {
              const result = sendTestNotification()
              setState((prev) => ({ ...prev, lastTest: result }))
            }
            if (systemPermission() === 'default') {
              requestSystemPermission().then(() => { refreshPerm(); send() })
            } else {
              send()
            }
          },
        }, '发送测试通知'),
          state.lastTest ? state.lastTest : '点击立即弹一条系统通知，用于诊断'),
      )
    }

    // ------------------------------------------------------------------- detection
    // SessionId -> { running, pending } baseline; transitions drive notifications.
    const prevStates = new Map()
    let ctxRef = null

    const PENDING_LABELS = {
      question: { title: '需要你的回答', kind: 'ask' },
      approval: { title: '需要你的批准', kind: 'warn' },
      'plan-review': { title: '请审阅计划', kind: 'warn' },
    }

    function pendingInfo(kind) {
      return PENDING_LABELS[kind] || { title: '需要你的操作', kind: 'ask' }
    }

    function lastAssistantText(sessionId) {
      try {
        const sessions = ctxRef && ctxRef.sessions
        if (!sessions || typeof sessions.binding !== 'function') return ''
        const binding = sessions.binding(sessionId)
        if (!binding || !binding.session || typeof binding.session.getSnapshot !== 'function') return ''
        const snap = binding.session.getSnapshot()
        const nodes = snap && Array.isArray(snap.nodes) ? snap.nodes : []
        for (let i = nodes.length - 1; i >= 0; i--) {
          const node = nodes[i]
          if (!node || node.kind !== 'assistant') continue
          const blocks = Array.isArray(node.blocks) ? node.blocks : []
          const parts = []
          for (const block of blocks) {
            if (block && block.kind === 'text' && typeof block.text === 'string' && block.text.trim() !== '') {
              parts.push(block.text.trim())
            }
          }
          const text = parts.join(' ').replace(/\s+/g, ' ').trim()
          if (text !== '') return truncate(text, 90)
        }
      } catch (error) {
        console.warn('[dsh-agent-notify] summary read failed:', error)
      }
      return ''
    }

    function handleListChange() {
      try {
        const sessions = ctxRef && ctxRef.sessions
        if (!sessions) return
        const snap = sessions.list.getSnapshot()
        if (!snap || snap.phase !== 'ready') return
        const byId = snap.byId || {}
        for (const id of Object.keys(byId)) {
          const summary = byId[id]
          if (!summary) continue
          // Subagent rows are skipped unless enabled in settings.
          if (summary.origin === 'subagent' && !settings.subagents) {
            prevStates.delete(id)
            continue
          }
          const was = prevStates.get(id)
          const nowRunning = summary.running === true
          const nowPending = summary.pendingInteraction
          if (was === undefined) {
            // First sighting (page load / reconnect baseline): record it and
            // never replay a finish. A session that appears already waiting on
            // the user is still worth a prompt — an unanswered question must
            // not be silently swallowed by the baseline.
            if (nowPending !== undefined) {
              const info = pendingInfo(nowPending)
              sendSystemNotification(info.kind, info.title, summary.displayTitle || id, id)
            }
            prevStates.set(id, { running: nowRunning, pending: nowPending })
            continue
          }
          if (was.running && !nowRunning && was.pending === undefined) {
            const title = summary.displayTitle || id
            const summaryText = lastAssistantText(id)
            const detail = summaryText !== '' ? title + ' · ' + summaryText : title
            sendSystemNotification('done', '任务完成', detail, id)
          }
          if (nowPending !== undefined && was.pending !== nowPending) {
            const info = pendingInfo(nowPending)
            sendSystemNotification(info.kind, info.title, summary.displayTitle || id, id)
          }
          prevStates.set(id, { running: nowRunning, pending: nowPending })
        }
        for (const id of Array.from(prevStates.keys())) {
          if (!(id in byId)) prevStates.delete(id)
        }
      } catch (error) {
        console.warn('[dsh-agent-notify] list change handling failed:', error)
      }
    }

    function resetBaseline() {
      // Drop every tracked state without re-baselining from the stale
      // snapshot: the list is about to be re-pulled, and the first snapshot
      // after the reset becomes the new baseline. Re-baselining from the old
      // snapshot would replay a finish (running true -> false) that happened
      // while disconnected as a false "task done".
      prevStates.clear()
    }

    // ------------------------------------------------------------------------ apply
    let applied = false

    exports.inject = ['slots', 'sessions']

    exports.apply = function apply(ctx) {
      if (applied) return
      applied = true
      ctxRef = ctx
      try {
        const sessions = ctx.sessions
        if (!sessions || !sessions.list || typeof sessions.list.subscribe !== 'function') {
          console.warn('[dsh-agent-notify] sessions list service unavailable; notifications disabled')
          return
        }
        const unsubscribe = sessions.list.subscribe(handleListChange)
        ctx.effect(() => unsubscribe, 'agent-notify: sessions list subscription')
        ctx.on('connection/reset', resetBaseline)
        // Register a first-level settings page (Settings → 任务提示), the
        // same mechanism the pet plugin uses for Settings → 宠物.
        if (ctx.slots && typeof ctx.slots.register === 'function') {
          try {
            ensureStyle()
            const unregister = ctx.slots.register({
              name: 'settings.section',
              id: 'agent-notify',
              order: 131,
              label: () => '任务提示',
            }, SettingsCard)
            ctx.effect(() => unregister, 'agent-notify: settings section')
          } catch (error) {
            console.warn('[dsh-agent-notify] settings section registration failed:', error)
          }
        } else {
          console.warn('[dsh-agent-notify] slots service unavailable; settings section not registered')
        }
        // Establish the baseline once services are ready.
        handleListChange()
        // Console diagnostic hook: `window.__agentNotify.test()` sends a test
        // notification and returns the exact result string.
        try {
          window.__agentNotify = {
            version: BUNDLE_VERSION,
            settings: () => Object.assign({}, settings),
            permission: () => systemPermission(),
            test: () => sendTestNotification(),
          }
        } catch (error) {
          console.warn('[dsh-agent-notify] debug hook install failed:', error)
        }
      } catch (error) {
        console.warn('[dsh-agent-notify] apply failed:', error)
      }
    }

    return module.exports
  },
})
