/**
 * dsh-agent-notify — host half.
 *
 * This plugin is pure browser-side capability: the empty apply exists so the
 * row appears in the host cordis.yml / Loader, while the browser half ships
 * through exports["./client"], discovered from the package.json `dsh.client`
 * declaration (see @deepseek-ai/dsh-client-modules).
 */

/** Host plugin body — this package contributes nothing host-side. */
export function apply() {}
