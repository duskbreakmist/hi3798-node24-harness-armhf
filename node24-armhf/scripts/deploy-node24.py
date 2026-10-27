#!/usr/bin/env python3
"""Run in WSL after build-node24-armhf.sh succeeds. Fixed independent prefix."""
import hashlib
import json
import pathlib
import shlex
import subprocess
import tarfile

PROJECT = pathlib.Path('/workspace/hi3798-node24-harness-armhf')
REPORT = PROJECT / 'reports/2026-10-26/node24-armhf'
PREFIX = '/opt/node-v24.22.1-armhf'
NODE = PREFIX + '/bin/node'
SSH = ['/mnt/c/Windows/System32/OpenSSH/ssh.exe', '-o', 'BatchMode=yes',
       '-o', 'UpdateHostKeys=no', '-o', 'User=root', 'board-host']


def remote(command, data=None, check=True, timeout=240):
    p = subprocess.run(SSH + [command], input=data, stdout=subprocess.PIPE,
                       stderr=subprocess.PIPE, timeout=timeout)
    if check and p.returncode:
        raise RuntimeError(f'{command}\nexit={p.returncode}\n{p.stderr.decode(errors="replace")}')
    return p


def ray_node(args, **kwargs):
    return remote(shlex.join(['runuser', '-u', 'boarduser', '--', NODE] + args), **kwargs)


def save_result(name, p):
    (REPORT / (name + '.stdout.txt')).write_bytes(p.stdout)
    (REPORT / (name + '.stderr.txt')).write_bytes(p.stderr)
    try:
        d = json.loads(p.stdout)
    except (ValueError, UnicodeDecodeError):
        d = {'allPassed': False, 'exit': p.returncode,
             'error': p.stderr.decode(errors='replace')}
    (REPORT / (name + '.json')).write_text(json.dumps(d, indent=2), encoding='utf-8')
    return d


def main():
    assert (REPORT / 'server-build-exit-code.txt').read_text().strip() == '0', 'server build failed'
    package = REPORT / 'node-v24.22.1-linux-armv7l-hi3798.tar.xz'
    sums = (REPORT / 'SHA256SUMS').read_text().splitlines()
    package_hash = hashlib.sha256(package.read_bytes()).hexdigest()
    assert any(line.split() == [package_hash, package.name] for line in sums), 'package checksum mismatch'
    with tarfile.open(package) as t:
        for m in t:
            assert m.name == PREFIX[1:] or m.name.startswith(PREFIX[1:] + '/'), m.name
            assert '..' not in pathlib.PurePosixPath(m.name).parts, m.name
    initial = remote('hostname; whoami; pwd; uname -a; df -h /; '
                     'systemctl show astrbot -p ActiveState -p NRestarts -p ExecMainPID')
    (REPORT / 'board-before.txt').write_bytes(initial.stdout)
    with tarfile.open(package) as t:
        expected = hashlib.sha256(t.extractfile(PREFIX[1:] + '/bin/node').read()).hexdigest()
    existing = remote('test -e ' + PREFIX, check=False)
    if existing.returncode == 0:
        actual = remote('sha256sum ' + NODE).stdout.decode().split()[0]
        assert actual == expected, 'Existing installation differs; do not overwrite a running binary'
    else:
        with package.open('rb') as src:
            p = subprocess.run(SSH + ['tar -xJf - -C /'], stdin=src,
                               stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=300)
        assert p.returncode == 0, p.stderr.decode(errors='replace')
        actual = remote('sha256sum ' + NODE).stdout.decode().split()[0]
        assert actual == expected, 'Node checksum differs after deployment'

    smoke = PROJECT / 'scripts/node24/smoke-test.mjs'
    remote('cat > /tmp/hi3798-node24-smoke.mjs', data=smoke.read_bytes())
    d = save_result('board-smoke', ray_node(['/tmp/hi3798-node24-smoke.mjs'], check=False))
    assert d.get('allPassed'), 'Core smoke tests failed; do not add PATH links'

    candidates = '/home/boarduser/node24-validation-20261026'
    native_script = PROJECT / 'scripts/node24/test-native-candidates.mjs'
    remote('cat > ' + candidates + '/test-native-candidates.mjs', data=native_script.read_bytes())
    save_result('board-native-candidates', ray_node([candidates + '/test-native-candidates.mjs'], check=False))

    network_js = '''
const r=await fetch('https://registry.npmjs.org/@deepseek-ai%2Fdsh/latest', {signal:AbortSignal.timeout(30000)});
if(!r.ok)throw new Error(`HTTP ${r.status}`);
const p=await r.json();console.log(JSON.stringify({https:true,status:r.status,package:p.name,version:p.version}));
'''
    save_result('board-https', ray_node(['--input-type=module', '-e', network_js], check=False, timeout=60))
    npm = ray_node([PREFIX + '/lib/node_modules/npm/bin/npm-cli.js', '--version'])
    links_js = f'''
import os,json
prefix={PREFIX!r}
result={{}}
for name in ['node','npm','npx']:
    src=prefix+'/bin/'+name;dst='/usr/local/bin/'+name
    if os.path.lexists(dst):
        if os.path.realpath(dst)!=os.path.realpath(src):
            raise SystemExit('Existing command differs: '+dst)
    else:os.symlink(src,dst)
    result[name]=os.readlink(dst)
print(json.dumps(result))
'''
    links = remote('/opt/py3_12/bin/python -B -', data=links_js.encode())
    (REPORT / 'board-command-links.json').write_bytes(links.stdout)
    runtime = remote('hostname; whoami; pwd; ' + NODE + ' --version; '
                     'runuser -u boarduser -- sh -c "command -v node; node --version; npm --version; npx --version"; '
                     'file ' + NODE + '; readelf -A ' + NODE + '; ldd ' + NODE + '; '
                     'du -sh ' + PREFIX + '; df -h /; '
                     'systemctl show astrbot -p ActiveState -p NRestarts -p ExecMainPID')
    (REPORT / 'board-runtime.txt').write_bytes(runtime.stdout + b'\nSTDERR:\n' + runtime.stderr)
    summary = {'node_sha256': expected, 'prefix': PREFIX,
               'npm_version': npm.stdout.decode().strip(), 'core_tests_passed': True,
               'native_tests': str(REPORT / 'board-native-candidates.json'),
               'https_test': str(REPORT / 'board-https.json')}
    (REPORT / 'deployment-summary.json').write_text(json.dumps(summary, indent=2))
    print(json.dumps(summary, indent=2), flush=True)


if __name__ == '__main__':
    main()
