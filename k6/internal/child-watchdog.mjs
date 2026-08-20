#!/usr/bin/env node

import {spawn} from 'node:child_process';

let raw='';
for await(const chunk of process.stdin)raw+=chunk;
const request=JSON.parse(raw);
const timeoutMs=Math.max(1,Number(request.timeoutMs));
const child=spawn(request.command,request.args,{cwd:request.cwd||undefined,env:request.env||process.env,detached:true,stdio:[request.inputBase64?'pipe':'ignore','pipe','pipe']});
if(request.inputBase64)child.stdin.end(Buffer.from(request.inputBase64,'base64'));
const stdout=[],stderr=[];let stdoutBytes=0,stderrBytes=0;const maximum=Number(request.maxBuffer)||32*1024*1024;
child.stdout.on('data',chunk=>{stdoutBytes+=chunk.length;if(stdoutBytes<=maximum)stdout.push(chunk);});
child.stderr.on('data',chunk=>{stderrBytes+=chunk.length;if(stderrBytes<=maximum)stderr.push(chunk);});
let timedOut=false,killTimer=null;
const signal=kind=>{try{process.kill(-child.pid,kind);}catch{child.kill(kind);}};
const timer=setTimeout(()=>{timedOut=true;signal('SIGTERM');killTimer=setTimeout(()=>signal('SIGKILL'),10_000);},timeoutMs);
const result=await new Promise(resolveResult=>{child.once('error',error=>resolveResult({status:null,error:error.message}));child.once('close',(status,signal)=>resolveResult({status,signal}));});
clearTimeout(timer);if(killTimer)clearTimeout(killTimer);
process.stdout.write(JSON.stringify({...result,timedOut,stdout:Buffer.concat(stdout).toString('base64'),stderr:Buffer.concat(stderr).toString('base64'),overflow:stdoutBytes>maximum||stderrBytes>maximum}));
