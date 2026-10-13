#!/usr/bin/env node
'use strict';
const assert=require('node:assert/strict');
const fs=require('node:fs'),os=require('node:os'),path=require('node:path');
const {spawnSync}=require('node:child_process');
const script=path.join(__dirname,'ci_monitor.cjs');
const fixture=fs.mkdtempSync(path.join(os.tmpdir(),'purplehaze-monitor-tests-'));
try {
 const bin=path.join(fixture,'bin');fs.mkdirSync(bin);
 fs.writeFileSync(path.join(bin,'git'),'#!/usr/bin/env node\nif(!process.env.CI_TEST_ORIGIN)process.exit(1);console.log(process.env.CI_TEST_ORIGIN);\n',{mode:0o755});
 fs.writeFileSync(path.join(bin,'gh'),'#!/usr/bin/env node\nconsole.log(JSON.stringify({repo:process.env.GH_REPO||null,args:process.argv.slice(2)}));\n',{mode:0o755});
 function run(origin,extra=[],repo){const env={...process.env,PATH:bin+path.delimiter+process.env.PATH,CI_TEST_ORIGIN:origin||''};delete env.GH_REPO;if(repo)env.GH_REPO=repo;return spawnSync(process.execPath,[script,'runs',...extra],{cwd:fixture,env,encoding:'utf8'});}
 for(const origin of ['https://github.com/Mrc527/PurpleHaze.git','https://someone:password@github.com/Mrc527/PurpleHaze.git','git@github.com:Mrc527/PurpleHaze.git','ssh://git@github.com/Mrc527/PurpleHaze.git']){
  const result=run(origin);assert.equal(result.status,0,result.stderr);assert.equal(JSON.parse(result.stdout).repo,'Mrc527/PurpleHaze');assert.ok(!result.stderr.includes('password'));
 }console.log('PASS: HTTPS, credentialled HTTPS, SCP and SSH origins select the fork without logging credentials');
 let result=run('git@github.com:Other/Origin.git',[],'Explicit/Repository');assert.equal(JSON.parse(result.stdout).repo,'Explicit/Repository');console.log('PASS: explicit GH_REPO takes precedence');
 for(const args of [['--repo','Explicit/Flag'],['--repo=Explicit/Flag'],['-R','Explicit/Flag'],['-RExplicit/Flag']]){
  result=run('git@github.com:Other/Origin.git',args);assert.equal(result.status,0,result.stderr);const received=JSON.parse(result.stdout);assert.equal(received.repo,null);assert.deepEqual(received.args,['run','list',...args]);
 }console.log('PASS: explicit repository flags are preserved');
 result=run('ssh://git@github.company.example/Team/App.git');assert.equal(JSON.parse(result.stdout).repo,'github.company.example/Team/App');console.log('PASS: enterprise SSH origin retains host');
 result=run(null);assert.notEqual(result.status,0);assert.equal(result.stdout,'');console.log('PASS: ambiguous origin fails instead of silently operating on upstream');
}finally{fs.rmSync(fixture,{recursive:true,force:true});}
