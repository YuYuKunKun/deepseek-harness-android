/**
 * dsh-agent-notify — rendered settings-page tests.
 *
 * Runs in a single jsdom window installed as the global environment (react-dom
 * requires a browser global), loads the bundle, registers the settings
 * section, then actually renders the page component with react-dom and drives
 * its controls.
 */
'use strict'
const { JSDOM } = require('jsdom')
const fs = require('fs')
const path = require('path')
const vm = require('vm')

const bundleSrc = fs.readFileSync(path.join(__dirname, '..', 'lib', 'client.js'), 'utf8')
const SETTINGS_KEY = 'dsh.agentNotify.settings.v3'

// Global browser environment before react-dom is loaded.
const dom = new JSDOM('<!DOCTYPE html><html><head></head><body></body></html>', {
  url: 'http://localhost/',
  pretendToBeVisual: true,
  runScripts: 'outside-only',
})
global.window = dom.window
global.document = dom.window.document
Object.defineProperty(global, 'navigator', {
  value: dom.window.navigator,
  configurable: true,
})
global.IS_REACT_ACT_ENVIRONMENT = true

const React = require('react')
const { createRoot } = require('react-dom/client')
const { act } = React

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

const tick = () => new Promise((resolve) => setTimeout(resolve, 10))

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
  const sessions = { list, binding: () => undefined, open: () => {} }
  const registered = []
  const ctx = {
    sessions,
    slots: {
      register: (options, component) => {
        registered.push({ options, component })
        return () => {}
      },
    },
    effect: () => () => {},
    on: () => () => {},
  }
  ctx._registered = registered
  return ctx
}

let notifications = []

class FakeNotification {
  constructor(title, options) {
    this.title = title
    this.options = options
    this.onclick = null
    notifications.push(this)
  }
  close() {}
}

function loadBundle(opts = {}) {
  const { window } = dom
  window.document.body.innerHTML = ''
  window.document.head.querySelectorAll('style[data-plugin="dsh-agent-notify"]').forEach((s) => s.remove())
  window.localStorage.clear()
  if (opts.preseed) {
    window.localStorage.setItem(SETTINGS_KEY, JSON.stringify(opts.preseed))
  }
  notifications = []
  window.focus = () => {}
  FakeNotification.permission = 'granted'
  FakeNotification.requestCalls = 0
  FakeNotification.requestPermission = () => {
    FakeNotification.requestCalls++
    return window.Promise.resolve('granted').then((p) => {
      FakeNotification.permission = p
      return p
    })
  }
  window.Notification = FakeNotification

  let captured = null
  window.__ModuleLoader__ = { load: (bundle) => { captured = bundle } }
  vm.runInContext(bundleSrc, dom.getInternalVMContext())
  if (captured === null) throw new Error('bundle did not register via __ModuleLoader__.load')
  const exportsObj = captured.factory((spec) => {
    if (spec === '@deepseek-ai/dsh-client-runtime/client') return {}
    if (spec === 'react') return React
    throw new Error('unexpected require: ' + spec)
  })
  return { window, bundle: exportsObj }
}

function harness(opts) {
  const h = loadBundle(opts)
  const ctx = makeCtx()
  h.bundle.apply(ctx)
  ctx.sessions.list._set({
    phase: 'ready',
    ids: ['s1'],
    byId: { s1: { id: 's1', displayTitle: '会话一', running: true } },
    current: 's1',
  })
  return { ...h, ctx }
}

;(async () => {
  console.log('card: rendered settings page interactions')
  const { window, ctx } = harness()
  const entry = ctx._registered[0]
  check('section registered', entry !== undefined && entry.options.name === 'settings.section')
  check('label is 任务提示', entry.options.label() === '任务提示')

  const mount = window.document.createElement('div')
  window.document.body.appendChild(mount)
  const root = createRoot(mount)
  await act(async () => {
    root.render(React.createElement(entry.component))
  })

  const card = mount.querySelector('.dan-card')
  check('page rendered', card !== null)
  const labels = Array.from(card.querySelectorAll('label')).map((l) => l.textContent.trim())
  check('page has all rows',
    ['启用通知', '包含子代理通知'].every((l) => labels.includes(l)) &&
    labels.some((l) => l.includes('系统通知')))
  check('no sound/volume rows', !card.textContent.includes('音量') && !card.textContent.includes('提示音'))
  check('page has test button',
    Array.from(card.querySelectorAll('button')).some((b) => b.textContent.includes('测试通知')))
  check('permission label shows granted', card.textContent.includes('已授权'))
  check('version line shows v1.0.7', card.textContent.includes('v1.0.7'))

  // Click the test-notification button -> immediate system notification.
  const testBtn = Array.from(card.querySelectorAll('button')).find((b) => b.textContent.includes('测试通知'))
  await act(async () => {
    testBtn.dispatchEvent(new window.MouseEvent('click', { bubbles: true }))
  })
  check('test notification sent', notifications.length === 1)
  check('test notification title', notifications[0].title === '测试通知')

  // Uncheck "启用通知" -> persisted; later events stay silent.
  const enabledCb = card.querySelector('input[type=checkbox]')
  await act(async () => {
    enabledCb.dispatchEvent(new window.MouseEvent('click', { bubbles: true }))
  })
  const stored = JSON.parse(window.localStorage.getItem(SETTINGS_KEY))
  check('enabled persisted as false', stored.enabled === false)
  ctx.sessions.list._set({
    phase: 'ready',
    ids: ['s1'],
    byId: { s1: { id: 's1', displayTitle: '会话一', running: true } },
    current: 's1',
  })
  ctx.sessions.list._set({
    phase: 'ready',
    ids: ['s1'],
    byId: { s1: { id: 's1', displayTitle: '会话一', running: false } },
    current: 's1',
  })
  check('no notification while disabled', notifications.length === 1)

  // Re-enable, then switch system mode to 'off' -> silent again.
  // (Re-enabling sends a "通知已开启" confirmation, so note the count first.)
  await act(async () => {
    enabledCb.dispatchEvent(new window.MouseEvent('click', { bubbles: true }))
  })
  const beforeOff = notifications.length
  const select = card.querySelector('select')
  await act(async () => {
    select.value = 'off'
    select.dispatchEvent(new window.MouseEvent('change', { bubbles: true }))
  })
  const stored2 = JSON.parse(window.localStorage.getItem(SETTINGS_KEY))
  check('system mode persisted as off', stored2.system === 'off')
  ctx.sessions.list._set({
    phase: 'ready',
    ids: ['s1'],
    byId: { s1: { id: 's1', displayTitle: '会话一', running: true } },
    current: 's1',
  })
  ctx.sessions.list._set({
    phase: 'ready',
    ids: ['s1'],
    byId: { s1: { id: 's1', displayTitle: '会话一', running: false } },
    current: 's1',
  })
  check('off mode sent nothing', notifications.length === beforeOff)

  // Console diagnostic hook: installed, exposes version, test() sends and
  // returns a result string (counts as one more notification).
  check('debug hook installed', window.__agentNotify !== undefined && window.__agentNotify.version === '1.0.7')
  check('debug hook settings', window.__agentNotify.settings().system === 'off')
  const beforeHook = notifications.length
  const hookResult = window.__agentNotify.test()
  check('debug hook test returns string', typeof hookResult === 'string')
  check('debug hook test sent a notification', notifications.length === beforeHook + 1)

  await act(async () => { root.unmount() })
  console.log(`\n${pass} passed, ${fail} failed`)
  process.exit(fail === 0 ? 0 : 1)
})()
