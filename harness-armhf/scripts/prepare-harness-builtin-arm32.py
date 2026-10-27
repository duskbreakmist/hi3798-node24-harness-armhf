#!/usr/bin/env python3
"""Run on build-host; preserve the downloaded source and build a patched copy."""
from pathlib import Path
import base64, difflib, hashlib, io, json, re, shutil, subprocess, tarfile, urllib.request

BASE=Path('/home/builder/build_nodejs_arm32')
WORK=BASE/'work'
OUT=WORK/'harness-armhf'
OUT.mkdir(exist_ok=True)
original=WORK/'dsh-audit/dsh-node-addon-require-builtin-master'
source=OUT/'builtin-source'
if not source.exists(): shutil.copytree(original,source)
headers=OUT/'public-headers'
headers.mkdir(exist_ok=True)
url='https://nodejs.org/dist/v24.22.1/node-v24.22.1-headers.tar.gz'
archive=headers/'node-v24.22.1-headers.tar.gz'
if not archive.exists(): archive.write_bytes(urllib.request.urlopen(url,timeout=90).read())
checks=urllib.request.urlopen('https://nodejs.org/dist/v24.22.1/SHASUMS256.txt',timeout=60).read().decode()
expected=next(l.split()[0] for l in checks.splitlines() if l.endswith('  '+archive.name))
assert hashlib.sha256(archive.read_bytes()).hexdigest()==expected
if not (headers/'node-v24.22.1').exists():
    with tarfile.open(archive) as t:t.extractall(headers)
api=OUT/'node-addon-api'
if not api.exists():
    meta=json.load(urllib.request.urlopen('https://registry.npmjs.org/node-addon-api/8.9.0',timeout=60))
    raw=urllib.request.urlopen(meta['dist']['tarball'],timeout=60).read()
    assert base64.b64encode(hashlib.sha512(raw).digest()).decode()==meta['dist']['integrity'].split('-',1)[1]
    api.mkdir()
    (api/'package.tgz').write_bytes(raw)
    with tarfile.open(fileobj=io.BytesIO(raw),mode='r:gz') as t:t.extractall(api)

decoder=r'''#pragma once
#include <cstdint>
#include <cstddef>
namespace esplus::node::require_builtin {
inline bool DecodePinnedThumbGetter(const uint16_t* c, size_t n, size_t* out) {
  if (n < 2) return false;
  size_t i=0, offset=0;
  const bool framed=c[0]==0xb480 && c[1]==0xaf00;
  if (framed) i=2;
  if (i+2<=n && c[i]==0xf8d0 && (c[i+1]&0xf000)==0) {
    offset=c[i+1]&0x0fff; i+=2;
  } else if (i<n && (c[i]&0xf83f)==0x6800) {
    offset=((c[i]>>6)&31)*4; i++;
  } else return false;
  if (offset==0 || (offset%4)!=0) return false;
  if (framed) {
    if (i+4>n || c[i]!=0x46bd || c[i+1]!=0xf85d ||
        c[i+2]!=0x7b04 || c[i+3]!=0x4770) return false;
  } else if (i>=n || c[i]!=0x4770) return false;
  *out=offset; return true;
}
}
'''
p=source/'packages/native/src/runtime_probe/thumb32_pinned.h';p.write_text(decoder)
p=source/'packages/native/src/runtime_probe/platform.cc'
old=(original/'packages/native/src/runtime_probe/platform.cc').read_text()
if '#include "thumb32_pinned.h"' not in old:
    new=old.replace('#include "parser.h"','#include "parser.h"\n#include "platform.h"\n#include "thumb32_pinned.h"\n#include <cstring>')
    needle='#elif defined(__linux__)\n'
    arm=r'''#elif defined(__linux__) && defined(__arm__)
  const uintptr_t address=reinterpret_cast<uintptr_t>(getter);
  const void* code=reinterpret_cast<const void*>(address & ~uintptr_t{1});
  if ((address & 1)==0 || !IsPlatformReadableRange(code,16)) {
    return Result<GetterPattern>::Failure(Status::Failure(
        ProbeStatus::kUnsupportedNoGetter,"ARM32 getter is not readable Thumb code"));
  }
  uint16_t instructions[8];
  std::memcpy(instructions,code,sizeof(instructions));
  size_t offset=0;
  if (!DecodePinnedThumbGetter(instructions,8,&offset)) {
    return Result<GetterPattern>::Failure(Status::Failure(
        ProbeStatus::kUnsupportedNoGetter,"unsupported ARM32 Thumb field getter"));
  }
  GetterPattern result;
  result.offset=offset;
  result.pattern="linux-arm-thumb32-validated-direct-field";
  result.call_mode=GetterCallMode::kDirectReturn;
  return Result<GetterPattern>::Ok(result);
'''
    assert new.count(needle)==1
    new=new.replace(needle,arm+needle)
    p.write_text(new)
    (OUT/'builtin-arm32.patch').write_text(''.join(difflib.unified_diff(old.splitlines(True),new.splitlines(True),fromfile='a/packages/native/src/runtime_probe/platform.cc',tofile='b/packages/native/src/runtime_probe/platform.cc')))

