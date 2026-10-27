# HI3798 DeepSeek Harness ARM32 适配记录

日期：2026-10-27。目标固定为 `@deepseek-ai/dsh@0.2.1-rc.2`，使用已部署的 Node 24.22.1 / npm 11.19.1；不是对任意后续版本的兼容承诺。原始 AstrBot 笔记及 Python 环境未修改。

## 目录结构

所有交叉编译在 `ssh build-host` 对应的 `builder@build-host` 中完成：

```text
/home/builder/build_nodejs_arm32/
├── scripts/prepare-harness-builtin-arm32.py
├── scripts/prepare-harness-system-arm32.py
├── tools/proot-no-statx
├── toolchain/                         Debian 12 GCC 12 armhf 工具链
└── work/
    ├── dsh-audit/                     已下载 npm 发布包和原始 builtin 源码
    ├── native-validation/             已通过板测的 pty.node / flock.node
    └── harness-armhf/
        ├── builtin-source/            独立修改副本，原始源码保留
        ├── public-headers/            官方 Node 24.22.1 公开头文件
        ├── node-addon-api/            npm 8.9.0，核验 integrity
        ├── require-builtin-armhf.node
        ├── internal-loader-armhf.node
        ├── node-addon-system-linux-arm/
        │   └── bin/{landlock-run,glibc/system.node}
        ├── installation/              package.json / lock / vendor
        ├── builtin-build-results.json
        └── system-build-results.json
```

板上：

```text
/opt/node-v24.22.1-armhf/               Node/npm，既有部署
/home/boarduser/harness-armhf-validation-20261027/
                                       原始扩展、集成包和实测记录
/home/boarduser/deepseek-harness-armhf/        独立 npm 安装，运行用户 boarduser
├── package.json
├── package-lock.json
├── vendor/node-addon-system-linux-arm/
├── node_modules/node-pty/build/Release/pty.node
└── node_modules/node-addon-require-builtin/
    └── build/nodeabi/node-v137-linux-arm-gnu/require_builtin.node
```

## 编译和安装方法

前置工具链、proot 的 statx 兼容启动器与 Node 构建过程见仓库 `node24-armhf/`。不需要在板上使用 Python 3.11 系统包；板上集成脚本使用已有 `/opt/py3_12/bin/python`。

```sh
# 服务器，脚本从本次材料复制到 scripts 后运行
python3 /home/builder/build_nodejs_arm32/scripts/prepare-harness-builtin-arm32.py
python3 /home/builder/build_nodejs_arm32/scripts/prepare-harness-system-arm32.py
```

公开 Node headers 下载自 `https://nodejs.org/dist/v24.22.1/` 并核对官方 SHASUMS256；node-addon-api 下载自 `https://registry.npmjs.org/` 并核对 SHA512 integrity。服务器没有 sudo，使用 proot 工具链根目录，不修改服务器系统工具链。

ARM32 分支通过公开 V8 API 读取当前 context，保留上游动态符号查找、同一加载映像、地址可读性、getter 与字段句柄一致性、NAPI 类型及内部模块 smoke 校验。新增 Thumb 指令解析严格识别实际 getter 模式，从指令解出字段偏移，不硬编码对象偏移；无法识别时拒绝使用。该路径属于 ABI 固定的 `nodeabi` 后端，不能称为跨任意 Node 版本的 NAPI 后端。

安装项目锁定 Koffi 3.3.4，替代原先不支持 ARM32 的 3.1.1。服务器生成含 693 个条目的依赖锁文件。板上尝试 `npm ci --ignore-scripts --no-audit --no-fund --registry=https://registry.npmjs.org`，安装中断，不能把留下的不完整目录作为成功安装。期间 SSH 握手曾超时；恢复后未发现正在运行的 npm，当前证据不足以断言是 OOM。

随后改为服务器预备 ARM 离线依赖树：

