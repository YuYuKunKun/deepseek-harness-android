# Changelog

## [1.0.0] — 2026-08-22

First open-source release. Behavior equals the locally developed `v1.0.7` bundle.

- Task-completion system notifications: session flips `running -> stopped` → "任务完成".
- Needs-your-input notifications: `question` / `approval` / `plan-review` pending states.
- Windows-level notifications via the browser Notification API; clicking a bubble
  focuses the page and opens the owning session.
- Send modes: `off` / `background` (hidden page only) / `always`.
- First-level settings page in the official Settings surface (Settings → 任务提示),
  persisted in `localStorage` (`dsh.agentNotify.settings.v3`).
- Auto permission request on the first user gesture; test-notification diagnostic.
- Anti-false-positive baseline handling across page load and connection resets.
- Subagent sessions excluded by default (toggleable in settings).
- jsdom behavior tests + rendered settings-page tests (`npm test`).
