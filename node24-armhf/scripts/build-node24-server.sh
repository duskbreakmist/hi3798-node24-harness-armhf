#!/usr/bin/env bash
# No sudo needed: native x86/i386 build tools inside a Debian 12 proot.
set -euo pipefail
BASE=${BASE:-/home/builder/build_nodejs_arm32}
WORK=$BASE/work
ROOT=$BASE/toolchain
JOBS=${JOBS:-16}
HOST_OPT=${HOST_OPT:-1}
PREFIX=/opt/node-v24.22.1-armhf
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
mkdir -p "$WORK/report" "$ROOT/proc" "$ROOT/dev" "$ROOT/sys" "$ROOT/tmp" "$ROOT/node24-work"
mkdir -p "$BASE/tools"
gcc -std=c11 -O2 -Wall -Wextra "$SCRIPT_DIR/proot-no-statx.c" -o "$BASE/tools/proot-no-statx"
exec 9>"$WORK/build.lock"
flock -n 9 || { echo 'Another build holds the lock'; exit 75; }
cd "$WORK"
echo '4f5379796280cdaeb0c2f358fd04b6a16cc4fb7dfa83b5a8c91a9d963b435231  node-v24.22.1.tar.xz' | sha256sum -c -
test -d node-v24.22.1 || tar -xf node-v24.22.1.tar.xz
for patch_file in zlib-arm32-crc-flags.patch v8-arm32-dependent-template.patch; do
  if patch -R --dry-run -s -d node-v24.22.1 -p1 < "$SCRIPT_DIR/$patch_file"; then
    echo "Already applied: $patch_file"
  else
    patch -d node-v24.22.1 -p1 < "$SCRIPT_DIR/$patch_file"
  fi
done
cat > toolchain-env.sh <<'EOF'
export CC='arm-linux-gnueabihf-gcc -mcpu=cortex-a7 -mfpu=neon-vfpv4 -mfloat-abi=hard'
export CXX='arm-linux-gnueabihf-g++ -mcpu=cortex-a7 -mfpu=neon-vfpv4 -mfloat-abi=hard'
export AR=arm-linux-gnueabihf-ar
export CC_host='gcc-12 -m32 -isystem /usr/include/x86_64-linux-gnu'
export CXX_host='g++-12 -m32 -isystem /usr/include/x86_64-linux-gnu'
EOF
runner=("$BASE/tools/proot-no-statx" proot -0 -r "$ROOT" -b /proc -b /dev -b /sys -b "$WORK:/node24-work" -w /node24-work /usr/bin/env -i PATH=/usr/bin:/bin HOME=/root USER=root LANG=C.UTF-8)
"${runner[@]}" /node24-work/host32-check
"${runner[@]}" /usr/bin/arm-linux-gnueabihf-g++ --version > report/toolchain-version.txt
hostname > report/build-host.txt
date -Is > report/build-started.txt
echo running > report/build-exit-code.txt
echo configure > report/build-phase.txt
(
  exec 9>&-
  while true; do
    phase=$(cat report/build-phase.txt)
    case "$phase" in configure) log=configure.log;; precheck) log=precheck.log;; install) log=install.log;; *) log=build.log;; esac
    { date -Is; echo "phase=$phase"; tail -n 3 "$WORK/$log" 2>/dev/null | tr -d '\000'; free -m | head -2; } > report/build-progress.txt.tmp
    mv report/build-progress.txt.tmp report/build-progress.txt
    sleep 30
  done
) &
monitor_pid=$!
trap 'status=$?; kill "$monitor_pid" 2>/dev/null || true; if test "$(cat report/build-exit-code.txt)" = running; then echo "$status" > report/build-exit-code.txt; fi' EXIT
"${runner[@]}" /bin/bash -c 'source /node24-work/toolchain-env.sh; cd /node24-work/node-v24.22.1; ./configure --cross-compiling --dest-cpu=arm --dest-os=linux --with-arm-float-abi=hard --with-arm-fpu=neon --prefix=/opt/node-v24.22.1-armhf' > configure.log 2>&1
python3 - "$WORK/node-v24.22.1/out/tools/v8_gypfiles" "$HOST_OPT" <<'PY'
import pathlib,re,sys
assert sys.argv[2] in ['1','2','3']
for p in pathlib.Path(sys.argv[1]).glob('*.host.mk'):
    old=p.read_text();new=re.sub(r'(?m)^(\s*)-O3(?=\s|\\|$)',lambda m:m.group(1)+'-O'+sys.argv[2],old)
    if old!=new:p.write_text(new)
PY
echo precheck > report/build-phase.txt
"${runner[@]}" /bin/bash -c 'source /node24-work/toolchain-env.sh; cd /node24-work/node-v24.22.1; make -C out BUILDTYPE=Release -j3 /node24-work/node-v24.22.1/out/Release/obj.host/v8_compiler/deps/v8/src/compiler/turboshaft/int64-lowering-phase.o /node24-work/node-v24.22.1/out/Release/obj.target/v8_compiler/deps/v8/src/compiler/turboshaft/int64-lowering-phase.o /node24-work/node-v24.22.1/out/Release/obj.host/v8_base_without_compiler/deps/v8/src/heap/heap-allocator.o' > precheck.log 2>&1
"${runner[@]}" /bin/bash -c 'source /node24-work/toolchain-env.sh; cd /node24-work/node-v24.22.1; make -C out BUILDTYPE=Release /node24-work/node-v24.22.1/out/Release/obj/gen/node_javascript.cc' > js2c-precheck.log 2>&1
echo build > report/build-phase.txt
set +e
"${runner[@]}" /bin/bash -c "source /node24-work/toolchain-env.sh; cd /node24-work/node-v24.22.1; make -j$JOBS" > build.log 2>&1
status=$?
set -e
echo "$status" > report/build-exit-code.txt
date -Is > report/build-finished.txt
test "$status" = 0 || { tail -50 build.log; exit "$status"; }
echo install > report/build-phase.txt
"${runner[@]}" /bin/bash -c 'source /node24-work/toolchain-env.sh; cd /node24-work/node-v24.22.1; make install DESTDIR=/node24-work/stage' > install.log 2>&1
cp "stage$PREFIX/bin/node" node.unstripped
"${runner[@]}" arm-linux-gnueabihf-strip "/node24-work/stage$PREFIX/bin/node"
mkdir -p "stage$PREFIX/share/licenses/node"
cp node-v24.22.1/LICENSE "stage$PREFIX/share/licenses/node/LICENSE"
tar --owner=0 --group=0 -C stage -cJf node-v24.22.1-linux-armv7l-hi3798.tar.xz opt/node-v24.22.1-armhf
sha256sum node-v24.22.1-linux-armv7l-hi3798.tar.xz > SHA256SUMS
echo ready > report/package-status.txt
