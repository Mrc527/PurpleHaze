#!/usr/bin/env node
'use strict';
const fs=require('node:fs');
const path=require('node:path');
const crypto=require('node:crypto');
const {spawnSync}=require('node:child_process');
const tag=process.env.RELEASE_TAG, sha=process.env.RELEASE_SHA;
if(!/^v[0-9]+\.[0-9]+\.[0-9]+(?:[-+][A-Za-z0-9.-]+)?$/.test(tag||''))throw Error('Invalid release tag');
if(!/^[a-f0-9]{40}$/.test(sha||''))throw Error('Invalid release commit');
const directory='artifacts/release';
const names=['PurpleHaze-Android-unsigned.apk','PurpleHaze-Android-unsigned.aab','PurpleHaze-iOS-unsigned.app.zip'];
const checksums=names.map(name=>{
 const file=path.join(directory,name);if(!fs.statSync(file).isFile()||fs.statSync(file).size<1024)throw Error(`Missing build artifact: ${name}`);
 return crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex')+'  '+name;
}).join('\n')+'\n';
fs.writeFileSync(path.join(directory,'SHA256SUMS'),checksums);
const notes=`PurpleHaze Android and iOS, built from commit ${sha}.\n\n`+
`These are **unsigned build artifacts**, not store-ready packages.\n\n`+
`- Android APK and AAB require your Android signing key before installation or distribution.\n`+
`- The iOS .app ZIP requires Apple signing and provisioning (including the VPN extension); it is not an installable IPA.\n`+
`- No server keys, signing keys or provisioning profiles are bundled.\n`+
`- Build, profile/security regression checks and Android emulator tests completed before publication.\n\n`+
`SHA256SUMS contains checksums of the three build files. This workflow does not publish to Google Play or the App Store.\n`;
fs.writeFileSync(path.join(directory,'RELEASE-NOTES.md'),notes);
const args=['tools/ci_monitor.cjs','release','create',tag,'--verify-tag','--title',`PurpleHaze ${tag} — unsigned builds`,'--notes-file',path.join(directory,'RELEASE-NOTES.md'),...names.map(name=>path.join(directory,name)),path.join(directory,'SHA256SUMS')];
if(process.env.RELEASE_DRAFT==='true')args.push('--draft');
if(tag.includes('-'))args.push('--prerelease');
const result=spawnSync(process.execPath,args,{stdio:'inherit',env:process.env});
if(result.error)throw result.error;process.exit(result.status??1);
