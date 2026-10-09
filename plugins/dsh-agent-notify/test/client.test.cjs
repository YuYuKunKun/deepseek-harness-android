/**
 * dsh-agent-notify — client bundle behavior tests (jsdom).
 *
 * Loads lib/client.js inside a jsdom window, captures the __ModuleLoader__
 * handoff, materializes the factory with a fake require (real React), applies
 * the plugin against a controllable sessions-list double, and asserts
 * system-notification / sound / settings-section behavior.
 *
 * All notices go through the Notification API — there are no in-page cards,
 * and the settings page registers into the official `settings.section` slot.
 */
'use strict'
const { JSDOM } = require('jsdom')
const fs = require('fs')
const path = require('path')
const vm = require('vm')
const React = require('react')

const bundleSrc = fs.readFileSync(path.join(__dirname, '..', 'lib', 'client.js'), 'utf8')
const SETTINGS_KEY = 'dsh.agentNotify.settings.v3'

let pass = 0
let fail = 0

function check(name, cond, extra) {
  if (cond) {
    pass++
    console.log('  ok  ' + name)
  } else {
    fail++
    console.error('  FAIL ' + name + (extra !== undefined ? ' :: ' + JSON.stringify(extra) : ''))
  }
}

function makeListStore() {
  const listeners = new Set()
  let snapshot = { phase: 'loading', ids: [], byId: {}, current: undefined }
  return {
    getSnapshot: () => snapshot,
    subscribe: (fn) => {
      listeners.add(fn)
      return () => listeners.delete(fn)
    },
    _set(next) {
      snapshot = next
      for (const fn of Array.from(listeners)) fn()
    },
  }
}

function makeCtx() {
  const list = makeListStore()
  const opens = []
  const sessions = {
    list,
    binding: () => undefined,
    open: (id) => { opens.push(id) },
  }
  const registered = []
  const slots = {
    register: (options, component) => {
      registered.push({ options, component })
      return () => {}
    },
  }
  const effects = []
  const eventHandlers = {}
  const ctx = {
    sessions,
    slots,
    effect: (cb) => {
      effects.push(cb)
      return () => {}
    },
    on: (evt, fn) => {
      ;(eventHandlers[evt] = eventHandlers[evt] || []).push(fn)
      return () => {}
    },
  }
  ctx._effects = effects
  ctx._eventHandlers = eventHandlers
  ctx._opens = opens
  ctx._registered = registered
  return ctx
}

/** Load the bundle in a fresh jsdom window; returns harness handles. */
function loadBundle(opts = {}) {
  const dom = new JSDOM('<!DOCTYPE html><html><head></head><body></body></html>', {
    url: 'http://localhost/',
    pretendToBeVisual: true,
    runScripts: 'outside-only',
  })
  const { window } = dom
  // Optional pre-seeded settings (written before the bundle reads them).
  if (opts.preseed) {
    window.localStorage.setItem(SETTINGS_KEY, JSON.stringify(opts.preseed))
  }
  let captured = null
  window.__ModuleLoader__ = { load: (bundle) => { captured = bundle } }
  vm.runInContext(bundleSrc, dom.getInternalVMContext())
  if (captured === null) throw new Error('bundle did not register via __ModuleLoader__.load')
  // jsdom does not implement window.focus(); stub it to keep stderr clean.
  window.focus = () => {}

  // Fake Notification API: records instances; permission is mutable per test.
  const notifications = []
  class FakeNotification {
    constructor(title, options) {
      this.title = title
      this.options = options
      this.onclick = null
      notifications.push(this)
    }
    close() {}
  }
  FakeNotification.permission = 'granted'
  FakeNotification.requestCalls = 0
  // Return a promise from the bundle's own realm (vm context) so promise
  // resolution follows the same microtask chain as in a real browser.
  FakeNotification.requestPermission = () => {
    FakeNotification.requestCalls++
    return window.Promise.resolve('granted').then((p) => {
      FakeNotification.permission = p
      return p
    })
  }
  window.Notification = FakeNotification

  const exportsObj = captured.factory((spec) => {
    if (spec === '@deepseek-ai/dsh-client-runtime/client') return {}
    if (spec === 'react') return React
    throw new Error('unexpected require: ' + spec)
  })

  return { window, dom, bundle: exportsObj, notifications }
}

/** Override the jsdom document.hidden read (page visibility). */
function setHidden(window, hidden) {
  Object.defineProperty(window.document, 'hidden', {
    configurable: true,
    get: () => hidden,
  })
}

