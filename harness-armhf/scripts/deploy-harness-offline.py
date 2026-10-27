#!/usr/bin/env python3
"""Run as root on the board with its custom Python 3.12 runtime."""
from pathlib import Path
import hashlib, json, os, pwd, shutil, subprocess, sys

assert os.geteuid()==0
root=Path('/home/boarduser/deepseek-harness-armhf')
archive=Path('/home/boarduser/harness-armhf-validation-20261027/harness-armhf-offline-npm.tar.gz')
assert hashlib.file_digest(archive.open('rb'),'sha256').hexdigest()==sys.argv[1]
stage=root/'offline-staging-20261027'
assert not stage.exists(), 'staging exists; inspect before retry'
assert not (root/'node_modules.incomplete-20261027').exists(), 'backup exists; inspect before retry'
stage.mkdir()
subprocess.run(['nice','-n','10','tar','--no-same-owner','-xzf',str(archive),'-C',str(stage)],check=True)
for name in ['package.json','package-lock.json']:
 assert (root/name).read_bytes()==(stage/name).read_bytes(), 'npm input drift: '+name
if (root/'node_modules').exists():
 (root/'node_modules').rename(root/'node_modules.incomplete-20261027')
(stage/'node_modules').rename(root/'node_modules')
subprocess.run(['/opt/py3_12/bin/python',str(archive.parent/'integrate-harness-armhf.py'),str(archive.parent),str(root)],check=True)
account=pwd.getpwnam('boarduser')
for directory,dirs,files in os.walk(root,followlinks=False):
 for name in dirs+files:os.chown(Path(directory)/name,account.pw_uid,account.pw_gid,follow_symlinks=False)
os.chown(root,account.pw_uid,account.pw_gid)
launcher=Path('/usr/local/bin/dsh-armhf')
assert not launcher.exists(), 'launcher exists; inspect before replacement'
launcher.write_text('''#!/bin/sh
set -eu
root=/home/boarduser/deepseek-harness-armhf
export DSH_HOME="${DSH_HOME:-$root/data}"
export DSH_AGENTS_HOME="${DSH_AGENTS_HOME:-$root/agents}"
export NODE_OPTIONS="${NODE_OPTIONS:---max-old-space-size=192 --max-semi-space-size=4}"
export PATH="/opt/node-v24.22.1-armhf/bin:$PATH"
exec /opt/node-v24.22.1-armhf/bin/node "$root/node_modules/@deepseek-ai/dsh/lib/bin.js" "$@"
''')
launcher.chmod(0o755)
print(json.dumps({'installation':str(root),'archiveSha256':sys.argv[1],'launcher':str(launcher),'oldPartialPreserved':str(root/'node_modules.incomplete-20261027')},indent=2))
