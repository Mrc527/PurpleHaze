#!/usr/bin/env node
'use strict';
// Observable, argument-safe gh wrapper. Never passes arguments through a shell.
const {spawnSync}=require('node:child_process');
const fs=require('node:fs');
const path=require('node:path');
const argv=process.argv.slice(2), command=argv.shift();
const help=`Usage: node tools/ci_monitor.cjs COMMAND [arguments]
  runs [gh run list arguments]
  view RUN_ID [gh run view arguments]
  watch RUN_ID [--exit-status]
  log-failed RUN_ID
  dispatch WORKFLOW [gh workflow run arguments]
  workflows [gh workflow list arguments]
  api ENDPOINT [gh api arguments]   (metadata/settings; never print secret values)
  action-ref OWNER/REPO TAG
  check-actions [workflow file or directory]
  release [gh release arguments]
  --help
Defaults to git remote origin (including forks), never the upstream repository.
Set GH_REPO=owner/repository or use gh arguments --repo where supported to override.
Every command logs its executable and argument vector before execution.`;
function repositoryEnvironment(args){
 const env={...process.env};
 const explicit=args.some(a=>a==='--repo'||a.startsWith('--repo=')||a==='-R'||/^-[R][^ ]+/.test(a));
 if(env.GH_REPO||explicit)return env;
 const remote=spawnSync('git',['remote','get-url','origin'],{encoding:'utf8',stdio:['ignore','pipe','ignore']});
 if(remote.status===0){
  let host,pathname;const origin=remote.stdout.trim();
  try{
   if(origin.includes('://')){const url=new URL(origin);host=url.hostname;pathname=url.pathname;}
   else{const match=origin.match(/^(?:[^@/]+@)?([^:/]+):(.+)$/);if(match){host=match[1];pathname=match[2];}}
   const parts=(pathname||'').replace(/^\/+|\/+$/g,'').replace(/\.git$/,'').split('/');
   if(host&&parts.length===2&&parts.every(p=>/^[A-Za-z0-9_.-]+$/.test(p)))env.GH_REPO=(host==='github.com'?'':host+'/')+parts.join('/');
  }catch(_){/* A non-GitHub origin must be overridden explicitly. */}
 }
 if(!env.GH_REPO&&['run','workflow','release'].includes(args[0]))throw Error('Cannot resolve GitHub repository from origin; set GH_REPO or --repo explicitly');
 return env;
}
function gh(args,capture=false){console.error('[ci_monitor]',JSON.stringify(['gh',...args]));const r=spawnSync('gh',args,{encoding:'utf8',stdio:capture?['inherit','pipe','inherit']:'inherit',env:repositoryEnvironment(args)});if(r.error)throw r.error;if(r.status!==0)throw new Error(`gh exited ${r.status}`);return capture?r.stdout.trim():'';}
function ref(repo,tag){const r=JSON.parse(gh(['api',`repos/${repo}/git/ref/tags/${tag}`],true));return r.object.type==='tag'?JSON.parse(gh(['api',`repos/${repo}/git/tags/${r.object.sha}`],true)).object.sha:r.object.sha;}
try{
 if(!command||command==='--help'){console.log(help);process.exit(0);}
 const routes={runs:['run','list'],view:['run','view'],watch:['run','watch'],'log-failed':['run','view'],dispatch:['workflow','run'],workflows:['workflow','list'],api:['api'],release:['release']};
 if(command==='action-ref'){if(argv.length!==2)throw Error('action-ref needs OWNER/REPO TAG');console.log(ref(argv[0],argv[1]));}
 else if(command==='check-actions'){
  const target=argv[0]||'.github/workflows';const files=fs.statSync(target).isDirectory()?fs.readdirSync(target).filter(x=>/\.ya?ml$/.test(x)).map(x=>path.join(target,x)):[target];
  let count=0;const checked=new Map();for(const file of files)for(const line of fs.readFileSync(file,'utf8').split('\n')){
   const use=line.match(/\buses:\s+([^\s#]+)(?:\s+#\s*(v[\w.-]+))?/);if(!use||use[1].startsWith('./'))continue;
   const [repo,sha]=use[1].split('@');if(!/^[0-9a-f]{40}$/.test(sha||''))throw Error(`${file}: action not pinned: ${use[1]}`);
   if(!use[2])throw Error(`${file}: add verified version comment for ${repo}`);
   const key=repo+'@'+use[2];let current=checked.get(key);if(!current){current=ref(repo,use[2]);checked.set(key,current);}
   if(current!==sha)throw Error(`${file}: ${repo}@${use[2]} resolves to ${current}, not ${sha}`);
   console.log(`VERIFIED ${file}: ${repo}@${use[2]} ${sha}`);count++;
  }console.log(`${count} pinned action references verified`);
 }else if(routes[command])gh([...routes[command],...argv,...(command==='log-failed'?['--log-failed']:[])]);else throw Error(`Unknown command ${command}; run --help`);
}catch(e){console.error('[ci_monitor] ERROR:',e.message);process.exit(1);}