/** Fresh harness: bundle + ctx, applied, baseline list ready. */
function harness(opts) {
  const h = loadBundle(opts)
  const ctx = makeCtx()
  h.bundle.apply(ctx)
  // Baseline: one session already running.
  ctx.sessions.list._set({
    phase: 'ready',
    ids: ['s1'],
    byId: {
      s1: { id: 's1', displayTitle: '会话一', running: true },
    },
    current: 's1',
  })
  return { ...h, ctx }
}

const settle = (ctx, id, extra = {}) => {
  ctx.sessions.list._set({
    phase: 'ready',
    ids: [id],
    byId: { [id]: { id, displayTitle: '会话一', running: false, ...extra } },
    current: id,
  })
}

// ---------------------------------------------------------------- scenario 1: baseline
;(function baselineDoesNotNotify() {
  console.log('scenario 1: baseline does not notify')
  const { notifications } = harness()
  check('no system notification on baseline', notifications.length === 0)
})()

// ---------------------------------------------------------------- scenario 2: done
;(function runningToStoppedNotifies() {
  console.log('scenario 2: running -> stopped notifies done')
  const { window, ctx, notifications } = harness()
  settle(ctx, 's1')
  check('one system notification', notifications.length === 1)
  check('title is 任务完成', notifications[0].title === '任务完成')
  check('body mentions session title', notifications[0].options.body.includes('会话一'))
  check('no tag (fresh bubble every time)', notifications[0].options.tag === undefined)
  settle(ctx, 's1')
  check('no double notification', notifications.length === 1)
  check('no in-page card was created', window.document.querySelectorAll('.dan-toast').length === 0)
})()

// ---------------------------------------------------------------- scenario 3: pending
;(function pendingQuestionNotifies() {
  console.log('scenario 3: pending question / approval notify')
  const { window, ctx, notifications } = harness()
  ctx.sessions.list._set({
    phase: 'ready',
    ids: ['s1'],
    byId: { s1: { id: 's1', displayTitle: '会话一', running: true, pendingInteraction: 'question' } },
    current: 's1',
  })
  check('ask notification sent', notifications.length === 1)
  check('ask title', notifications[0].title === '需要你的回答')
  ctx.sessions.list._set({
    phase: 'ready',
    ids: ['s1'],
    byId: { s1: { id: 's1', displayTitle: '会话一', running: true, pendingInteraction: 'question' } },
    current: 's1',
  })
  check('no re-notify for same pending', notifications.length === 1)
  ctx.sessions.list._set({
    phase: 'ready',
    ids: ['s1'],
    byId: { s1: { id: 's1', displayTitle: '会话一', running: true, pendingInteraction: 'approval' } },
    current: 's1',
  })
  check('approval notification sent', notifications.length === 2)
  check('approval title', notifications[1].title === '需要你的批准')
  check('no in-page cards', window.document.querySelectorAll('.dan-toast').length === 0)
})()

// ---------------------------------------------------------------- scenario 4: subagent skipped
;(function subagentSkippedByDefault() {
  console.log('scenario 4: subagent rows skipped by default')
  const { ctx, notifications } = harness()
  ctx.sessions.list._set({
    phase: 'ready',
    ids: ['s1'],
    byId: { s1: { id: 's1', displayTitle: '子代理', running: true, origin: 'subagent' } },
    current: 's1',
  })
  ctx.sessions.list._set({
    phase: 'ready',
    ids: ['s1'],
    byId: { s1: { id: 's1', displayTitle: '子代理', running: false, origin: 'subagent' } },
    current: 's1',
  })
  check('no notification for subagent', notifications.length === 0)
})()

// ---------------------------------------------------------------- scenario 5: no synthesized sound
;(function noSynthesizedSound() {
  console.log('scenario 5: no synthesized sound code remains')
  const { window, ctx, notifications } = harness()
  settle(ctx, 's1')
  check('notification sent without any audio', notifications.length === 1)
  check('no AudioContext ever created', window.AudioContext === undefined)
  const style = window.document.getElementById('dsh-agent-notify-style')
  check('no sound options in page copy', style === null || !style.textContent.includes('音量'))
  // Bundle must not reference the audio APIs at all.
  check('bundle has no audio code', !bundleSrc.includes('AudioContext') && !bundleSrc.includes('createOscillator'))
})()

