# Android 原生插件替代实现

`node-addon-require-builtin-android-arm64/` 是一个**手写的 JS 假包**，用来顶替上游缺失的
android-arm64 原生绑定。`setup.sh` 第 3.2 步会在每次安装后自动把它复制到
`<dsh>/node_modules/node-addon-require-builtin-android-arm64/`。

## 为什么需要

`0.1.7` 起，上游新增了原生插件 `node-addon-require-builtin`，由 `dsh-app-boot` 的
`internalModules()` 加载 —— 这是**启动必经路径**，而且是一句**没有 try/catch 的裸 require**：

```js
const addon = createRequire(import.meta.url)("node-addon-require-builtin");
const esmModule = addon.requireBuiltin("internal/modules/esm/loader");
const cjsModule = addon.requireBuiltin("internal/modules/cjs/loader");
const cjsHelpers = addon.requireBuiltin("internal/modules/helpers");
const esmUtils = addon.requireBuiltin("internal/modules/esm/utils");
const esmResolve = addon.requireBuiltin("internal/modules/esm/resolve");
```

缺了它，dsh 直接死在启动阶段：

```
dsh: fatal uncaught exception: Error: dsh: host preparation failed:
No usable native binding found for node-addon-require-builtin-android-arm64 (auto)
  attempts: [{ source: 'optional-package',
               request: 'node-addon-require-builtin-android-arm64',
               error: Cannot find module '...' }]
```

而补上它有三重障碍（均已核实）：

| 障碍 | 事实 |
|---|---|
| 没有 android 预编译 | `node-addon-require-builtin@0.1.6`（已是最高版）的 `optionalDependencies` 只有 `darwin-arm64/x64`、`linux-arm64/x64-gnu`、`win32-arm64/x64/ia32-msvc` |
| 平台包不存在 | `node-addon-require-builtin-android-arm64` 在 npm 上 **404** |
| 无法自行编译 | 发布包的 `files` 仅含 `lib/`，**无 `src/`、无 `binding.gyp`**，`package.json` **连 repository 字段都没有** —— 拿不到源码 |

加载器（`node-addon-native-custom-loader@0.1.6`，被精确锁定）只有 `optional-package` 与
`local-build` 两条来源，**没有 JS 回退**；唯一可用的口子是 `NARB_DISABLE_OPTIONAL_PACKAGE`
之类的环境变量，但那只会让它更快失败。

## 为什么这样做是等价的

原生绑定的**唯一实际用途**就是取 Node 内部模块（上面 5 个 `internal/modules/*`）。
而这在 `--expose-internals` 下用 `require` 就能做到 —— dsh 的包装脚本
`$PREFIX/bin/dsh`（由 `setup.sh` 第 6 步生成）本来就带该参数，HMR 也需要它：

```sh
exec node --expose-internals .../@deepseek-ai/dsh/lib/bin.js "$@"
```

所以本实现**没有引入任何新能力**：它暴露的就是同一个内部模块加载器本身。

## 加载器会做哪些校验（本实现必须全过）

`node-addon-native-custom-loader` 的 `validateLoadedBinding()`：

1. 导出对象要有 `requireBuiltin` / `isAllowedInternalId` / `getNativeBindingInfo` 三个函数；
2. `getNativeBindingInfo()` 返回对象的 `mode` / `backend` / `abi` 必须是字符串；
3. `backend` 必须是 `'napi'` 或 `'nodeabi'`；
4. **`abi` 必须精确等于 `buildAbiTag(backend, ...)`** —— 对 `nodeabi` 即
   `node-v${process.versions.modules}`。

第 4 条是最容易踩的：abi 不能在源码里写死，必须运行时从 `process.versions.modules` 取
（不同 Node 小版本的 ABI 号不同）。本实现即如此。

`dsh-app-boot` 随后还会校验 6 项内部模块形状：

```
esm.resolveSync / esm.getOrCreateModuleJob（或 legacy 的 getModuleJobForImport）
cjsModule.Module._resolveFilename / cjsHelpers.getCjsConditions
esmUtils.getDefaultConditions / esmResolve.defaultResolve
```

在本机（Node v26.10.0，`nodeabi` = `node-v147`）与真机（Node v26.4.0）上均验证通过。

## 怎么验证它还在生效

```bash
# 假包是否就位
ls /data/data/com.termux/files/usr/lib/node_modules/@deepseek-ai/dsh/node_modules/node-addon-require-builtin-android-arm64/

# 真机直接跑一遍校验（需要 --expose-internals）
node --expose-internals -e '
const b = require("/data/data/com.termux/files/usr/lib/node_modules/@deepseek-ai/dsh/node_modules/node-addon-require-builtin-android-arm64");
console.log(b.getNativeBindingInfo());
console.log(typeof b.requireBuiltin("internal/modules/esm/loader").getOrInitializeCascadedLoader().resolveSync);
'
```

## 已知限制

- **每次 `npm install` 都会被清掉**（它不在任何依赖树里，npm 视为 extraneous），所以必须靠
  `setup.sh` 第 3.2 步重新放回。手动升级 dsh 后若忘记重跑 `setup.sh`，dsh 会起不来。
- 依赖 `--expose-internals`。若哪天包装脚本去掉了该参数，本实现会失效（`require('internal/...')`
  将抛 `MODULE_NOT_FOUND`）。
- 上游若改为发布 android 预编译或开源该插件的源码，应当**优先改用官方产物**，本目录即可删除。
