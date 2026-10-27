#!/usr/bin/env bash
# Run as root in WSL Ubuntu-24.04. No target binaries run during compilation.
set -euo pipefail
VERSION=${VERSION:-24.22.1}
WORK=${WORK:-/home/boarduser/workplace/node24-armhf}
CHROOT=${CHROOT:-/home/boarduser/workplace/astrbot-faiss-armhf-1.14.3/amd64}
JOBS=${JOBS:-2}
HOST_OPT=${HOST_OPT:-1}
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
REPORT_DIR=${REPORT_DIR:-/workspace/hi3798-node24-harness-armhf/reports/2026-10-26/node24-armhf}
PREFIX=/opt/node-v${VERSION}-armhf
test -x "$CHROOT/usr/bin/arm-linux-gnueabihf-g++"
test -x "$CHROOT/usr/bin/g++-12"
mkdir -p "$WORK" "$CHROOT/node24-work"
exec 9>"$WORK/build.lock"
flock -n 9 || { echo 'Another Node build holds the lock'; exit 75; }
mountpoint -q "$CHROOT/node24-work" || mount --bind "$WORK" "$CHROOT/node24-work"
cd "$WORK"
if test -f build.log; then cp build.log "build-attempt-$(date +%Y%m%d-%H%M%S).log"; fi
if ! test -f "node-v${VERSION}.tar.xz"; then
  curl -fL --retry 3 "https://nodejs.org/dist/v${VERSION}/node-v${VERSION}.tar.xz" -o "node-v${VERSION}.tar.xz"
fi
curl -fsSL --retry 3 "https://nodejs.org/dist/v${VERSION}/SHASUMS256.txt" -o "SHASUMS256-v${VERSION}.txt"
grep " node-v${VERSION}.tar.xz$" "SHASUMS256-v${VERSION}.txt" | sha256sum -c -
test -d "node-v${VERSION}" || tar -xf "node-v${VERSION}.tar.xz"
if ! grep -q 'armv8-a+crypto+crc' "node-v${VERSION}/deps/zlib/zlib.gyp"; then
  patch -d "node-v${VERSION}" -p1 < "$SCRIPT_DIR/zlib-arm32-crc-flags.patch"
fi
if ! grep -q 'return __ template Tuple<Word32, Word32>' "node-v${VERSION}/deps/v8/src/compiler/turboshaft/int64-lowering-reducer.h"; then
  patch -d "node-v${VERSION}" -p1 < "$SCRIPT_DIR/v8-arm32-dependent-template.patch"
fi
cat > "$WORK/toolchain-env.sh" <<'EOF'
export CC='arm-linux-gnueabihf-gcc -mcpu=cortex-a7 -mfpu=neon-vfpv4 -mfloat-abi=hard'
export CXX='arm-linux-gnueabihf-g++ -mcpu=cortex-a7 -mfpu=neon-vfpv4 -mfloat-abi=hard'
export AR=arm-linux-gnueabihf-ar
export CC_host='gcc-12 -m32 -isystem /usr/include/x86_64-linux-gnu'
export CXX_host='g++-12 -m32 -isystem /usr/include/x86_64-linux-gnu'
EOF
date -Is > build-started.txt
mkdir -p "$REPORT_DIR"
echo running > "$REPORT_DIR/build-exit-code.txt"
(
  while true; do
    { date -Is; tail -n 3 "$WORK/build.log" 2>/dev/null | tr -d '\000'; free -m | head -2; } > "$REPORT_DIR/build-progress.txt.tmp"
    mv "$REPORT_DIR/build-progress.txt.tmp" "$REPORT_DIR/build-progress.txt"
    sleep 20
  done
) &
monitor_pid=$!
trap 'status=$?; kill "$monitor_pid" 2>/dev/null || true; if test "$(cat "$REPORT_DIR/build-exit-code.txt")" = running; then echo "$status" > "$REPORT_DIR/build-exit-code.txt"; echo "$status" > "$WORK/build-exit-code.txt"; fi' EXIT
chroot "$CHROOT" bash -c "source /node24-work/toolchain-env.sh; cd /node24-work/node-v${VERSION}; ./configure --cross-compiling --dest-cpu=arm --dest-os=linux --with-arm-float-abi=hard --with-arm-fpu=neon --prefix=${PREFIX}" > configure.log 2>&1
python3 - "$WORK/node-v${VERSION}/out/tools/v8_gypfiles" "$HOST_OPT" <<'PY'
import pathlib,re,sys
root=pathlib.Path(sys.argv[1]);opt=sys.argv[2]
assert opt in ['0','1','2','3']
changed=[]
for p in root.glob('*.host.mk'):
    old=p.read_text();new=re.sub(r'(?m)^(\s*)-O3(?=\s|\\|$)',lambda m:m.group(1)+'-O'+opt,old)
    if new!=old:p.write_text(new);changed.append(p.name)
print('V8 host-tool optimization -O'+opt, 'files:',len(changed),flush=True)
PY
chroot "$CHROOT" bash -c "source /node24-work/toolchain-env.sh; cd /node24-work/node-v${VERSION}; make -C out BUILDTYPE=Release -j3 /node24-work/node-v${VERSION}/out/Release/obj.host/v8_compiler/deps/v8/src/compiler/turboshaft/int64-lowering-phase.o /node24-work/node-v${VERSION}/out/Release/obj.target/v8_compiler/deps/v8/src/compiler/turboshaft/int64-lowering-phase.o /node24-work/node-v${VERSION}/out/Release/obj.host/v8_base_without_compiler/deps/v8/src/heap/heap-allocator.o" > precheck.log 2>&1
set +e
chroot "$CHROOT" bash -c "source /node24-work/toolchain-env.sh; cd /node24-work/node-v${VERSION}; make -j${JOBS}" > build.log 2>&1
status=$?
set -e
echo "$status" > build-exit-code.txt
echo "$status" > "$REPORT_DIR/build-exit-code.txt"
date -Is > build-finished.txt
test "$status" = 0 || { tail -50 build.log; exit "$status"; }
chroot "$CHROOT" bash -c "source /node24-work/toolchain-env.sh; cd /node24-work/node-v${VERSION}; make install DESTDIR=/node24-work/stage" > install.log 2>&1
cp "stage${PREFIX}/bin/node" node.unstripped
chroot "$CHROOT" arm-linux-gnueabihf-strip "/node24-work/stage${PREFIX}/bin/node"
mkdir -p "stage${PREFIX}/share/licenses/node"
cp "node-v${VERSION}/LICENSE" "stage${PREFIX}/share/licenses/node/LICENSE"
tar -C stage -cJf "node-v${VERSION}-linux-armv7l-hi3798.tar.xz" "opt/node-v${VERSION}-armhf"
sha256sum "node-v${VERSION}-linux-armv7l-hi3798.tar.xz" > SHA256SUMS
