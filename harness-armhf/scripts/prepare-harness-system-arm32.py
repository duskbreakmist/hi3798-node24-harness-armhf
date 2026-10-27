#!/usr/bin/env python3
"""Run on build-host; build the published 0.1.2 system launcher for honest probes."""
from pathlib import Path
import hashlib, json, shutil, subprocess

base=Path('/home/builder/build_nodejs_arm32')
work=base/'work'
out=work/'harness-armhf'
package=out/'node-addon-system-linux-arm'
binary=package/'bin'
(binary/'glibc').mkdir(parents=True,exist_ok=True)
published=work/'dsh-audit/@deepseek-ai__node-addon-system/package'
source=published/'src/main.c'
runner=[str(base/'tools/proot-no-statx'),'proot','-0','-r',str(base/'toolchain'),'-b','/proc','-b','/dev','-b','/sys','-b',str(work)+':/node24-work','-w','/node24-work']
guest=lambda p:'/node24-work/'+str(p.relative_to(work))
target=binary/'landlock-run'
cmd=['arm-linux-gnueabihf-gcc','-std=c11','-O2','-mcpu=cortex-a7','-mfpu=neon-vfpv4','-mfloat-abi=hard','-fstack-protector-strong',guest(source),'-o',guest(target)]
result=subprocess.run(runner+cmd,stdout=subprocess.PIPE,stderr=subprocess.STDOUT)
record={'command':cmd,'exit':result.returncode,'output':result.stdout.decode(errors='replace'),'sourceSha256':hashlib.sha256(source.read_bytes()).hexdigest()}
(out/'system-build-results.json').write_text(json.dumps(record,indent=2))
assert result.returncode==0,record['output']
shutil.copy2(work/'native-validation/flock.node',binary/'glibc/system.node')
(package/'package.json').write_text(json.dumps({'name':'@deepseek-ai/node-addon-system-linux-arm','version':'0.1.2-hi3798.1','private':True,'os':['linux'],'cpu':['arm'],'license':'BSD-3-Clause','description':'Local ARM32 build; Landlock availability is decided by the real kernel probe.'},indent=2))
for name in ['LICENSE','README.md']:
    if (published/name).exists():shutil.copy2(published/name,package/name)
print(json.dumps({'package':str(package),'files':{str(p.relative_to(package)):hashlib.sha256(p.read_bytes()).hexdigest() for p in package.rglob('*') if p.is_file()}},indent=2))
