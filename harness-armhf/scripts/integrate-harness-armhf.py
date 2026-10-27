#!/usr/bin/env python3
"""Apply tested native binaries to the isolated, version-pinned npm install."""
from pathlib import Path
import hashlib, json, shutil, subprocess, sys

bundle=Path(sys.argv[1]).resolve()
install=Path(sys.argv[2]).resolve()
assert install==Path('/home/boarduser/deepseek-harness-armhf'), 'unexpected installation directory'
root=json.loads((install/'package.json').read_text())
assert root['dependencies']['@deepseek-ai/dsh']=='0.2.1-rc.2'
assert root['overrides']['koffi']=='3.3.4'
runtime=json.loads(subprocess.check_output(['/opt/node-v24.22.1-armhf/bin/node','-p','JSON.stringify({version:process.version,arch:process.arch,abi:process.versions.modules})']))
assert runtime=={'version':'v24.22.1','arch':'arm','abi':'137'},runtime
modules=install/'node_modules'
assert json.loads((modules/'node-addon-require-builtin/package.json').read_text())['version']=='0.1.9'
assert json.loads((modules/'node-pty/package.json').read_text())['version']=='1.2.0-beta.15'
expected={
 'require-builtin-armhf.node':'a5f98ac02a8001596a3c74916897b3572af8c89ee723157b92dde3681cc64165',
 'internal-loader-armhf.node':'04ffc87e7b871129c33a619d065f31026664ce677197257df03cdf73d1d3250b',
 'pty.node':'bdb61c08dbb3a06007f28d47427c58d33db06a340cf053e8b0c2178230c1d3dc',
}
for name,digest in expected.items():
 assert hashlib.sha256((bundle/name).read_bytes()).hexdigest()==digest,name
copies={
 'require-builtin-armhf.node':modules/'node-addon-require-builtin/build/nodeabi/node-v137-linux-arm-gnu/require_builtin.node',
 'pty.node':modules/'node-pty/build/Release/pty.node',
}
for name,target in copies.items():
 target.parent.mkdir(parents=True,exist_ok=True)
 shutil.copy2(bundle/name,target)
platform=modules/'@deepseek-ai/node-addon-system-linux-arm'
assert (platform/'bin/glibc/system.node').is_file(),'local platform dependency missing'
result={'runtime':runtime,'copies':{str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in copies.values()},'platform':str(platform.resolve()),'sandboxPolicy':'unchanged; actual kernel probe decides availability'}
(install/'armhf-integration.json').write_text(json.dumps(result,indent=2))
print(json.dumps(result,indent=2))
