import {test} from 'node:test';
import assert from 'node:assert/strict';
import vm from 'node:vm';
import {readFileSync} from 'node:fs';

test('PWA install assets and service worker keep business data online and notification clicks preserve open carts',async()=>{
  const manifest=JSON.parse(readFileSync('frontend/web/manifest.json','utf8'));
  assert.equal(manifest.display,'standalone');assert.equal(manifest.scope,'/pos/');
  for(const size of ['192x192','512x512'])assert.ok(manifest.icons.some(icon=>icon.sizes===size&&icon.type==='image/png'));
  const handlers={},cached=[],shown=[],messages=[];let focused=false,responded=false;
  const context={URL,fetch:async()=>{throw new Error('offline');},caches:{
    open:async()=>({addAll:async paths=>cached.push(...paths)}),keys:async()=>[],delete:async()=>true,match:async()=>({offline:true}),
  },self:{
    location:{origin:'https://pos.example'},addEventListener:(name,fn)=>handlers[name]=fn,skipWaiting:async()=>{},
    registration:{scope:'https://pos.example/pos/',showNotification:async(title,options)=>shown.push({title,options})},
    clients:{claim:async()=>{},matchAll:async()=>[{url:'https://pos.example/pos/',focus:async()=>{focused=true;},postMessage:message=>messages.push(message)}],openWindow:async()=>{throw new Error('Do not replace an existing open cart.');}},
  }};
  vm.runInNewContext(readFileSync('frontend/web/sw.js','utf8'),context);
  let pending;
  handlers.install({waitUntil:p=>pending=p});await pending;
  assert.ok(cached.includes('./offline.html'));assert.ok(cached.every(p=>!p.includes('/api/')&&!p.includes('main.dart.js')));
  handlers.fetch({request:{mode:'same-origin',url:'https://pos.example/api/data'},respondWith:()=>{responded=true;}});assert.equal(responded,false);
  handlers.fetch({request:{mode:'navigate',url:'https://pos.example/pos/'},respondWith:p=>pending=p});assert.equal((await pending).offline,true);
  handlers.push({data:{json:()=>({notificationId:'notice-1',body:'PRIVATE CUSTOMER DETAILS'})},waitUntil:p=>pending=p});await pending;
  assert.equal(shown[0].options.tag,'notice-1');assert.ok(!JSON.stringify(shown).includes('PRIVATE CUSTOMER DETAILS'));
  handlers.notificationclick({notification:{close(){}},waitUntil:p=>pending=p});await pending;
  assert.equal(focused,true);assert.equal(messages[0].type,'open-notifications');
});