unit=OUT/'test-thumb-getter.cc'
unit.write_text(r'''#include "thumb32_pinned.h"
#include <cassert>
using namespace esplus::node::require_builtin;
int main() {
 size_t offset=0;
 uint16_t framed[]={0xb480,0xaf00,0xf8d0,0x0100,0x46bd,0xf85d,0x7b04,0x4770};
 assert(DecodePinnedThumbGetter(framed,8,&offset) && offset==256);
 for(int i=0;i<8;i++) {auto old=framed[i];framed[i]^=0x8000;
  assert(!DecodePinnedThumbGetter(framed,8,&offset));framed[i]=old;}
 assert(!DecodePinnedThumbGetter(framed,7,&offset));
 uint16_t leaf[]={0xf8d0,0x0100,0x4770};
 assert(DecodePinnedThumbGetter(leaf,3,&offset) && offset==256);
 uint16_t small[]={0x6840,0x4770};
 assert(DecodePinnedThumbGetter(small,2,&offset) && offset==4);
}
''')
subprocess.run(['g++','-std=c++17','-I',str(p.parent),str(unit),'-o',str(OUT/'test-thumb-getter')],check=True)
subprocess.run([str(OUT/'test-thumb-getter')],check=True)

build=(source/'scripts/build.ts').read_text().split('const commonSources = [',1)[1].split('];',1)[0]
files=[]
for match in re.finditer(r"path\.join\(packageRoot,\s*'src',([^)]*)\)",build):
    files.append(source/'packages/native/src'/Path(*re.findall(r"'([^']+)'",match.group(1))))
files.append(source/'packages/native/src/runtime_compat_nodeabi.cc')
guest=lambda x:'/node24-work/'+str(x.relative_to(WORK))
runner=[str(BASE/'tools/proot-no-statx'),'proot','-0','-r',str(BASE/'toolchain'),'-b','/proc','-b','/dev','-b','/sys','-b',str(WORK)+':/node24-work','-w','/node24-work']
records=[]
for name,product in [('require-builtin',1),('internal-loader',2)]:
    target=OUT/(name+'-armhf.node')
    cmd=['arm-linux-gnueabihf-g++','-std=c++20','-O2','-fPIC','-shared','-pthread','-fno-exceptions','-fvisibility=hidden','-DNAPI_VERSION=9','-DNARB_BACKEND=2','-DNARB_PRODUCT='+str(product),'-DNODE_ADDON_API_DISABLE_CPP_EXCEPTIONS','-DNODE_GYP_MODULE_NAME=require_builtin','-DHAVE_SQLITE=0','-DHAVE_AMARO=0','-I'+guest(headers/'node-v24.22.1/include/node'),'-I'+guest(api/'package')]+[guest(f) for f in files]+['-ldl','-o',guest(target)]
    result=subprocess.run(runner+cmd,stdout=subprocess.PIPE,stderr=subprocess.STDOUT)
    records.append({'name':name,'command':cmd,'exit':result.returncode,'output':result.stdout.decode(errors='replace')})
    (OUT/'builtin-build-results.json').write_text(json.dumps(records,indent=2))
    assert result.returncode==0,records[-1]['output']
    print(name,hashlib.sha256(target.read_bytes()).hexdigest(),flush=True)
print('decoder tests and builds passed',flush=True)
