# HI3798 Node 24 and DeepSeek Harness armhf

Independent build artifacts, source patches and board validation for Debian 12 armhf on HI3798 Cortex-A7.

- [Node 24.22.1 build, installation and tests](node24-armhf/README.md)
- [Harness 0.2.1-rc.2 adaptation and installation](harness-armhf/README.md)
- [Releases](../../releases)

Public build paths such as `/home/builder/build_nodejs_arm32` are generic examples. Original local build records remain private. Target installation paths under `/opt` and `/home/boarduser` are retained as documented deployment defaults. Native executable and addon bytes are unchanged; documentation/source archives have been repacked, with fresh SHA256SUMS.

Node core and native dependency tests passed on the board. Harness authenticated homepage HTTP 200 passed. The old kernel has no usable Landlock or bubblewrap sandbox; real model conversations and sandboxed tool execution are not validated. See component documentation for limits and upstream licenses. AstrBot is maintained separately.

All account names, hostnames, SSH aliases and machine paths in this public copy are example values. Validation numbers and native binaries are unchanged.
