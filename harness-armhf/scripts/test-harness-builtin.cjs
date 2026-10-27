const assert = require('node:assert/strict');
const path = require('node:path');
const directory = path.resolve(process.argv[2] || '.');
const results = [];
for (const name of ['require-builtin', 'internal-loader']) {
  const addon = require(path.join(directory, name + '-armhf.node'));
  const info = addon.getNativeBindingInfo();
  assert.equal(info.backend, 'nodeabi');
  assert.equal(info.abi, 'node-v' + process.versions.modules);
  const cjs = addon.requireBuiltin('internal/modules/cjs/loader');
  const esm = addon.requireBuiltin('internal/modules/esm/loader');
  assert.equal(typeof cjs.Module, 'function');
  assert.equal(typeof esm.createModuleLoader, 'function');
  let denied = null;
  if (name === 'require-builtin') {
    assert.equal(typeof addon.requireBuiltin('internal/bootstrap/realm').internalBinding, 'function');
  } else {
    assert.equal(addon.isAllowedInternalId('internal/bootstrap/realm'), false);
    assert.throws(() => addon.requireBuiltin('internal/bootstrap/realm'), error => {
      denied = error.code;
      return typeof denied === 'string';
    });
  }
  results.push({name, info, cjs: true, esm: true, denied});
}
console.log(JSON.stringify({node: process.version, arch: process.arch, results, allPassed: true}, null, 2));
