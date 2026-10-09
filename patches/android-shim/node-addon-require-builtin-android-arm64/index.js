'use strict';
/*
 * [dsh-android] node-addon-require-builtin 的 JS 替代实现
 * ---------------------------------------------------------------------------
 * 为什么需要它：上游 node-addon-require-builtin 只发布 darwin / linux / win32 的
 * 平台包（optionalDependencies），没有 android；对应平台包在 npm 上 404。发布到
 * npm 的包里也不含源码（package.json 的 files 仅含 lib/，无 src/、无 binding.gyp、
 * 无 repository 字段），所以在 Android/Termux 上既装不到、也无法自行编译。
 *
 * 而 dsh-app-boot 的 internalModules() 是一句**没有 try/catch 的裸 require**：
 *     const addon = createRequire(import.meta.url)("node-addon-require-builtin");
 *     addon.requireBuiltin("internal/modules/esm/loader"); ...
 * 缺了它整个 dsh 起不来（"No usable native binding found for
 * node-addon-require-builtin-android-arm64"）。加载器（node-addon-native-custom-loader）
 * 只有 optional-package 与 local-build 两条来源，没有 JS 回退。
 *
 * 为什么这样替代是等价的：原生绑定唯一的实际用途就是取 Node 内部模块，而这在
 * --expose-internals 下用 require 就能做到 —— dsh 的包装脚本（$PREFIX/bin/dsh，
 * 由 setup.sh 第 6 步生成）本来就带该参数，HMR 也需要它。
 * 本模块不引入任何新能力：它暴露的就是同一个内部模块加载器本身。
 *
 * getNativeBindingInfo() 的返回值必须通过加载器的严格校验：
 *   backend 必须是 'napi' | 'nodeabi'；abi 必须精确等于 buildAbiTag(backend, ...)，
 *   对 nodeabi 即 `node-v${process.versions.modules}`（运行时取值，不能硬编码）。
 */
/**
 * ⚠️ 这四个字段必须通过加载器的严格校验，改任何一个都可能让 dsh 起不来：
 *   · mode / product / backend / abi 都必须是字符串；
 *   · product 必须等于加载器 productForPackage() 从包名推出的值 —— 即 'require-builtin'
 *     （由 'node-addon-require-builtin' 去掉 'node-addon-' 前缀得到）。
 *     这一条是 node-addon-native-custom-loader **0.1.9 才加**的（0.1.6 只查 mode/backend/abi）。
 *     真机 .170 装到 0.1.9 后即因此报：
 *       native binding product mismatch: expected require-builtin, got dsh-android
 *   · backend 必须是 'napi' | 'nodeabi'；abi 必须精确等于 buildAbiTag(backend, …)，
 *     对 nodeabi 即 `node-v${process.versions.modules}`（运行时取值，不能硬编码）。
 */
const info = Object.freeze({
  mode: 'js-shim',
  product: 'require-builtin',
  backend: 'nodeabi',
  abi: `node-v${process.versions.modules}`,
});

module.exports = {
  requireBuiltin(moduleId) {
    return require(moduleId);
  },
  isAllowedInternalId(moduleId) {
    return typeof moduleId === 'string' && moduleId.startsWith('internal/');
  },
  getNativeBindingInfo() {
    return info;
  },
};
