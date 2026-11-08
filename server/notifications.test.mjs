import {test} from 'node:test';
import assert from 'node:assert/strict';
import {randomUUID,randomBytes,createECDH} from 'node:crypto';
import path from 'node:path';
import {createApp} from './index.mjs';

test('notification inbox, branch privacy, durable push retries and device ownership',async()=>{
  const sent=[];let failNext=false,expired=false;
  const app=await createApp({dataDirectory:path.resolve('outputs','notifications-'+randomUUID()),production:false,pushSender:async(subscription,payload)=>{
    if(expired)throw {statusCode:410};if(failNext){failNext=false;throw {statusCode:503};}sent.push({subscription,payload:JSON.parse(payload)});
  }});
  await new Promise(resolve=>app.server.listen(0,'127.0.0.1',resolve));
  const base=`http://127.0.0.1:${app.server.address().port}`,password='Test-only-'+randomUUID(),cookies={},users={};
  async function call(route,user='admin',body,status=200){
    const r=await fetch(base+'/api/'+route,{method:body?'POST':'GET',headers:{...(cookies[user]?{Cookie:cookies[user]}:{}),...(body?{'Content-Type':'application/json',Origin:base}:{})},body:body?JSON.stringify(body):undefined});
    const value=await r.json();assert.equal(r.status,status,`${route}: ${JSON.stringify(value)}`);return value;
  }
  async function login(user){const r=await fetch(base+'/api/auth/login',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({username:user,password})});assert.equal(r.status,200);cookies[user]=r.headers.get('set-cookie').split(';')[0];}
  async function add(user,role,branch){users[user]=(await call('members','admin',{name:user,username:user,role,branches:[branch],password})).id;await login(user);}
  const sub=()=>({endpoint:'https://fcm.googleapis.com/fcm/send/'+randomUUID(),keys:{p256dh:createECDH('prime256v1').generateKeys().toString('base64url'),auth:randomBytes(16).toString('base64url')}});
  const invoice=(extra={})=>({id:randomUUID(),branch:'zahra',kind:'sale',tailorId:users.tailorone,lines:[{id:'1001',qty:1,price:2000,note:'Private garment note'}],payments:[],...extra});
  try{
    await app.auth.createOwner({name:'Admin',username:'admin',password});await login('admin');
    await add('reception','reception','zahra');await add('tailorone','tailor','zahra');await add('tailortwo','tailor','zahra');await add('otherbranch','manager','avenues');
    await call('notifications','anonymous',undefined,401);
    const config=await call('notifications/config','tailorone');assert.equal(config.enabled,true);assert.equal(config.publicKey.length,87);assert.ok(!('privateKey' in config));
    const tailorDevice=sub();await call('notifications/subscriptions','tailorone',{action:'subscribe',subscription:tailorDevice});
    await call('notifications/subscriptions','tailorone',{action:'subscribe',subscription:{...sub(),endpoint:'https://127.0.0.1/private'}},400);
    await call('notifications/subscriptions','tailorone',{action:'subscribe',subscription:{...sub(),endpoint:'https://fcm.googleapis.com.evil.example/push'}},400);
    let sale=await call('orders','reception',invoice());
    let inbox=await call('notifications','tailorone');assert.equal(inbox.unread,1);assert.equal(inbox.items[0].type,'assigned');
    assert.ok(!JSON.stringify(inbox).includes('Private garment note'));assert.ok(!('total' in inbox.items[0]));
    assert.equal((await call('notifications','tailortwo')).unread,0);
    const notification=inbox.items[0];await call('notifications','tailortwo',{action:'read',id:notification.id});assert.equal((await call('notifications','tailorone')).unread,1);
    await app.push.flush();assert.equal(sent.length,1);assert.deepEqual(Object.keys(sent[0].payload).sort(),['body','notificationId','title']);assert.ok(!JSON.stringify(sent[0].payload).includes(sale.bill));
    await app.push.flush();assert.equal(sent.length,1,'Push delivery must not repeat after success.');
    await call('notifications','tailorone',{action:'read',id:notification.id});assert.equal((await call('notifications','tailorone')).unread,0);
    const officeDevice=sub();await call('notifications/subscriptions','reception',{action:'subscribe',subscription:officeDevice});
    let work=await call('tracking/'+sale.id,'tailorone',{action:'progress',status:'In Progress',version:sale.version});
    assert.equal((await call('notifications','reception')).unread,0);
    work=await call('tracking/'+sale.id,'tailorone',{action:'progress',status:'On Hold',note:'Awaiting a fitting',version:work.version});
    assert.equal((await call('notifications','reception')).unread,1);assert.equal((await call('notifications','otherbranch')).unread,0);assert.equal((await call('notifications','admin')).unread,1);
    failNext=true;await app.push.flush();const retry=app.storage.sqlite.prepare("SELECT * FROM push_deliveries WHERE sent_at=''").get();assert.equal(retry.attempts,1);assert.ok(retry.next_attempt);
    app.storage.sqlite.prepare("UPDATE push_deliveries SET next_attempt='' WHERE sent_at=''").run();await app.push.flush();assert.equal(sent.length,2);
    work=await call('tracking/'+sale.id,'tailorone',{action:'progress',status:'In Progress',version:work.version});
    const responses=await Promise.all([1,2].map(()=>fetch(base+'/api/tracking/'+sale.id,{method:'POST',headers:{Cookie:cookies.tailorone,'Content-Type':'application/json',Origin:base},body:JSON.stringify({action:'progress',status:'Completed',version:work.version})})));
    assert.deepEqual(responses.map(r=>r.status).sort(),[200,409]);
    const complete=await call('notifications','reception');assert.equal(complete.items.filter(n=>n.type==='completed').length,1);assert.equal(complete.unread,2);
    expired=true;await app.push.flush();assert.equal(app.storage.sqlite.prepare('SELECT COUNT(*) n FROM push_subscriptions WHERE member_id=?').get(users.reception).n,0);expired=false;
    const later=await call('orders','reception',invoice());
    await call('orders/'+later.id,'reception',{action:'assign',tailorId:users.tailortwo,version:later.version});
    assert.equal((await call('notifications','tailorone')).items.some(n=>n.order_id===later.id),false);
    const before=sent.length;await app.push.flush();assert.equal(sent.length,before,'Reassigned jobs must not notify their former tailor.');
    await call('notifications/subscriptions','tailortwo',{action:'unsubscribe',endpoint:tailorDevice.endpoint});assert.equal(app.storage.sqlite.prepare('SELECT COUNT(*) n FROM push_subscriptions WHERE member_id=?').get(users.tailorone).n,1);
    await call('notifications/subscriptions','tailortwo',{action:'subscribe',subscription:tailorDevice});assert.equal(app.storage.sqlite.prepare('SELECT member_id FROM push_subscriptions').get().member_id,users.tailortwo);
    await call('notifications/subscriptions','tailortwo',{action:'unsubscribe',endpoint:tailorDevice.endpoint});assert.equal(app.storage.sqlite.prepare('SELECT COUNT(*) n FROM push_subscriptions').get().n,0);
    await call('notifications','reception',{action:'read',id:'all'});assert.equal((await call('notifications','reception')).unread,0);assert.ok((await call('notifications','admin')).unread>0);
  }finally{await app.close();}
});
