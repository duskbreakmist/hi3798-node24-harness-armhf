# DeepSeek Harness 在 HI3798 armhf 上的额外编译评估

检查日期：2026-10-26。安装目标锁定 npm 正式发布通道的 `@deepseek-ai/dsh@0.2.1-rc.2`；官方源码 master 已是 `0.2.1-rc.3`，只用来辅助分析，不能与已发布包混为同一版本。`package-lock.json` 由 `npm install --package-lock-only --ignore-scripts` 生成，含根项目及 683 个依赖条目；没有运行第三方安装脚本。

## 结论与优先顺序

Node 24 运行成功仅是第一步。完整安装 Harness 还存在需要代码适配的原生依赖，不能认为所有缺失模块都可以直接 `npm rebuild`。

| 组件 | 锁定版本 | 检查结果 | 后续处理 |
| --- | --- | --- | --- |
| Node / npm | 24.22.1 / 11.19.1 | ARMv7为实验平台；板子kernel4.4.35低于官方基线 | 已编译部署，12项核心、HTTPS及npm下载发布包均通过 |
| `node-pty` | 1.2.0-beta.15 | npm包无Linux arm预编译产物；安装脚本可fallback到node-gyp | 已交叉编译并通过板上PTY shell/退出测试；服务器重编译结果与实测二进制SHA256相同 |
| `node-addon-require-builtin` | 0.1.9 | 发布平台不含 Linux arm；源码包含按架构实现的 runtime context / instruction probe，未提供 Linux ARM32 实现 | 需要移植、平台包/加载器适配与内部模块测试；仅设置 `--arch=arm` 不足以证明可用 |
| `koffi` | 3.1.1 | 此版无ARM32后端；3.2恢复ARM32，3.3.4发布Linux arm包 | 3.3.4预编译包已在板上加载并调用libc getpid；无需自行编译，仍须验证Harness各调用点的overrides兼容性 |
| `@deepseek-ai/node-addon-system` | 0.1.2 | 官方平台包只有darwin arm64/x64、linux arm64/x64 | flock已交叉编译且通过板上竞争/释放测试；尚需补Linux arm平台包声明和加载路径 |
| Landlock launcher | 随上述包 | Linux 4.4 没有上游 Landlock 接口 | 即使编译 launcher，也不会获得 Landlock 沙箱能力；需要另查 bwrap/namespace 可用性，不能伪造 probe 成功 |
| `sharp` + libvips | 0.35.5 / 1.3.4 | 官方Linux ARM包提供Sharp0.35.5/libvips8.18.7 | 已在板上加载并完成图片缩放/PNG往返；可使用预编译包，无需重编整套libvips |
| `@vscode/ripgrep` | 1.18.0 | lock 中有 `@vscode/ripgrep-linux-arm`，实际随附 rg 是 13.0.0 | 已在板上以 boarduser 用户运行 `rg --version`，退出 0，无需先编译 Rust |
| SQLite 会话查询 | dsh-session-query-sqlite 0.2.1-rc.2 | 发布代码动态 import `node:sqlite`，未依赖 better-sqlite3 | 使用本次 Node 内置 SQLite，无须另编 better-sqlite3 或 Python sqlite |
| Harness 普通 JS / Web 静态资源 | 0.2.1-rc.2 | npm 已提供构建后的 JS / Web 资源 | 安装发布包时通常不需要重建整个 monorepo；esbuild/rollup 等开发工具不能自动算作板上运行依赖 |
| 本地语音识别 `sherpa-onnx-node` | 1.13.8 | `dsh-experimental-speech-to-text-sensevoice` 使用它；Linux 预编译包只有 x64/arm64 | 若启用本地 SenseVoice，需要另评估 Sherpa/ONNX Runtime ARM32 源码构建、模型与内存；不是 Node 本体需要的库 |
| Office / PDF `@deepseek-ai/libreoffice-kit` | 0.1.5 | `dsh-office-to-pdf`、`dsh-skill-office` 使用；Linux 提供 `libreoffice-kit-wasm` 包 | 先测试官方 WASM 运行时与板上内存，不预先编译整套 LibreOffice；其 Koffi 3.1.1 也要纳入 overrides 兼容性检查 |

建议先验证 Node，再处理 node-pty 和 flock 等较直接的扩展；Koffi 优先试新版预编译包和兼容性回归，builtin 仍需单独解决 ARM32 适配。当前没有宣布 Harness 已能完整启动、执行工具或使用沙箱。

