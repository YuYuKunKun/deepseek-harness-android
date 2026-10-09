/**
 * dsh-agent-notify — host half.
 *
 * 浏览器半边通过 exports["./client"] 提供（由 package.json 的 `dsh.client` 声明，
 * 见 @deepseek-ai/dsh-client-modules）。宿主这一侧原本什么都不做，现在只负责一件事：
 * **提供一个 service worker 脚本**，因为移动端浏览器无法用 `new Notification()` 发系统
 * 通知，只能走 `ServiceWorkerRegistration.showNotification()`，而 dsh 前端不自带 SW。
 *
 * 该路由的要点：
 *   · `Service-Worker-Allowed: /` —— 允许注册到 scope "/"。必须控制 dsh 页面本身，
 *     notificationclick 才能 focus 回它。
 *   · `Cache-Control: no-cache` —— SW 更新靠字节比对，长缓存会让新版本永远装不上。
 *   · 文件每次请求现读（体积很小），改完源码刷新页面即可生效。
 */
import { readFile } from 'node:fs/promises'
import { fileURLToPath } from 'node:url'
import { dirname, join } from 'node:path'

/** 与客户端半边（lib/client.js）约定的注册地址，改这里必须同步改那边。 */
export const SERVICE_WORKER_PATH = '/plugins/dsh-agent-notify/sw.js'

const SERVICE_WORKER_FILE = join(dirname(fileURLToPath(import.meta.url)), 'sw.js')

/** 读取并返回 SW 脚本内容；读不到时给出可诊断的 500 而不是静默 404。 */
async function readServiceWorker() {
  return await readFile(SERVICE_WORKER_FILE)
}

/**
 * 注册 SW 路由。
 * @param ctx - 已注入 webServer 的宿主上下文。
 */
function registerServiceWorkerRoute(ctx) {
  ctx.effect(
    () =>
      ctx.webServer.register({
        kind: 'exact',
        path: SERVICE_WORKER_PATH,
        handler: async (req, res) => {
          if (req.method !== 'GET' && req.method !== 'HEAD') {
            res.writeHead(405, { allow: 'GET, HEAD' })
            res.end()
            return
          }
          let body
          try {
            body = await readServiceWorker()
          } catch (error) {
            res.writeHead(500, { 'content-type': 'text/plain; charset=utf-8' })
            res.end(`dsh-agent-notify: cannot read sw.js: ${String(error && error.message)}`)
            return
          }
          res.writeHead(200, {
            'content-type': 'text/javascript; charset=utf-8',
            // 允许 scope "/"：必须能控制 dsh 页面本身
            'service-worker-allowed': '/',
            // SW 靠字节比对更新，绝不能被长缓存
            'cache-control': 'no-cache, no-store, must-revalidate',
            'content-length': String(body.byteLength),
          })
          res.end(req.method === 'HEAD' ? undefined : body)
        },
      }),
    'agent-notify: service worker route',
  )
}

/** Host plugin body. */
export function apply(ctx) {
  // 只能走 inject：cordis 的上下文对**未注入**的服务直接取值会抛错
  //   Error: cannot get property "webServer" without inject
  // 所以不能用 `ctx.webServer !== undefined` 之类的探测。inject 会在 webServer
  // 就绪（或晚于本插件就绪）时再执行回调。
  ctx.inject(['webServer'], registerServiceWorkerRoute)
}
