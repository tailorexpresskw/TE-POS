import {spawnSync} from 'node:child_process';
import {cpSync, mkdirSync} from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
const root=fileURLToPath(new URL('..',import.meta.url));
const flutter=process.env.FLUTTER_BIN || (process.platform==='win32'?'flutter.bat':'flutter');
const args=['build','web','--release','--base-href=/pos/','--pwa-strategy=none','--no-web-resources-cdn'];
const result=process.platform==='win32'
  ?spawnSync(process.env.ComSpec||'cmd.exe',['/d','/s','/c',`""${flutter.replaceAll('/','\\')}" ${args.join(' ')}"`],{cwd:path.join(root,'frontend'),stdio:'inherit',windowsVerbatimArguments:true,windowsHide:true})
  :spawnSync(flutter,args,{cwd:path.join(root,'frontend'),stdio:'inherit'});
if(result.error)throw result.error;
if(result.status!==0)process.exit(result.status??1);
mkdirSync(path.join(root,'public','pos'),{recursive:true});
cpSync(path.join(root,'frontend','build','web'),path.join(root,'public','pos'),{recursive:true});
console.log('Flutter Web assets prepared at public/pos.');
