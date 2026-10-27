# Node 24 在 HI3798 / Debian 12 armhf 上的交叉编译记录

编译日期：2026-10-26；部署验证：2026-10-27。**Node v24.22.1 已在用户指定服务器目录完成交叉编译，并部署到 HI3798 当前 SSD 根系统。npm/npx 为 11.19.1。核心 12 项、原生组件 5 项测试全部通过；HTTPS 和 npm 下载 Harness 发布包也成功。**

板上入口为 `/opt/node-v24.22.1-armhf`，占用约 170 MiB；`/usr/local/bin/node`、`npm`、`npx` 已链接到该独立目录。AstrBot 验证前后均 active、PID 2935、NRestarts=0。没有安装完整 Harness，剩余 ARM32 平台适配见依赖评估。

运行时包 SHA256：`f8b07a6a71645a91edd492a387d10856d0138b5bbb9cd65dd334f6347ee6ff46`；板上 node 二进制 SHA256：`89af274cbc4b154e593ef5a714a7004e30b35e7b9e56202c54e97597d4e63997`。

最终服务器成功轮次复用了前期依赖缓存：20:56:03 开始、21:48:48 编译结束（52分45秒），21:58 完成安装和打包。前期错误定位、迁移和传输时间另计，不能把此数值当作无缓存的完整构建基准。

## 最终服务器目录结构

```text
/home/builder/build_nodejs_arm32/
├── scripts/                     构建脚本、两份源码补丁、statx兼容启动器源码
├── tools/proot-no-statx          仅供主机构建使用的兼容启动器
├── toolchain/                   Debian12 amd64/i386/armhf交叉工具快照
└── work/
    ├── node-v24.22.1.tar.xz      官方源码，已校验SHA256
    ├── node-v24.22.1/            解包源码及out/构建树
    ├── stage/opt/node-v24.22.1-armhf/
    ├── report/                  构建退出码、时间、进度
    ├── dsh-audit/               附加依赖源码及npm元数据
    ├── native-validation/       node-pty与flock的服务器编译结果
    ├── node-v24.22.1-linux-armv7l-hi3798.tar.xz
    ├── node-v24.22.1-armhf-native-addons.tar.xz
    ├── build.log / configure.log / install.log / precheck.log
    └── node24-extra-source-and-validation.tar.gz
```

复现服务器构建：`ssh build-host`，确认 hostname/whoami/pwd 后，在上述目录执行 `JOBS=16 HOST_OPT=1 bash scripts/build-node24-server.sh`。脚本使用快照内 GCC12；服务器自身 gcc 只用于编译小型 statx 兼容启动器。原始工具快照及缓存归档也保存在 `work/`。

## 手动安装已发布包

以 root 解压到当前根系统，命令链接应在没有其他版本冲突时创建：

```sh
sha256sum --ignore-missing -c SHA256SUMS
tar -xJf node-v24.22.1-linux-armv7l-hi3798.tar.xz -C /
ln -s /opt/node-v24.22.1-armhf/bin/node /usr/local/bin/node
ln -s /opt/node-v24.22.1-armhf/bin/npm /usr/local/bin/npm
ln -s /opt/node-v24.22.1-armhf/bin/npx /usr/local/bin/npx
node --version
npm --version
```

已有其他版本时可以仅把 `/opt/node-v24.22.1-armhf/bin` 放在当前 shell 的 PATH 前面。只复制 `/opt` 不会同时复制 `/usr/local/bin` 的命令链接。实际部署脚本还会校验包和二进制、检查现有目录，先运行核心测试再创建链接。

## 环境与路径

| 位置 | 路径 / 配置 |
| --- | --- |
| Windows 项目 | `C:\workspace\hi3798-node24-harness-armhf` |
| WSL | Ubuntu-24.04，主机 x86_64；通过 `wsl -d Ubuntu-24.04 -u root` 运行 |
| 准备期 WSL 工作目录 | `/home/boarduser/workplace/node24-armhf` |
| 准备期 Debian 12 amd64 工具环境 | `/home/boarduser/workplace/astrbot-faiss-armhf-1.14.3/amd64` |
| 最终服务器工具环境 | `/home/builder/build_nodejs_arm32/toolchain` |
| 容器内源码映射 | `/node24-work` → 对应环境的 Node 工作目录 |
| 最终 Node 源码 | `/home/builder/build_nodejs_arm32/work/node-v24.22.1` |
| 目标工具链 | Debian GCC 12.2.0，`arm-linux-gnueabihf-gcc/g++` |
| 主机构建工具 | Debian GCC/G++ 12.2.0，`-m32`，在 x86 主机执行 V8/ICU 生成器；V8 主机工具使用 `-O1` |
| 目标 CPU / ABI | Cortex-A7 / NEON-VFPv4 / hard-float，ELF ARM EABI5 |
| 最终安装暂存 | `/home/builder/build_nodejs_arm32/work/stage/opt/node-v24.22.1-armhf` |
| 板上安装 | `/opt/node-v24.22.1-armhf`，独立版本目录 |
| 板上系统 | HI3798MV100，Debian 12 armhf，glibc 2.36，kernel 4.4.35-s40 |
| 板上 SSH | `ssh board-host`；连接后确认 hostname/whoami/pwd |