Koffi 的新版路线已核对[官方更新记录](https://koffi.dev/changelog)和 npm 元数据；本目录保存 `koffi__3.3.4.json`、`@koromix__koffi-linux-arm__3.3.4.json`。不要用“最新版支持 ARM32”误推原来的 3.1.1 也支持；也不要未经测试就把 overrides 写入生产安装。

板上只读核查发现 `/usr/bin/bwrap` 已存在，内核 `CONFIG_NAMESPACES/UTS_NS/USER_NS/PID_NS/SECCOMP=y`。这使 bwrap 成为可验证的候选路径，但配置项与文件存在并不证明 Harness 的完整沙箱 profile 能成功运行。

随后实测 bubblewrap 0.8.0，以普通用户 `boarduser` 执行下列最小探测失败，退出 1：`bwrap: Can't mount devpts on /newroot/dev/pts: Operation not permitted`。因此目前没有可宣称通过的沙箱后端；还需要检查内核 devpts/user namespace 实现和 Harness 实际 profile，不应通过伪造检测结果解决。

```sh
runuser -u boarduser -- bwrap --ro-bind / / --proc /proc --dev /dev \
  --unshare-user --unshare-pid --die-with-parent /bin/true
```

Windows 的 Python 虚拟环境、板子的 CPython 3.12 / AstrBot 环境不能代替 Node 原生扩展。构建机可以使用 Python 3.11 运行 node-gyp/GYP；这不等于在板上依赖系统 Python 3.11 的运行包。

## 可核对的源码位置

- `node-pty/package.json` 的 install：`node scripts/prebuild.js || node-gyp rebuild`。
- `node-pty/prebuilds/`：Linux 仅 x64、arm64。
- `koffi/package.json` optionalDependencies；`src/koffi/CMakeLists.txt` 中 `CMAKE_SIZEOF_VOID_P EQUAL 4` 分支；`src/koffi/src/abi/`。
- `dsh-session-query-sqlite/lib/index.js`：动态导入 `node:sqlite`。
- Harness `native/system/scripts/build.ts`；`native/system/packages/entry/src/flock.c`；`native/system/packages/entry/src/main.c`。
- builtin 官方源码 `docs/support-matrix.md`、`packages/native/src/runtime_context/`、`packages/native/src/runtime_probe/`。

builtin 中明确的 Linux ARM32 障碍位于 `runtime_context/platform.cc` 与 `runtime_probe/platform.cc`：Linux 只分派 `__aarch64__` / `__x86_64__`，其他架构返回 unsupported。Node ABI 后端可以通过公开 V8 API读取 context，但仍会调用 getter 机器码解码；不能仅切换 backend 就宣称解决 ARM32，需要对返回 ABI/指令解析及内部模块加载做实际验证。

官方来源：[Harness](https://github.com/deepseek-ai/deepseek-harness)、[builtin 扩展](https://github.com/deepseek-ai/dsh-node-addon-require-builtin)、[node-pty](https://github.com/microsoft/node-pty)、[Koffi](https://koffi.dev/contribute)、[Node 构建支持表](https://github.com/nodejs/node/blob/v24.22.1/BUILDING.md)。锁定清单中的 resolved/integrity 记录对应 npm 发布包，后续验证应保持版本一致。

## 工作目录

WSL：`/home/boarduser/workplace/node24-armhf/dsh-audit/` 保存下载的 npm 元数据、tarball 和解包源码；`/home/boarduser/workplace/node24-armhf/deepseek-harness-master/` 保存辅助分析的官方源码。该目录不存业务配置和模型 API 密钥。

Windows：本目录保存依赖锁定清单与评估说明。2026-10-27已补充真实板上验证：上述5项原生组件测试全部通过。尚未通过的Harness整合、builtin和沙箱项目继续明确标为待处理。

## 已完成的可行性验证

`native-build-results.json` 保存两条实际交叉编译命令和退出状态：node-pty 的 `src/unix/pty.cc` → `pty.node`，Harness 官方 master 的 `native/system/packages/entry/src/flock.c` → `flock.node`，均退出 0。后者是源码验证样本，不应误称为已经完成官方 armhf npm 平台包发布。

`prebuilt-candidates.json` 记录官方包下载地址、SHA256、ELF 及最高 glibc 符号版本：Koffi 3.3.4 / Sharp 0.35.5 为 2.34，libvips 1.3.4 为 2.36，ripgrep ARM 包为 2.28。静态匹配不代替实际 Node 加载测试。

板上独立验证目录：`/home/boarduser/node24-validation-20261026`；未修改 AstrBot 环境和 Harness 生产配置。ripgrep 验证输出见 `board-ripgrep.txt`。完整 Harness 启动、工具执行和沙箱仍没有通过结论。

2026-10-27结果：Node24.22.1/npm11.19.1已部署；实际加载Koffi、Sharp，运行PTY、flock竞争和ripgrep搜索，5项全部通过，详细结果见 `../board-native-candidates.json`（发布仓库中位于 `../validation/board-native-candidates.json`）。服务器目录 `/home/builder/build_nodejs_arm32/work/native-validation` 中重编译的两项模块与板上验证结果字节一致。npm pack目标Harness发布包成功；完整Harness尚未安装。
