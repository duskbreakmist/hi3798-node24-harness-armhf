import assert from 'node:assert/strict';
import os from 'node:os';
import fs from 'node:fs/promises';
import path from 'node:path';
import crypto from 'node:crypto';
import zlib from 'node:zlib';
import { execFileSync } from 'node:child_process';
import { Worker } from 'node:worker_threads';
import http from 'node:http';
import { DatabaseSync } from 'node:sqlite';
const results = [];
async function check(name, fn) {
  const started = Date.now();
  try { await fn(); results.push({name, pass:true, ms:Date.now()-started}); }
  catch (e) { results.push({name, pass:false, error:String(e.stack || e)}); }
}
await check('arm-runtime', () => { assert.equal(process.arch,'arm'); assert.equal(process.platform,'linux'); assert.match(process.version,/^v24\./); });
await check('v8-jit', () => { let x=0; for(let i=0;i<1_000_000;i++) x=(x+i)%65521; assert.equal(x,34707); });
await check('crypto', () => { assert.equal(crypto.createHash('sha256').update('abc').digest('hex'),'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad'); assert.equal(crypto.randomBytes(32).length,32); });
await check('zlib-neon-crc', () => { const b=Buffer.alloc(1024*1024); for(let i=0;i<b.length;i++) b[i]=i%251; assert.deepEqual(zlib.gunzipSync(zlib.gzipSync(b)),b); });
await check('filesystem', async () => { const d=await fs.mkdtemp(path.join(os.tmpdir(),'node24-smoke-')); try {await fs.writeFile(path.join(d,'a'),'armhf'); await fs.rename(path.join(d,'a'),path.join(d,'b')); assert.equal(await fs.readFile(path.join(d,'b'),'utf8'),'armhf');} finally {await fs.rm(d,{recursive:true,force:true});} });
await check('child-process', () => { assert.equal(execFileSync(process.execPath,['-p','6*7'],{encoding:'utf8'}).trim(),'42'); });
await check('worker-threads', async () => { assert.equal(await new Promise((resolve,reject) => { const w=new Worker("require('node:worker_threads').parentPort.postMessage(6*7)",{eval:true}); w.once('message',resolve); w.once('error',reject); }),42); });
await check('sqlite-builtin', () => { const db=new DatabaseSync(':memory:'); try {db.exec('create table t (v integer)'); db.prepare('insert into t values (?)').run(42); assert.equal(db.prepare('select v from t').get().v,42);} finally {db.close();} });
await check('intl-full-icu', () => {assert.equal(Intl.DateTimeFormat.supportedLocalesOf(['zh-CN','ja-JP']).length,2);});
await check('webassembly', async () => {const m=await WebAssembly.instantiate(new Uint8Array([0,97,115,109,1,0,0,0])); assert.ok(m.instance);});
await check('wasm-i64-optimizing-lowering', () => {
  function verify() {
    const bytes=[0,97,115,109,1,0,0,0,1,6,1,96,1,126,1,126,3,3,2,0,0,7,13,2,3,99,108,122,0,0,3,99,116,122,0,1,10,13,2,5,0,32,0,121,11,5,0,32,0,122,11];
    const {clz,ctz}=new WebAssembly.Instance(new WebAssembly.Module(new Uint8Array(bytes))).exports;
    for (const [input,leading,trailing] of [[0n,64n,64n],[1n,63n,0n],[1n<<32n,31n,32n],[1n<<40n,23n,40n],[-1n,0n,0n]]) {
      if(clz(input)!==leading || ctz(input)!==trailing) throw new Error('i64 clz/ctz mismatch: '+input);
    }
    console.log('wasm-i64-lowering-ok');
  }
  const output=execFileSync(process.execPath,['--no-liftoff','-e',`(${verify.toString()})()`],{encoding:'utf8',timeout:30000});
  assert.match(output,/wasm-i64-lowering-ok/);
});
await check('http-fetch-loopback', async () => {const server=http.createServer((req,res)=>res.end('armhf-ok')); await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve)); try {const r=await fetch(`http://127.0.0.1:${server.address().port}`,{signal:AbortSignal.timeout(10000)}); assert.equal(await r.text(),'armhf-ok');} finally {await new Promise(resolve=>server.close(resolve));}});
console.log(JSON.stringify({version:process.version,arch:process.arch,platform:process.platform,kernel:os.release(),versions:process.versions,memoryUsage:process.memoryUsage(),resourceUsage:process.resourceUsage(),results,allPassed:results.every(x=>x.pass)},null,2));
process.exitCode=results.every(x=>x.pass)?0:1;