本次不使用海思 softfp SDK 库，也不从系统 Python 3.11 导入运行包。构建环境的 Python 3.11.2 用于 GYP 等构建脚本；产物运行不依赖它。AstrBot 的 `/opt/py3_12` 和 CPython 3.12 环境保持独立。

## 源码及依赖

官方源码：<https://nodejs.org/dist/v24.22.1/node-v24.22.1.tar.xz>。
使用同目录 `SHASUMS256.txt` 核验 tarball，实际核验成功。不要把“下载成功”当作编译或板上测试成功。

已复用 Debian 12 原生 amd64 chroot，目标交叉 GCC12 在此环境中原本已安装。为 V8 的 32 位主机生成器补充 native G++12、i386 libc/libstdc++ 开发库和 make。

Debian 的 gcc-multilib 元包与交叉 gcc 包有冲突；最初 apt 自动安装推荐项时触发替换，之后已重新安装交叉工具链并保留实际的 32 位库。复现时应先 `apt-get -s`，使用 `--no-install-recommends`，确认不会移除交叉 GCC，禁止执行 autoremove。建议使用独立的 Debian 12 amd64 build chroot；这里只复用了已存在的 FAISS 工具环境，没有修改 FAISS 的源码/产物和 ARM 目标 rootfs。

典型依赖清单（必须先模拟求解）：

```sh
apt-get -s --no-install-recommends install \
  python3 g++-12 libc6-dev-i386 lib32stdc++-12-dev \
  gcc-arm-linux-gnueabihf g++-arm-linux-gnueabihf make xz-utils
```

apt 源使用 `https://mirrors.aliyun.com/debian bookworm main`；Node 源码仍从 nodejs.org 下载，校验值来自官方。

## 编译入口

项目 `scripts/node24/build-node24-armhf.sh` 保存完整构建、暂存、strip 和打包命令；同目录保存最小 zlib 补丁与板上 smoke test。脚本通过文件锁避免多个 make 同时操作一套 out 目录。

```powershell
wsl -d Ubuntu-24.04 -u root -- env JOBS=8 HOST_OPT=1 bash /workspace/hi3798-node24-harness-armhf/scripts/node24/build-node24-armhf.sh
```

工具链关键参数：

```sh
export CC='arm-linux-gnueabihf-gcc -mcpu=cortex-a7 -mfpu=neon-vfpv4 -mfloat-abi=hard'
export CXX='arm-linux-gnueabihf-g++ -mcpu=cortex-a7 -mfpu=neon-vfpv4 -mfloat-abi=hard'
export AR=arm-linux-gnueabihf-ar
export CC_host='gcc-12 -m32 -isystem /usr/include/x86_64-linux-gnu'
export CXX_host='g++-12 -m32 -isystem /usr/include/x86_64-linux-gnu'
./configure --cross-compiling --dest-cpu=arm --dest-os=linux \
  --with-arm-float-abi=hard --with-arm-fpu=neon \
  --prefix=/opt/node-v24.22.1-armhf
make -j8
make install DESTDIR=/node24-work/stage
```

Node 使用源码随附的 V8、ICU、OpenSSL、SQLite、zlib 等库；不是要求板上另装这些开发包。没有为了减少编译量而禁用 ICU、SQLite、Wasm、npm 等功能。

脚本在 configure 后只把 `out/tools/v8_gypfiles/*.host.mk` 中的 `-O3` 改成 `-O1`，降低只在构建机执行的 V8 生成器优化等级。ARM `*.target.mk` 保持 `-O3`。上面的 configure/make 片段是关键命令摘要，完整复现须运行脚本，不能遗漏此步骤和补丁。

## 遇到的问题

