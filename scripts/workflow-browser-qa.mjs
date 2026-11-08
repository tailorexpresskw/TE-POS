import {spawn} from 'node:child_process';
import {mkdirSync,writeFileSync} from 'node:fs';
import path from 'node:path';
import {randomUUID} from 'node:crypto';
import assert from 'node:assert/strict';
import {createApp} from '../server/index.mjs';
const output=path.resolve('outputs');mkdirSync(output,{recursive:true});
const app=await createApp({dataDirectory:path.join(output,'workflow-browser-'+randomUUID()),production:false});
await new Promise(resolve=>app.server.listen(0,'127.0.0.1',resolve));
const base=`http://127.0.0.1:${app.server.address().port}`,password='QA-'+randomUUID(),sessions={};
await app.auth.createOwner({name:'QA Admin',username:'qa.admin',email:'admin@qa.test',password});
async function login(name,username){const r=await fetch(base+'/api/auth/login',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({username,password})});assert.equal(r.status,200);sessions[name]=r.headers.get('set-cookie').split(';')[0].split('=')[1];}
await login('admin','qa.admin');
async function post(route,body){const r=await fetch(base+'/api/'+route,{method:'POST',headers:{'Content-Type':'application/json',Cookie:'te_pos_session='+sessions.admin},body:JSON.stringify(body)});assert.equal(r.status,200,await r.clone().text());return r.json();}
await post('members',{name:'QA Reception',email:'reception@qa.test',role:'reception',branches:['zahra'],password});
await post('members',{name:'QA Manager',username:'qa.manager',role:'manager',branches:['zahra'],password});
await post('members',{name:'QA Supervisor',username:'qa.supervisor',role:'supervisor',branches:['zahra','avenues'],password});
const tailor=await post('members',{name:'QA Tailor',email:'tailor@qa.test',role:'tailor',branches:['zahra'],password});
await post('members',{name:'Other Branch Tailor',email:'other@qa.test',role:'tailor',branches:['avenues'],password});
const customer=await post('customers',{name:'QA Customer',phone:'55551234',address:'Kuwait City'});
await post('orders',{id:randomUUID(),branch:'zahra',kind:'sale',customerId:customer.id,tailorId:tailor.id,lines:[{id:'1001',qty:1,price:2000,note:'Hem to 90 cm'}],payments:[],dueDate:'2026-11-03',notes:'QA garment instructions'});
await login('manager','qa.manager');await login('supervisor','qa.supervisor');await login('reception','reception@qa.test');await login('tailor','tailor@qa.test');
const child=spawn(process.env.CHROME_BIN||'C:/Program Files/Google/Chrome/Application/chrome.exe',['--headless=new','--disable-gpu','--no-first-run','--no-default-browser-check','--remote-debugging-port=9334',`--user-data-dir=${path.join(output,'workflow-chrome-profile')}`,'about:blank'],{stdio:'ignore',windowsHide:true});
const sleep=ms=>new Promise(resolve=>setTimeout(resolve,ms));let ws;
try{
  let pages;for(let n=0;n<50;n++){try{pages=await(await fetch('http://127.0.0.1:9334/json/list')).json();if(pages.length)break;}catch{}await sleep(200);}
  assert.ok(pages?.length,'Chrome did not start.');ws=new WebSocket(pages.find(p=>p.type==='page').webSocketDebuggerUrl);
  await new Promise((resolve,reject)=>{ws.onopen=resolve;ws.onerror=reject;});
  let sequence=0;const pending=new Map(),errors=[];
  ws.onmessage=e=>{const m=JSON.parse(e.data);if(m.id){const p=pending.get(m.id);if(p){pending.delete(m.id);m.error?p.reject(m.error):p.resolve(m.result);}}else if(m.method==='Runtime.exceptionThrown')errors.push(m.params.exceptionDetails.exception?.description??m.params.exceptionDetails.text);};
  const send=(method,params={})=>new Promise((resolve,reject)=>{const id=++sequence;pending.set(id,{resolve,reject});ws.send(JSON.stringify({id,method,params}));});
  const evaluate=async expression=>(await send('Runtime.evaluate',{expression,returnByValue:true,awaitPromise:true,userGesture:true})).result?.value;
  const screenshot=async name=>{const image=await send('Page.captureScreenshot',{format:'png',captureBeyondViewport:false});writeFileSync(path.join(output,name+'.png'),Buffer.from(image.data,'base64'));};
  async function wait(expression){for(let n=0;n<100;n++){if(await evaluate(expression))return;await sleep(150);}await screenshot('workflow-failure');writeFileSync(path.join(output,'workflow-browser-dom.txt'),await evaluate('document.body.outerHTML'));throw new Error('Browser timeout: '+expression);}
  async function click(label){await wait(`(()=>{const e=[...document.querySelectorAll('[role=button]')].find(e=>(e.getAttribute('aria-label')||e.textContent||'').trim().split(String.fromCharCode(10))[0].trim()===${JSON.stringify(label)});if(!e)return false;e.click();return true;})()`);await sleep(300);}
  async function fill(label,text){
    const expression=`(()=>{const e=[...document.querySelectorAll('input,textarea,[role=textbox]')].find(e=>(e.getAttribute('aria-label')||'').includes(${JSON.stringify(label)}));if(!e)return null;const r=e.getBoundingClientRect();return {x:r.x+r.width/2,y:r.y+r.height/2};})()`;
    await wait(`!!(${expression})`);const point=await evaluate(expression);
    await send('Input.dispatchMouseEvent',{type:'mousePressed',...point,button:'left',clickCount:1});
    await send('Input.dispatchMouseEvent',{type:'mouseReleased',...point,button:'left',clickCount:1});
    await send('Input.insertText',{text});await sleep(500);
  }
  async function exportInvoice(label,name,width){
    const before=new Set((await(await fetch('http://127.0.0.1:9334/json/list')).json()).map(p=>p.id));
    await click(label);let target;
    for(let n=0;n<50;n++){target=(await(await fetch('http://127.0.0.1:9334/json/list')).json()).find(p=>!before.has(p.id)&&p.type==='page');if(target)break;await sleep(150);}
    assert.ok(target,'Invoice preview did not open');const socket=new WebSocket(target.webSocketDebuggerUrl);
    await new Promise((resolve,reject)=>{socket.onopen=resolve;socket.onerror=reject;});
    let id=0;const pending=new Map();socket.onmessage=e=>{const m=JSON.parse(e.data);if(m.id){const p=pending.get(m.id);pending.delete(m.id);m.error?p.reject(m.error):p.resolve(m.result);}};
    const call=(method,params={})=>new Promise((resolve,reject)=>{const token=++id;pending.set(token,{resolve,reject});socket.send(JSON.stringify({id:token,method,params}));});
    try{
      await call('Page.enable');await call('Runtime.enable');await call('Emulation.setDeviceMetricsOverride',{width,height:1000,deviceScaleFactor:1,mobile:false});
      for(let n=0;n<50;n++){const r=await call('Runtime.evaluate',{expression:'typeof sizePaper',returnByValue:true});if(r.result.value==='function')break;await sleep(100);}
      await call('Runtime.evaluate',{expression:'sizePaper()',awaitPromise:true});
      const details=(await call('Runtime.evaluate',{expression:"JSON.stringify({text:document.body.innerText,overflow:document.documentElement.scrollWidth>innerWidth,paper:document.querySelector('#paper').textContent})",returnByValue:true})).result.value;
      const info=JSON.parse(details);assert.ok(info.text.includes('Hem to 90 cm'));assert.equal(info.overflow,false);assert.ok(info.paper.includes(name==='invoice-print'?'80mm':'108mm'));
      const pdf=await call('Page.printToPDF',{preferCSSPageSize:true,printBackground:true,displayHeaderFooter:false,marginTop:0,marginBottom:0,marginLeft:0,marginRight:0});
      writeFileSync(path.join(output,name+'.pdf'),Buffer.from(pdf.data,'base64'));
      const picture=await call('Page.captureScreenshot',{format:'png',captureBeyondViewport:true});writeFileSync(path.join(output,name+'.png'),Buffer.from(picture.data,'base64'));
      await call('Page.close');
    }finally{socket.close();}
  }
  const has=text=>`(document.body.innerText.includes(${JSON.stringify(text)})||[...document.querySelectorAll('input,textarea')].some(e=>(e.value||'').includes(${JSON.stringify(text)}))||[...document.querySelectorAll('[aria-label]')].some(e=>(e.getAttribute('aria-label')||'').includes(${JSON.stringify(text)})))`;
  async function account(role){await send('Network.setCookie',{name:'te_pos_session',value:sessions[role],url:base,httpOnly:true,sameSite:'Strict'});await send('Page.navigate',{url:base+'/pos/'});await wait("!!document.querySelector('flt-semantics-placeholder')");await evaluate("document.querySelector('flt-semantics-placeholder').click()");if(role!=='tailor')await click('Zahra Complex');await wait(has(role==='admin'?'Admin Dashboard':role==='reception'?'Reception Dashboard':role==='manager'?'Branch Manager Dashboard':role==='supervisor'?'Supervisor Dashboard':'Tailor Dashboard'));await sleep(400);}
  await send('Page.enable');await send('Runtime.enable');await send('Network.enable');await send('Emulation.setDeviceMetricsOverride',{width:1440,height:900,deviceScaleFactor:1,mobile:false});
  await account('admin');await screenshot('admin-dashboard');
  await wait('!!navigator.serviceWorker.controller');
  const appManifest=await send('Page.getAppManifest');assert.equal(JSON.parse(appManifest.data).display,'standalone');
  const installability=await send('Page.getInstallabilityErrors');assert.deepEqual(installability.installabilityErrors,[],'Chrome PWA install requirements');
  const cached=await evaluate("(async()=>{const names=await caches.keys();const urls=[];for(const name of names.filter(n=>n.startsWith('te-pos-offline-'))){const cache=await caches.open(name);urls.push(...(await cache.keys()).map(r=>new URL(r.url).pathname));}return urls;})()");
  assert.ok(cached.includes('/pos/offline.html'));assert.ok(cached.every(url=>!url.startsWith('/api/')));
  await click('Manage users');await click('Add branch');await wait(has('Invoice code'));await screenshot('admin-add-branch');await click('Cancel');
  // Widget tests exercise both fields and form submission; seed this browser fixture through the API.
  await post('branches',{name:'QA New Branch',code:'NB'});await account('admin');await click('Manage users');await wait(has('QA New Branch'));
  const adminBranches=await evaluate("fetch('/api/boot').then(r=>r.json()).then(b=>b.branches)");assert.ok(adminBranches.some(b=>b.name==='QA New Branch'));assert.ok(!adminBranches.some(b=>b.id==='aventura'));await screenshot('admin-branches');

  await account('manager');assert.equal(await evaluate(has('Administration')),false);await screenshot('manager-dashboard');
  await account('supervisor');assert.equal(await evaluate(has('Administration')),false);assert.equal(await evaluate(has('Manage users')),false);await wait(has('Assigned branches'));await screenshot('supervisor-dashboard');
  const supervised=await evaluate("fetch('/api/boot').then(r=>r.json()).then(b=>b.branches.map(b=>b.id))");assert.deepEqual(supervised.sort(),['avenues','zahra']);
  await send('Emulation.setDeviceMetricsOverride',{width:390,height:844,deviceScaleFactor:1,mobile:true});await sleep(500);await screenshot('supervisor-dashboard-phone');
  await send('Emulation.setDeviceMetricsOverride',{width:1440,height:900,deviceScaleFactor:1,mobile:false});
  await account('reception');await screenshot('reception-dashboard');await click('POS');await wait(has('Hem- Skirt'));await screenshot('reception-pos');await click('Walk-in customer');await fill('Find customer','55551234');await click('QA Customer');await wait(has('Last bill date'));await screenshot('customer-details');await click('Select customer');await click('Hem- Skirt');assert.equal(await evaluate(has('Service notes / measurements')),false);await evaluate("[...document.querySelectorAll('[role=button]')].filter(e=>(e.getAttribute('aria-label')||e.textContent||'').trim().split(String.fromCharCode(10))[0].trim()==='Hem- Skirt').at(-1).click()");await wait(has('Service notes / measurements'));await screenshot('service-notes');await click('Cancel');await click('Dashboard');await click('Tracking');await wait(has('Tailor Tracking & Assignment'));await screenshot('reception-tracking');
  await click('Invoice / WhatsApp');await wait(has('WhatsApp invoice'));await screenshot('invoice-assignment');
  await click('Assign tailor');await wait(has('Assign later / Unassigned'));assert.equal(await evaluate(has('Other Branch Tailor')),false);
  await click('Assign later / Unassigned');await wait(has('Tailor: Unassigned'));
  await click('Assign tailor');await click('QA Tailor');await wait(has('Tailor: QA Tailor'));
  await exportInvoice('Print receipt / Save PDF','invoice-print',500);
  await exportInvoice('WhatsApp PDF / mobile layout','invoice-whatsapp',390);
  await click('WhatsApp invoice');await wait(has('Save WhatsApp PDF'));await screenshot('whatsapp-invoice-dialog');
  await account('tailor');await screenshot('tailor-dashboard');
  await click('Notifications');await wait(has('New tailor assignment'));await screenshot('notification-inbox');await click('Mark all as read');await click('Close');

  const body=await evaluate('document.body.innerText');assert.ok(!body.includes('Total Sales')&&!body.includes('Administration'));
  await click('My Tracking');await wait(has('My Tailor Tracking'));await click('Update progress');await wait(has('Work status'));await click('Save');await wait(has('Tracking updated.'));
  await send('Emulation.setDeviceMetricsOverride',{width:390,height:844,deviceScaleFactor:1,mobile:true});await sleep(500);await screenshot('tailor-tracking-phone');
  assert.deepEqual(errors,[],'Browser runtime exceptions');console.log('Chrome workflow QA passed: role dashboards, branch-only picker, assign later, reassign at printing, tailor progress, customer details, service notes both invoice PDFs, installability, service-worker privacy and the notification inbox. No WhatsApp messages were sent.');
  await send('Browser.close').catch(()=>{});
}finally{ws?.close();if(child.exitCode===null)child.kill();await app.close();}
