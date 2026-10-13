#!/usr/bin/env node
'use strict';
// Exercises publication packaging without calling GitHub or creating a release.
const assert=require('node:assert/strict');
const fs=require('node:fs'), os=require('node:os'), path=require('node:path');
const crypto=require('node:crypto');
const {spawnSync}=require('node:child_process');
const root=path.resolve(__dirname,'..');
const fixture=fs.mkdtempSync(path.join(os.tmpdir(),'purplehaze-release-tests-'));
try {
 fs.mkdirSync(path.join(fixture,'tools'));fs.mkdirSync(path.join(fixture,'bin'));fs.mkdirSync(path.join(fixture,'artifacts/release'),{recursive:true});
 fs.copyFileSync(path.join(root,'tools/ci_monitor.cjs'),path.join(fixture,'tools/ci_monitor.cjs'));
 const capture=path.join(fixture,'gh-args.json');
 fs.writeFileSync(path.join(fixture,'bin/gh'),'#!/usr/bin/env node\nrequire("node:fs").writeFileSync(process.env.CI_TEST_CAPTURE,JSON.stringify(process.argv.slice(2)));\n',{mode:0o755});
 const sha='a'.repeat(40);
 const env={...process.env,PATH:path.join(fixture,'bin')+path.delimiter+process.env.PATH,CI_TEST_CAPTURE:capture,GH_REPO:'Mrc527/PurpleHaze',RELEASE_TAG:'v1.2.3-rc.1',RELEASE_SHA:sha,RELEASE_DRAFT:'true'};
 function run(changes={}){return spawnSync(process.execPath,[path.join(root,'tools/release-publish.cjs')],{cwd:fixture,env:{...env,...changes},encoding:'utf8'});}
 assert.notEqual(run({RELEASE_TAG:'v1.2.3; touch unsafe'}).status,0);assert.ok(!fs.existsSync(capture));console.log('PASS: rejects malformed release tags before publication');
 assert.notEqual(run({RELEASE_SHA:'main'}).status,0);assert.ok(!fs.existsSync(capture));console.log('PASS: rejects mutable/non-commit references');
 assert.notEqual(run().status,0);assert.ok(!fs.existsSync(capture));console.log('PASS: missing artifacts cannot publish');
 const names=['PurpleHaze-Android-unsigned.apk','PurpleHaze-Android-unsigned.aab','PurpleHaze-iOS-unsigned.app.zip'];
 for(const [i,name] of names.entries())fs.writeFileSync(path.join(fixture,'artifacts/release',name),Buffer.alloc(2048,i+1));
 const result=run();assert.equal(result.status,0,result.stderr);
 const args=JSON.parse(fs.readFileSync(capture));assert.deepEqual(args.slice(0,3),['release','create','v1.2.3-rc.1']);
 for(const flag of ['--verify-tag','--draft','--prerelease','--notes-file'])assert.ok(args.includes(flag));
 for(const name of names)assert.ok(args.includes('artifacts/release/'+name));assert.ok(args.includes('artifacts/release/SHA256SUMS'));
 console.log('PASS: exact unsigned files, verified tag and draft/prerelease arguments');
 const sums=fs.readFileSync(path.join(fixture,'artifacts/release/SHA256SUMS'),'utf8');
 for(const name of names){const hash=crypto.createHash('sha256').update(fs.readFileSync(path.join(fixture,'artifacts/release',name))).digest('hex');assert.ok(sums.includes(hash+'  '+name+'\n'));}
 const notes=fs.readFileSync(path.join(fixture,'artifacts/release/RELEASE-NOTES.md'),'utf8');assert.ok(notes.includes(sha));assert.ok(notes.includes('not an installable IPA'));console.log('PASS: accurate SHA-256 manifest and unsigned release notes');
 const stable=run({RELEASE_TAG:'v1.2.3',RELEASE_DRAFT:'false'});assert.equal(stable.status,0,stable.stderr);
 const stableArgs=JSON.parse(fs.readFileSync(capture));assert.ok(!stableArgs.includes('--draft'));assert.ok(!stableArgs.includes('--prerelease'));console.log('PASS: stable tag produces a regular release when requested');
} finally {fs.rmSync(fixture,{recursive:true,force:true});}