1. zlib NEON intrinsic 报 target specific option mismatch：仅指定 Node 的 `--with-arm-fpu` 没覆盖所有依赖，改为在目标 CC/CXX 中显式传 CPU/FPU/float ABI。
2. 32 位主机 ICU 工具缺 `asm/errno.h`：给 CC_host/CXX_host 加 Debian x86 多架构内核头文件路径。
3. zlib ARM CRC 编译使用 `-march=armv8-a+aes+crc`，ARM32 GCC12 不认可 `+aes`。仅对 `target_arch==arm` 改成 `+crypto+crc`，其他架构保留原参数。该独立 CRC 编译单元仍由 zlib 运行时能力检测选择，不能让 Cortex-A7 无条件执行 ARMv8 指令；板上 gzip 往返测试也覆盖这一点。
4. 长工具会话期间 WSL 出现非正常中断，日志未留下完整退出状态，后续 uptime 显示环境重新启动；没有证据将其确定归因于 OOM。改用隐藏、持久的 Windows `wsl.exe` 进程和独立日志推进构建。尝试过 2/4 路，内存实测充足后调整至 8 路，并增加构建锁。中断/错误日志与最终成功日志应分别保留。
5. V8 的主机/目标双份构建量较大，后续降低了主机工具优化等级。没有降低 ARM Node 的 Release 优化，也没有对目标功能做裁剪；不要把这项调整写成对目标 Node 的运行性能优化。
6. V8 `int64-lowering-reducer.h` 的 `LowerClz` / `LowerCtz` 两处调用缺依赖模板的 `template` 标记，GCC12 报 invalid use of struct Tuple。补丁只补这两个标记；[Node issue 58458](https://github.com/nodejs/node/issues/58458) 也记录同样的错误。该 issue 是 ARMv6 构建记录，但本次 ARMv7/32位主机生成器实际复现了相同源码错误，不能据 issue 的芯片范围推断本板结果。
7. 曾尝试主机 V8 工具 `-O0`，但触发 GCC12 对递归路径 `always_inline` 的限制；因此改为 `-O1`，不绕过 V8 的内联约束。随后单独预检 int64-lowering 的 host/target 两个对象和 host heap-allocator，均成功。完整编译之前先验证这三个对象，减少晚期失败的等待。
8. 服务器旧版 proot 对 i386 statx 路径转换不完整，导致 js2c 在目录存在时仍报 `[stat] lib: no such file or directory`。用 `proot-no-statx.c` 只给构建进程安装过滤器：x86_64/i386 的 statx 返回 ENOSYS，libc/libuv 走既有 stat/fstatat 回退。相同 js2c 命令及完整生成步骤随后通过；最终构建成功。过滤器没有编译进 ARM Node，也没有修改服务器全局设置。

## build-host 加速环境

用户明确指定在服务器 `builder@build-host:~/build_nodejs_arm32` 编译。通过 `ssh build-host` 连接，主机为32核 Xeon Platinum 8375C，检查时 load 约 1、可用内存约 30 GB。构建目录统一为 `/home/builder/build_nodejs_arm32`，其中 `toolchain/` 是同一 Debian12 用户态工具快照、`work/` 保存 Node 源码/缓存/输出，`scripts/` 保存脚本及补丁。此前临时准备目录已整体移动到用户指定位置。以无 sudo 的 proot 运行，不修改服务器系统编译器。

`build-node24-server.sh` 使用 native x86/i386 GCC 工具；proot 提供路径映射，实际目标由 arm-linux-gnueabihf GCC 生成。实际采用 16 路、主机 V8 O1、目标 O3；原生32位生成器执行和最终构建均已通过。

Node 官方源码由服务器直接下载并再次核对 SHA256。工具快照通过 Windows 原生 SCP 传输：本地上行约 400 KB/s，首次 stdin 流传输在 600 秒超时，因此不能将其误记为源码或编译错误。工具快照归档只在构建目录保留，不作为 GitHub 运行时安装包发布。

## 验证及边界

板上核心 12 项全部通过：ARM运行时、V8/JIT、crypto、gzip、fs、子进程、worker、内置 SQLite、中文/日文 ICU、Wasm、强制优化编译器的 Wasm i64 clz/ctz、loopback HTTP/fetch。后者使用 `--no-liftoff`，直接覆盖本次 int64 lowering 修复相关路径。

原生组件 5 项全部通过：Koffi 3.3.4 调用 libc getpid、Sharp/libvips 实际图片缩放、node-pty shell、flock竞争与释放、ripgrep实际文件搜索。服务器重新编译的 node-pty/flock 与板上测试的二进制 SHA256 相同。原生模块归档附源码、命令和 MIT 许可证，但没有完成 Harness Linux ARM 平台包封装。

外网 HTTPS 访问 npm registry 返回200；板上 boarduser 用户执行 `npm pack @deepseek-ai/dsh@0.2.1-rc.2 --ignore-scripts` 成功，未执行包脚本或安装整套 Harness。smoke主进程 maxRSS约67.7MiB，此值不能代表完整 Harness 的内存用量。详细结果保存在验证 JSON；没有运行 Node 官方完整测试套件。

ELF 为32位ARM EABI5、hard-float，加载器 `/lib/ld-linux-armhf.so.3`；动态依赖仅 libstdc++、libm、libgcc_s、libc。合并后的 CPU attribute 显示 v8，程序包含按CPU特性分派的ARMv8加速编译单元（例如zlib CRC）；本包已在实际 Cortex-A7 上运行上述测试，不能仅凭此 attribute 判断全程序最低CPU，也不能据本板结果宣称兼容所有ARMv7机器。

Node 24 将 ARMv7 列为 Experimental；官方支持表内核基线为 4.18，文档说明旧内核可能工作。因此必须明确“本板实测通过的项目”与“官方平台支持”是两种结论，不能由几项 smoke test 宣称所有 Node 程序兼容。官方依据：[BUILDING.md](https://github.com/nodejs/node/blob/v24.22.1/BUILDING.md)。

Harness 额外依赖评估见 [dsh-dependencies/README.md](dsh-dependencies/README.md)。Node 安装成功不等于 Harness 的原生扩展和沙箱全部可用。
