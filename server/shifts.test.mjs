import {test} from 'node:test';
import assert from 'node:assert/strict';
import {randomUUID,randomBytes,createECDH} from 'node:crypto';
import path from 'node:path';
import {createApp} from './index.mjs';

async function fixture({realtime=false,pushSender}={}){
  let stamp=Date.parse('2026-11-16T05:59:00Z');
  const app=await createApp({dataDirectory:path.resolve('outputs','shifts-'+randomUUID()),production:false,push:!!pushSender,pushSender,...(!realtime?{clock:()=>stamp}:{})});
  await new Promise(resolve=>app.server.listen(0,'127.0.0.1',resolve));
  const base=`http://127.0.0.1:${app.server.address().port}`,password='Test-only-'+randomUUID(),cookies={},ids={};
  async function call(route,user='admin',body,status=200){const response=await fetch(base+'/api/'+route,{method:body?'POST':'GET',headers:{...(cookies[user]?{Cookie:cookies[user]}:{}),...(body?{'Content-Type':'application/json',Origin:base}:{})},body:body?JSON.stringify(body):undefined});const data=await response.json();assert.equal(response.status,status,`${user} ${route}: ${JSON.stringify(data)}`);return data;}
  async function login(user,status=200,pass=password){const response=await fetch(base+'/api/auth/login',{method:'POST',headers:{'Content-Type':'application/json',Origin:base},body:JSON.stringify({username:user,password:pass})});const data=await response.json();assert.equal(response.status,status,`${user} login: ${JSON.stringify(data)}`);if(status===200)cookies[user]=response.headers.get('set-cookie').split(';')[0];return data;}
  await app.auth.createOwner({name:'Admin',username:'admin',password});await login('admin');
  for(const [user,role]of [['reception','reception'],['tailor','tailor'],['manager','manager'],['supervisor','supervisor']]){ids[user]=(await call('members','admin',{name:user,username:user,role,branches:['zahra','avenues'],password})).id;await login(user);}
  const setTime=value=>stamp=Date.parse(value);
  const policy=(extra={})=>({enabled:true,weekly:[{day:1,start:'09:00',end:'10:00',branch:'zahra'}],exceptions:[],revision:0,...extra});
  return {app,base,password,cookies,ids,call,login,setTime,policy};
}

test('all non-Admin roles are checked at login and on existing sessions; alerts stay Admin-only',async()=>{
  const f=await fixture(),{app,ids,call,login,setTime,policy,cookies}=f;
  try{
    await login('reception',401,'incorrect-password');assert.equal(app.storage.sqlite.prepare('SELECT COUNT(*) n FROM security_alerts').get().n,0);
    for(const user of Object.keys(ids)){
      const saved=await call('shifts/'+ids[user],'admin',policy());assert.equal(saved.policy.revision,1);
      assert.equal((await login(user,403)).code,'SHIFT_BLOCKED');
    }
    assert.equal((await call('notifications')).unread,4);
    assert.equal((await call('shifts/alerts?from=2026-11-16&to=2026-11-16')).summary.attempts,4);
    setTime('2026-11-16T06:00:00Z');
    for(const user of Object.keys(ids)){await login(user);const boot=await call('boot',user);assert.deepEqual(boot.branches.map(b=>b.id),['zahra']);assert.equal(boot.member.shift_access.enabled,true);}
    assert.equal((await call('notifications','manager')).unread,0);assert.equal((await call('notifications','supervisor')).unread,0);
    await call('shifts/alerts','supervisor',undefined,403);
    await call('shifts/'+ids.reception,'manager',policy({revision:1}),403);
    await call('shifts/owner','admin',policy(),400);
    const deniedBranch=await call('data?branch=avenues','supervisor',undefined,403);assert.equal(deniedBranch.code,'SHIFT_BLOCKED');
    await call('boot','supervisor',undefined,401);await login('supervisor');
    const file=await fetch(f.base+'/api/documents?branch=zahra',{method:'POST',headers:{Cookie:cookies.reception,'Content-Type':'application/pdf',Origin:f.base},body:'%PDF shift-test'});assert.equal(file.status,200);const document=await file.json();
    setTime('2026-11-16T07:00:00Z');
    assert.equal((await call('documents/'+document.id,'reception',undefined,403)).code,'SHIFT_BLOCKED');
    await call('data?branch=zahra','reception',undefined,401);
    const before=app.storage.sqlite.prepare('SELECT COUNT(*) n FROM orders').get().n;
    const denied=await call('orders','manager',{id:randomUUID(),branch:'zahra',kind:'sale',lines:[{id:'1001',qty:1,price:2000}],payments:[]},403);
    assert.equal(denied.code,'SHIFT_BLOCKED');assert.equal(app.storage.sqlite.prepare('SELECT COUNT(*) n FROM orders').get().n,before);
    await login('admin');assert.equal((await call('boot')).member.role,'admin');
    const alert=await call('shifts/alerts?from=2026-11-16&to=2026-11-16');assert.ok(alert.items.some(a=>a.source==='branch'));assert.ok(alert.items.some(a=>a.source==='request'));
    assert.ok(!JSON.stringify(alert).includes(f.password));assert.ok(!JSON.stringify(alert).includes('scrypt:'));
  }finally{await app.close();}
});

