import {spawn} from 'node:child_process';
import {mkdirSync,writeFileSync} from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {createApp} from '../server/index.mjs';
const output=path.resolve('outputs');mkdirSync(output,{recursive:true});
const app=await createApp({dataDirectory:path.join(output,'browser-standalone-'+randomUUID()),production:false});
await new Promise(resolve=>app.server.listen(0,'127.0.0.1',resolve));
const base='http://127.0.0.1:'+app.server.address().port;
const password='QA-'+randomUUID();await app.auth.createOwner({name:'QA Owner',email:'qa@pos.test',password});
const login=await fetch(base+'/api/auth/login',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({email:'qa@pos.test',password})});
const session=login.headers.get('set-cookie').split(';')[0].split('=')[1];
const chrome=process.env.CHROME_BIN||'C:/Program Files/Google/Chrome/Application/chrome.exe';
const child=spawn(chrome,['--headless=new','--disable-gpu','--no-first-run','--no-default-browser-check','--remote-debugging-port=9333',`--user-data-dir=${path.join(output,'chrome-qa-profile')}`,'about:blank'],{windowsHide:true,stdio:'ignore'});
const sleep=ms=>new Promise(resolve=>setTimeout(resolve,ms));
let ws;
try{
  let pages;
  for(let i=0;i<50;i++){try{pages=await(await fetch('http://127.0.0.1:9333/json/list')).json();if(pages.length)break;}catch{}await sleep(200);}
  assert.ok(pages?.length,'Chrome did not start.');
  ws=new WebSocket(pages.find(p=>p.type==='page').webSocketDebuggerUrl);
  await new Promise((resolve,reject)=>{ws.onopen=resolve;ws.onerror=reject;});
  let seq=0;const pending=new Map(),errors=[];
  ws.onmessage=event=>{const msg=JSON.parse(event.data);if(msg.id){const p=pending.get(msg.id);if(p){pending.delete(msg.id);msg.error?p.reject(msg.error):p.resolve(msg.result);}}else if(msg.method==='Runtime.exceptionThrown'){errors.push(msg.params.exceptionDetails.exception?.description??msg.params.exceptionDetails.text);}};
  const send=(method,params={})=>new Promise((resolve,reject)=>{const id=++seq;pending.set(id,{resolve,reject});ws.send(JSON.stringify({id,method,params}));});
  const evaluate=async expression=>(await send('Runtime.evaluate',{expression,returnByValue:true,awaitPromise:true})).result?.value;
  const waitFor=async expression=>{for(let i=0;i<100;i++){if(await evaluate(expression))return;await sleep(200);}const picture=await send('Page.captureScreenshot',{format:'png'});writeFileSync(path.join(output,'browser-failure.png'),Buffer.from(picture.data,'base64'));writeFileSync(path.join(output,'browser-dom.txt'),await evaluate('document.body.outerHTML'));throw new Error('Timed out: '+expression);};
  await send('Page.enable');await send('Runtime.enable');await send('Network.enable');
  await send('Emulation.setDeviceMetricsOverride',{width:1440,height:900,deviceScaleFactor:1,mobile:false});
  await send('Page.navigate',{url:base+'/pos/'});
  await waitFor("!!document.querySelector('flt-semantics-placeholder')");
  await evaluate("const p=document.querySelector('flt-semantics-placeholder');p.dispatchEvent(new MouseEvent('mousedown',{bubbles:true}));p.dispatchEvent(new MouseEvent('mouseup',{bubbles:true}));p.click()");
  await waitFor("document.body.innerText.includes('Staff sign in')");
  const loginPicture=await send('Page.captureScreenshot',{format:'png'});writeFileSync(path.join(output,'pos-login.png'),Buffer.from(loginPicture.data,'base64'));
  await send('Network.setCookie',{name:'te_pos_session',value:session,url:base,httpOnly:true,sameSite:'Strict'});
  await send('Page.reload',{ignoreCache:true});
  await waitFor("!!document.querySelector('flt-semantics-placeholder')");
  await evaluate("document.querySelector('flt-semantics-placeholder').click()");
  const click=async label=>{
    const expr=`(()=>{const el=[...document.querySelectorAll('[role=button]')].find(e=>(e.getAttribute('aria-label')||e.textContent||'').trim()===${JSON.stringify(label)});if(!el)return false;el.click();return true;})()`;
    await waitFor(expr);await sleep(600);
  };
  await click('Zahra Complex');
  await click('POS');
  await waitFor("document.body.innerText.includes('Hem- Skirt') || [...document.querySelectorAll('[aria-label]')].some(e=>(e.getAttribute('aria-label')||'').includes('Hem- Skirt'))");
  await sleep(1500);
  for(const [name,width,height] of [['desktop',1440,900],['phone',390,844]]){
    await send('Emulation.setDeviceMetricsOverride',{width,height,deviceScaleFactor:1,mobile:width<600});await sleep(700);
    const screenshot=await send('Page.captureScreenshot',{format:'png',captureBeyondViewport:false});writeFileSync(path.join(output,`pos-${name}.png`),Buffer.from(screenshot.data,'base64'));
  }
  assert.deepEqual(errors,[],'Browser runtime exceptions');
  console.log('Chrome release QA passed: Flutter rendered, branch selected, POS opened, desktop and phone screenshots saved.');
  await send('Browser.close').catch(()=>{});
} finally {ws?.close();if(child.exitCode===null)child.kill();await app.close();}