```sh
cd /home/builder/build_nodejs_arm32/work/harness-armhf/installation
npm ci --ignore-scripts --no-audit --no-fund --force --cpu=arm --os=linux --libc=glibc
tar -cf - package.json package-lock.json vendor node_modules | gzip -3 > ../harness-armhf-offline-npm.tar.gz
```

实际新增 614 个包，依赖树约 681MiB，压缩约 118MiB。服务器 npm 10 的非 optional 平台检查忽略目标 cpu 参数，故用 `--force` 允许直接依赖的本地 ARM 包；optional 依赖仍按 arm/linux/glibc 筛选（已核对 npm arborist 的 `checkPlatform(node.package, false, {cpu,os,libc})`）。实际包含 `@img/*linux-arm`、`@koromix/koffi-linux-arm`、`@vscode/ripgrep-linux-arm`。全部禁用安装脚本，没有在 x64 上执行 ARM 程序。这个包只包含发布包和本地 vendor，不含用户凭据或业务数据。

全新目录的板上部署方法如下；已有安装须先备份，不能重复覆盖运行中的应用。三个压缩包先上传到板上验证目录（offline-npm 包留在指定服务器，本仓库发布小体积编译/锁定材料）：

```sh
# root 执行，要求 Node24 已部署、以下安装目录为全新目录
install -d -o boarduser -g boarduser /home/boarduser/deepseek-harness-armhf
install -d -o boarduser -g boarduser /home/boarduser/harness-armhf-validation-20261027
cd /home/boarduser/harness-armhf-validation-20261027
tar -xJf harness-armhf-integration.tar.xz
tar -xJf harness-install-inputs.tar.xz -C /home/boarduser/deepseek-harness-armhf
/opt/py3_12/bin/python deploy-harness-offline.py \
  7d49dbc526fece40418c5f6833325dbc619422bf2c3c44e5f34596395c6ebdc8
runuser -u boarduser -- node test-harness-install.mjs /home/boarduser/deepseek-harness-armhf
```

离线包每次重新生成可能因 tar 元数据而有不同摘要，应使用该次真实核验的摘要；以上 SHA256 对应本次服务器及板上实际包。此安装脚本验证摘要、保留不完整 node_modules 为 `node_modules.incomplete-20261027`，并创建 `/usr/local/bin/dsh-armhf`。已有 staging、备份或启动器时会拒绝盲目重复部署，需先检查现状。

先禁止第三方安装脚本，再运行 `integrate-harness-armhf.py` 放入已校验 SHA256 的 pty 和 builtin 文件。本地 system 平台包是项目的 `file:vendor/node-addon-system-linux-arm` 依赖，包含真实 flock 扩展和真实 Landlock launcher；不修改官方 npm 平台矩阵，不向 npm 发布冒充官方的平台包。

builtin 使用上游支持的 `local-build` 回退目录；未修改 JS 加载器、未关闭二进制产品/ABI 校验或缓存校验。之后重新 `npm ci` 会重建 node_modules，因此需要再次运行集成脚本。

## 已验证与边界

- 两个 builtin ARM32 共享对象交叉编译成功；主机指令解析测试覆盖实际模式、截断与变异拒绝。
- 板上 boarduser 用户通过 CJS/ESM 内部加载器测试，完整版本可读取 bootstrap realm；受限版本拒绝白名单外 bootstrap realm。见 `builtin-test.json`。
- pty/flock 的基础功能、Koffi libc、Sharp 图片缩放、ripgrep 搜索此前已在同一 Node 版本上通过，见 `node24-armhf/validation/board-native-candidates.json`；完整应用仍需整合验证。
- 本次 Landlock ARM32 launcher 编译成功，实际板上 `--probe` 退出 125，明确不支持；不是缺少平台文件导致的假阴性。
- bubblewrap 的实际 profile 退出 1，错误为无法挂载 devpts。内核配置明确 `CONFIG_DEVPTS_MULTIPLE_INSTANCES` 未启用，见 `bwrap-probe.txt`。

