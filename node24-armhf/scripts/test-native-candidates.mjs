import {createRequire} from 'node:module';
import {execFileSync} from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import assert from 'node:assert/strict';
const require=createRequire(import.meta.url), results=[];
async function check(name,fn) {try {const details=await fn();results.push({name,pass:true,details});} catch(e){results.push({name,pass:false,error:String(e.stack||e)});}}
await check('koffi-libc-getpid',()=>{const koffi=require('koffi'); const libc=koffi.load('libc.so.6');assert.equal(libc.func('int getpid(void)')(),process.pid);return {version:koffi.version};});
await check('sharp-libvips-resize',async()=>{const sharp=require('sharp');const image=await sharp({create:{width:32,height:32,channels:3,background:'#42aaff'}}).resize(16,16).png().toBuffer();const meta=await sharp(image).metadata();assert.equal(meta.width,16);assert.equal(meta.height,16);return {versions:sharp.versions,outputBytes:image.length};});
await check('node-pty-shell',async()=>{const pty=require('node-pty');return await new Promise((resolve,reject)=>{let text='';const term=pty.spawn('/bin/sh',['-c','printf "pty-armhf-ok\\n"'],{name:'xterm',cols:80,rows:24,cwd:'/tmp',env:process.env});const timer=setTimeout(()=>{term.kill();reject(new Error('PTY timeout'));},10000);term.onData(chunk=>{text+=chunk;});term.onExit(({exitCode})=>{clearTimeout(timer);try{assert.equal(exitCode,0);assert.match(text,/pty-armhf-ok/);resolve({text:text.trim()});}catch(e){reject(e);}});});});
await check('flock-contention',async()=>{const binding=require('./flock.node'),dir=fs.mkdtempSync(path.join(os.tmpdir(),'node24-flock-')),file=path.join(dir,'lock');let a,b;try{a=fs.openSync(file,'w+');b=fs.openSync(file,'r+');const lock=fd=>new Promise(resolve=>binding.tryLock(fd,resolve));assert.equal(await lock(a),0);assert.equal(await lock(b),os.constants.errno.EAGAIN);fs.closeSync(a);a=undefined;assert.equal(await lock(b),0);return {exclusive:true,nonblocking:true};}finally{if(a!==undefined)fs.closeSync(a);if(b!==undefined)fs.closeSync(b);fs.rmSync(dir,{recursive:true,force:true});}});
await check('ripgrep-arm-executable',()=>{const {rgPath}=require('@vscode/ripgrep');fs.chmodSync(rgPath,0o755);const version=execFileSync(rgPath,['--version'],{encoding:'utf8'});assert.match(version,/ripgrep/);const dir=fs.mkdtempSync(path.join(os.tmpdir(),'node24-rg-'));try{const file=path.join(dir,'input.txt');fs.writeFileSync(file,'plain\nneedle-armhf\n');assert.equal(execFileSync(rgPath,['--fixed-strings','needle-armhf',file],{encoding:'utf8'}).trim(),'needle-armhf');}finally{fs.rmSync(dir,{recursive:true,force:true});}return {version:version.split('\n')[0],search:true};});
console.log(JSON.stringify({node:process.version,arch:process.arch,results,allPassed:results.every(x=>x.pass)},null,2));
process.exitCode=results.every(x=>x.pass)?0:1;
