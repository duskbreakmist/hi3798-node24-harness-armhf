import {createRequire} from 'node:module';
import {pathToFileURL} from 'node:url';
import {execFileSync,spawnSync} from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import assert from 'node:assert/strict';
const root=path.resolve(process.argv[2] || '/home/boarduser/deepseek-harness-armhf');
const require=createRequire(path.join(root,'package.json'));
const results=[];
async function check(name,fn){try{results.push({name,pass:true,details:await fn()});}catch(error){results.push({name,pass:false,error:String(error.stack||error)});}}
await check('published-js-builtin-loader',()=>{
 const api=require('node-addon-require-builtin');
 assert.equal(typeof api.requireBuiltin('internal/modules/cjs/loader').Module,'function');
 assert.equal(typeof api.requireBuiltin('internal/modules/esm/loader').createModuleLoader,'function');
 return api.getBindingInfo();
});
await check('koffi-override',()=>{
 const koffi=require('koffi');assert.equal(koffi.version,'3.3.4');
 assert.equal(koffi.load('libc.so.6').func('int getpid(void)')(),process.pid);
 return {version:koffi.version};
});
await check('sharp-png',async()=>{
 const sharp=require('sharp');
 const data=await sharp({create:{width:32,height:32,channels:3,background:'#42aaff'}}).resize(16,16).png().toBuffer();
 const meta=await sharp(data).metadata();assert.equal(meta.width,16);assert.equal(meta.height,16);
 return {version:sharp.versions.sharp,libvips:sharp.versions.vips};
});
await check('published-pty-wrapper',()=>new Promise((resolve,reject)=>{
 const pty=require('node-pty');let output='';
 const term=pty.spawn('/bin/sh',['-c','printf "harness-armhf-pty-ok\\n"'],{name:'xterm',cols:80,rows:24,cwd:'/tmp',env:process.env});
 const timer=setTimeout(()=>{term.kill();reject(new Error('PTY timeout'));},10000);
 term.onData(chunk=>output+=chunk);
 term.onExit(({exitCode})=>{clearTimeout(timer);try{assert.equal(exitCode,0);assert.match(output,/harness-armhf-pty-ok/);resolve({output:output.trim()});}catch(error){reject(error);}});
}));
await check('published-flock-wrapper',async()=>{
 const {tryLockExclusive}=await import(pathToFileURL(require.resolve('@deepseek-ai/node-addon-system/flock')));
 const dir=fs.mkdtempSync(path.join(os.tmpdir(),'harness-armhf-lock-'));
 let a,b;
 try{
  const file=path.join(dir,'lock');a=fs.openSync(file,'w+');b=fs.openSync(file,'r+');
  await tryLockExclusive(a);
  await assert.rejects(tryLockExclusive(b),{code:'EAGAIN'});
  fs.closeSync(a);a=undefined;await tryLockExclusive(b);
  return {contentionRejected:true,release:true};
 }finally{if(a!==undefined)fs.closeSync(a);if(b!==undefined)fs.closeSync(b);fs.rmSync(dir,{recursive:true,force:true});}
});
await check('ripgrep-platform-package',()=>{
 const {rgPath}=require('@vscode/ripgrep');
 const version=execFileSync(rgPath,['--version'],{encoding:'utf8'}).split('\n')[0];
 assert.match(version,/ripgrep/);return {path:rgPath,version};
});
const landlock=await import(pathToFileURL(require.resolve('@deepseek-ai/node-addon-system/landlock-run')));
const bwrap=spawnSync('bwrap',['--ro-bind','/','/','--dev','/dev','--unshare-pid','--proc','/proc','--die-with-parent','--','/bin/true'],{encoding:'utf8',timeout:5000});
console.log(JSON.stringify({node:process.version,arch:process.arch,results,allPassed:results.every(x=>x.pass),sandbox:{landlock:landlock.probe(),bwrapExit:bwrap.status,bwrapError:bwrap.stderr},maxRssKiB:process.resourceUsage().maxRSS},null,2));
process.exitCode=results.every(x=>x.pass)?0:1;