当前没有通过的工具沙箱。没有静默改成无沙箱执行，没有设置 SUID/capabilities，也没有伪造可用性检测。后续启用工具的隔离执行需要更换/重编兼容内核并重新验证 profile。仅安装 Node/npm 或编译 Landlock 程序不能补齐内核功能。

本地 SenseVoice 的 Sherpa/ONNX ARM32，以及 Office WASM 内存需求仍需单独验证。本次不下载语音模型，不配置用户 API 密钥，不调用付费模型。

## 安装后的回归与启动方法

离线依赖已部署；`installed-native-test.json` 的 6 项全部通过：npm 发布版 JS builtin 加载器、Koffi override、Sharp PNG、PTY 包装器、flock 包装器和 ripgrep 平台包。builtin 加载器明确报告 `bindingSource=local-build`；flock 包装器的竞争拒绝和释放后再加锁均通过。该测试最大 RSS 59916KiB，不代表完整网页的内存占用。

`dsh-armhf --help` 和 `dsh-armhf web --help` 均退出 0。启动入口默认使用 192MiB old-space 与 4MiB semi-space；这只是堆限制，不是进程 RSS 硬上限。用户数据位于 `data/`，共享 agent 配置位于 `agents/`，均在独立安装目录内；没有复用用户原有的 `~/.dsh` 或 `~/.agents`。

`web-startup.json` 记录完整认证 HTTP 验证通过：200、37512 字节 HTML、74.52 秒（含启动/检查/退出）、峰值 RSS 176956KiB，SIGTERM 后退出 0。`web-startup.log` 中的启动令牌已脱敏。首次探测因没有携带令牌遇到 401，修正认证流程后通过。此结果证明网页后端能启动并提供认证首页；未以真实模型完成对话、执行带沙箱工具、验收浏览器交互、本地语音或 Office 转换。

```sh
# 板上以 boarduser 用户运行；如从 root 登录，先切换到 boarduser
mkdir -p /home/boarduser/deepseek-harness-armhf/workspace
cd /home/boarduser/deepseek-harness-armhf/workspace
dsh-armhf web --host 127.0.0.1 --port 3080 --no-open
```

启动终端会打印含临时登录令牌的 URL，应使用该完整地址。直接无令牌访问 `/` 返回 401 属于实际认证行为。Windows 通过 SSH 转发访问时：

```powershell
ssh -N -L 3080:127.0.0.1:3080 board-host
```

保持上述 SSH 窗口，在 Windows 浏览器打开板上打印的 `http://127.0.0.1:3080/?token=<redacted> GitHub。测试未配置开机自启；测试脚本退出会关闭它启动的网页进程。

## 归档和复现

`harness-armhf-build-records.tar.xz` 包含原始 builtin 源码 tarball、完整修改副本、新增解析头文件、指令测试、编译命令、system 0.1.2 发布源码及许可证。`sources-manifest.json` 保存来源和 SHA256。原始 builtin 取自当时 master 的快照，必须使用归档内快照复现，不能重新下载浮动 master 并假设结果相同。

`harness-armhf-integration.tar.xz` 包含两项 builtin 扩展、pty、system 本地平台包及板上集成/验证脚本。pty/flock 的来源与独立构建命令在已发布 `node24-armhf` 构建材料内；本次核对 system npm 发布源码的 flock.c 与该构建使用源码 SHA256 完全一致。

服务器已有工具链时，重建所需目录如下：先解包 build-records，将原始 builtin tarball 解到 `work/dsh-audit/`，将 `system-published-0.1.2/` 放到 `work/dsh-audit/@deepseek-ai__node-addon-system/package/`；将脚本放到服务器 `scripts/`。builtin 脚本自动下载并核验公开 headers/API。system 脚本还需要已构建的 `work/native-validation/flock.node`。不需要还原任何用户 home 或系统配置。