// ---------------------------------------------------------------- scenario 6: settings section registration
;(function settingsSectionRegistered() {
  console.log('scenario 6: settings section registered as first-level page')
  const { ctx } = harness()
  check('slots.register called once', ctx._registered.length === 1)
  const entry = ctx._registered[0]
  check('slot name is settings.section', entry.options.name === 'settings.section')
  check('slot id is agent-notify', entry.options.id === 'agent-notify')
  check('section label is 任务提示', typeof entry.options.label === 'function' && entry.options.label() === '任务提示')
  check('section is a React component', typeof entry.component === 'function')
  // Disabling via preseed stops notifications.
  const h2 = harness({ preseed: { enabled: false } })
  settle(h2.ctx, 's1')
  check('preseed-disabled sends nothing', h2.notifications.length === 0)
})()

// ---------------------------------------------------------------- scenario 7: reconnect resets baseline
;(function reconnectResetsBaseline() {
  console.log('scenario 7: connection/reset re-baselines without notifying')
  const { ctx, notifications } = harness()
  ctx._eventHandlers['connection/reset'].forEach((fn) => fn())
  settle(ctx, 's1')
  check('no notification after reconnect baseline', notifications.length === 0)
})()

// ---------------------------------------------------------------- scenario 8: background mode
;(function systemNotifyBackgroundMode() {
  console.log('scenario 8: background mode — hidden sends, visible suppresses')
  const { window, ctx, notifications } = harness({ preseed: { system: 'background' } })
  setHidden(window, false)
  settle(ctx, 's1')
  check('no notification while visible (background mode)', notifications.length === 0)
  ctx.sessions.list._set({
    phase: 'ready',
    ids: ['s1'],
    byId: { s1: { id: 's1', displayTitle: '会话一', running: true } },
    current: 's1',
  })
  setHidden(window, true)
  settle(ctx, 's1')
  check('notification while hidden (background mode)', notifications.length === 1)
})()

// ---------------------------------------------------------------- scenario 9: off / always modes
;(function systemNotifyModes() {
  console.log('scenario 9: off / always modes')
  const { ctx, notifications } = harness({ preseed: { system: 'off' } })
  settle(ctx, 's1')
  check('off mode sent nothing', notifications.length === 0)
  const h2 = harness({ preseed: { system: 'always' } })
  settle(h2.ctx, 's1')
  check('always mode sent while visible', h2.notifications.length === 1)
})()

// ---------------------------------------------------------------- scenario 10: permission denied
;(function systemNotifyPermissionDenied() {
  console.log('scenario 10: denied permission never sends')
  const { window, ctx, notifications } = harness()
  setHidden(window, true)
  window.Notification.permission = 'denied'
  settle(ctx, 's1')
  check('no notification when denied', notifications.length === 0)
})()

// ---------------------------------------------------------------- scenario 11: no floating UI
;(function noFloatingUi() {
  console.log('scenario 11: no floating buttons / corner UI')
  const { window, ctx, notifications } = harness()
  settle(ctx, 's1')
  check('notification still sent', notifications.length === 1)
  check('no .dan-toast elements in DOM', window.document.querySelectorAll('.dan-toast').length === 0)
  check('no sidebar entry injected', window.document.querySelector('[data-dsh-agent-notify-entry]') === null)
  check('no floating corner button', window.document.querySelector('.dan-float-btn') === null)
  check('no .dan-ui container mounted', window.document.getElementById('dsh-agent-notify-container') === null)
})()

// ---------------------------------------------------------------- scenario 12: auto permission request
;(function autoPermissionRequest() {
  console.log('scenario 12: first gesture asks for permission')
  const { window, ctx, notifications } = harness()
  window.Notification.permission = 'default'
  window.document.dispatchEvent(new window.MouseEvent('pointerdown', { bubbles: true }))
  // Wait a macro task so every microtask (bundle realm included) has drained
  // before asserting — vm-realm and Node-realm microtask queues are separate
  // in jsdom, so Promise.then timing is not reliable here.
  return new Promise((resolve) => {
    setTimeout(() => {
      check('requestPermission called once', window.Notification.requestCalls === 1)
      check('granted confirmation notification sent', notifications.length === 1)
      check('confirmation title', notifications[0].title === '系统通知已授权')
      resolve()
    }, 0)
  })
})()

// ---------------------------------------------------------------- scenario 13: click opens session
;(function notificationClickOpensSession() {
  console.log('scenario 13: clicking a notification opens the owning session')
  const { ctx, notifications } = harness()
  settle(ctx, 's1')
  check('one notification', notifications.length === 1)
  notifications[0].onclick()
  check('session opened on click', ctx._opens.length === 1 && ctx._opens[0] === 's1')
})()

// ---------------------------------------------------------------- summary
// Wait a macro task so async scenarios have run their assertions too.
setTimeout(() => {
  console.log(`\n${pass} passed, ${fail} failed`)
  process.exit(fail === 0 ? 0 : 1)
}, 50)