test('live schedule changes, days off, authorized exceptions, quiet shift-end checks and grouped alerts',async()=>{
  const {app,ids,call,login,setTime,policy}=await fixture();
  try{
    await call('shifts/'+ids.reception,'admin',policy());
    setTime('2026-11-16T06:00:00Z');await login('reception');
    await call('shifts/'+ids.reception,'admin',policy({revision:1,exceptions:[{date:'2026-11-16',off:true,periods:[]}]}));
    assert.equal((await call('boot','reception',undefined,403)).code,'SHIFT_BLOCKED');
    const one=(await call('notifications')).items.find(item=>item.type==='off_shift');assert.ok(one);
    await call('notifications','manager',{action:'read',id:one.id},403);
    await call('notifications','admin',{action:'read',id:one.id});assert.equal((await call('notifications')).unread,0);
    await login('reception',403);await login('reception',403);
    const grouped=await call('shifts/alerts?from=2026-11-16&to=2026-11-16');assert.equal(grouped.summary.events,2);assert.equal(grouped.summary.attempts,3);
    await call('shifts/alerts','admin',{action:'read',id:'all'});assert.equal((await call('notifications')).unread,0);
    await call('shifts/'+ids.reception,'admin',policy({revision:2,exceptions:[{date:'2026-11-16',off:false,periods:[{start:'09:00',end:'11:00',branch:'avenues'}]}]}));
    await login('reception');assert.deepEqual((await call('boot','reception')).branches.map(b=>b.id),['avenues']);
    await call('shifts/'+ids.reception,'admin',policy({revision:2}),409);
    const before=app.storage.sqlite.prepare('SELECT SUM(attempts) n FROM security_alerts').get().n;
    setTime('2026-11-16T08:00:00Z');
    assert.equal((await call('auth/status','reception',undefined,403)).code,'SHIFT_BLOCKED');
    assert.equal(app.storage.sqlite.prepare('SELECT SUM(attempts) n FROM security_alerts').get().n,before,'Normal shift-end heartbeat does not create an alarm.');
    await call('boot','reception',undefined,401);await login('reception',403);
    assert.equal(app.storage.sqlite.prepare('SELECT SUM(attempts) n FROM security_alerts').get().n,before+1);
    await call('shifts/'+ids.reception,'admin',policy({enabled:false,revision:3}));await login('reception');assert.equal((await call('boot','reception')).branches.length,2);
  }finally{await app.close();}
});

test('blocked-access push goes only to active Admin devices, retries durably and cleans up device rebinds',async()=>{
  const sent=[];let fail=true;
  const {app,ids,call,login,policy}=await fixture({realtime:true,pushSender:async(subscription,payload)=>{if(fail){fail=false;throw {statusCode:503};}sent.push({subscription,payload:JSON.parse(payload)});}});
  const sub=()=>({endpoint:'https://fcm.googleapis.com/fcm/send/'+randomUUID(),keys:{p256dh:createECDH('prime256v1').generateKeys().toString('base64url'),auth:randomBytes(16).toString('base64url')}});
  try{
    const adminDevice=sub(),supervisorDevice=sub();
    await call('notifications/subscriptions','admin',{action:'subscribe',subscription:adminDevice});await call('notifications/subscriptions','supervisor',{action:'subscribe',subscription:supervisorDevice});
    await call('shifts/'+ids.reception,'admin',policy({weekly:[]}));await login('reception',403);
    await app.push.flush();assert.equal(app.storage.sqlite.prepare("SELECT attempts FROM security_push_deliveries WHERE sent_at=''").get().attempts,1);
    app.storage.sqlite.prepare("UPDATE security_push_deliveries SET next_attempt=''").run();await app.push.flush();assert.equal(sent.length,1);
    assert.equal(sent[0].subscription.endpoint,adminDevice.endpoint);assert.ok(sent[0].payload.notificationId.startsWith('security:'));assert.ok(!JSON.stringify(sent[0].payload).includes('reception'));
    await app.push.flush();assert.equal(sent.length,1);
    assert.equal((await call('notifications','supervisor')).items.some(item=>item.type==='off_shift'),false);
    await call('notifications/subscriptions','supervisor',{action:'unsubscribe',endpoint:adminDevice.endpoint});assert.equal(app.storage.sqlite.prepare('SELECT COUNT(*) n FROM security_push_deliveries').get().n,1);
    await call('notifications/subscriptions','supervisor',{action:'subscribe',subscription:adminDevice});assert.equal(app.storage.sqlite.prepare('SELECT COUNT(*) n FROM security_push_deliveries').get().n,0);
    await call('notifications/subscriptions','supervisor',{action:'unsubscribe',endpoint:adminDevice.endpoint});
    await call('notifications','admin',{action:'read',id:'all'});assert.equal((await call('notifications')).unread,0);
  }finally{await app.close();}
});
