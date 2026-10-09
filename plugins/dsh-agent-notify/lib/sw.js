/* =============================================================================
 * [dsh-agent-notify] Service worker
 * -----------------------------------------------------------------------------
 * 为什么需要它：移动端浏览器（Chrome for Android 等）的 `new Notification()`
 * 构造器会直接抛 TypeError，规范/实现层面只能改用
 * `ServiceWorkerRegistration.showNotification()`。见 MDN 与 Chrome issue #481856。
 * 而 dsh 前端本身不注册任何 service worker，所以本插件自带一个。
 *
 * 由插件宿主半边（lib/index.js）在 `/plugins/dsh-agent-notify/sw.js` 提供，
 * 并带 `Service-Worker-Allowed: /` 头，使本 SW 能以 scope="/" 控制整站
 * （必须控制 dsh 页面，notificationclick 才能 focus 到它）。
 *
 * ⚠️ 刻意**不注册 fetch 处理函数**：不拦截、不缓存任何请求，
 *    只负责安装/激活与通知点击转发，从而对 dsh 的正常运行零影响。
 * ========================================================================== */

const CLICK_MESSAGE = 'dsh-agent-notify:click'

self.addEventListener('install', (event) => {
  // 新版本立即进入 waiting → active，避免用户要刷新两次才生效
  event.waitUntil(self.skipWaiting())
})

self.addEventListener('activate', (event) => {
  // 立刻接管已打开的页面，无需等下次导航
  event.waitUntil(self.clients.claim())
})

self.addEventListener('notificationclick', (event) => {
  event.notification.close()

  const data = event.notification.data || {}
  const sessionId = typeof data.sessionId === 'string' ? data.sessionId : null

  event.waitUntil(
    (async () => {
      const clientList = await self.clients.matchAll({
        type: 'window',
        includeUncontrolled: true,
      })

      // 优先复用已经打开的 dsh 页面；找不到就新开一个
      const target = clientList.find((client) => client.url && client.url.indexOf('://') !== -1)
      if (target) {
        try {
          await target.focus()
        } catch (error) {
          /* focus 可能被拒（例如不在用户手势上下文），忽略 */
        }
        try {
          target.postMessage({ type: CLICK_MESSAGE, sessionId })
        } catch (error) {
          /* 忽略 */
        }
        return
      }

      const opened = await self.clients.openWindow('./')
      if (opened && sessionId) {
        try {
          opened.postMessage({ type: CLICK_MESSAGE, sessionId })
        } catch (error) {
          /* 忽略 */
        }
      }
    })(),
  )
})
