import {test} from 'node:test';
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import path from 'node:path';
import {createApp} from './index.mjs';

test('standalone accounts, sessions, branch permissions, payments and persistence',async()=>{
  const folder=path.resolve('outputs',`standalone-test-${randomUUID()}`);
  const app=await createApp({dataDirectory:folder,production:false});
  await new Promise(resolve=>app.server.listen(0,'127.0.0.1',resolve));
  const base=`http://127.0.0.1:${app.server.address().port}`;
  const password='Test-only-'+randomUUID();let ownerCookie='',cashierCookie='';
  async function call(route,{cookie='',body,status=200,headers={}}={}){
    const response=await fetch(base+'/api/'+route,{method:body?'POST':'GET',headers:{...headers,...(cookie?{Cookie:cookie}:{}),...(body?{'Content-Type':'application/json',Origin:base}:{})},body:body?JSON.stringify(body):undefined});
    const data=await response.json();assert.equal(response.status,status,`${route}: ${JSON.stringify(data)}`);return {data,response};
  }
  try{
    const status=await call('auth/status');assert.equal(status.data.needsSetup,true);
    await call('boot',{status:401,headers:{'oai-authenticated-user-id':'owner','oai-authenticated-user-email':'owner@pos.test'}});
    await call('auth/setup',{body:{name:'Owner',email:'owner@pos.test',password:'short'},status:403});
    await app.auth.createOwner({name:'Owner',email:'owner@pos.test',password});
    const setup=await call('auth/login',{body:{email:'owner@pos.test',password}});ownerCookie=setup.response.headers.get('set-cookie').split(';')[0];
    assert.match(setup.response.headers.get('set-cookie'),/HttpOnly/);assert.match(setup.response.headers.get('set-cookie'),/SameSite=Strict/);
    const hash=app.storage.sqlite.prepare("SELECT password_hash FROM credentials WHERE member_id='owner'").get().password_hash;
    assert.match(hash,/^scrypt:/);assert.ok(!hash.includes(password));
    await call('auth/setup',{body:{name:'Other',email:'other@pos.test',password},status:403});
    await call('auth/login',{body:{email:'owner@pos.test',password:'wrong'},status:401});
    const boot=await call('boot',{cookie:ownerCookie});assert.equal(boot.data.catalogue.length,446);assert.equal(boot.data.branches.length,10);
    const invited=await call('members',{cookie:ownerCookie,body:{name:'Cashier',email:'cashier@pos.test',role:'cashier',branches:['zahra'],password}});
    const login=await call('auth/login',{body:{email:'cashier@pos.test',password}});cashierCookie=login.response.headers.get('set-cookie').split(';')[0];
    await call('admin',{cookie:cashierCookie,status:403});await call('data?branch=aventura',{cookie:cashierCookie,status:403});
    const id=randomUUID(),draft={id,branch:'zahra',kind:'sale',lines:[{id:'1001',qty:1,price:2000}],payments:[]};
    await call('orders',{cookie:cashierCookie,body:{...draft,id:randomUUID(),discount:500},status:403});
    await call('orders',{cookie:cashierCookie,body:draft});await call('orders',{cookie:cashierCookie,body:draft});
    const paymentId=randomUUID();
    await call('orders/'+id,{cookie:cashierCookie,body:{action:'payment',id:paymentId,version:0,amount:1000,method:'Cash'}});
    await call('orders/'+id,{cookie:cashierCookie,body:{action:'payment',id:paymentId,version:0,amount:1000,method:'Cash'}});
    const concurrent=await Promise.all([0,1].map(()=>fetch(base+'/api/orders/'+id,{method:'POST',headers:{Cookie:cashierCookie,'Content-Type':'application/json',Origin:base},body:JSON.stringify({action:'payment',id:randomUUID(),version:1,amount:1000,method:'K-NET'})})));
    assert.deepEqual(concurrent.map(r=>r.status).sort(),[200,409]);
    const paid=await call('orders/'+id,{cookie:ownerCookie});assert.equal(paid.data.order.paid,2000);assert.equal(paid.data.payments.length,2);
    await call('orders/'+id,{cookie:cashierCookie,body:{action:'refund',version:2,reason:'Test refund',method:'Cash'},status:403});
    await call('orders/'+id,{cookie:ownerCookie,body:{action:'refund',version:2,reason:'Test refund',method:'Cash'}});
    const refunded=await call('orders/'+id,{cookie:ownerCookie});assert.equal(refunded.data.payments.reduce((s,p)=>s+p.amount,0),0);
    const cross=await fetch(base+'/api/auth/login',{method:'POST',headers:{Origin:'https://untrusted.test','Content-Type':'application/json'},body:JSON.stringify({email:'owner@pos.test',password})});assert.equal(cross.status,403);
    const oldCookie=cashierCookie;
    await call('members',{cookie:ownerCookie,body:{id:invited.data.id,name:'Cashier',email:'cashier@pos.test',role:'cashier',branches:['zahra'],password:'Changed-'+password}});
    await call('boot',{cookie:oldCookie,status:401});
    await call('auth/login',{body:{email:'cashier@pos.test',password},status:401});
    const logout=await call('auth/logout',{cookie:ownerCookie,body:{}});assert.match(logout.response.headers.get('set-cookie'),/Max-Age=0/);
    await call('boot',{cookie:ownerCookie,status:401});
    assert.equal((await fetch(base+'/data/pos.sqlite')).status,404);
    assert.equal((await fetch(base+'/')).status,200);
  }finally{await app.close();}
  const reopened=await createApp({dataDirectory:folder,production:false});
  assert.equal(reopened.auth.needsSetup(),false);assert.equal(reopened.storage.sqlite.prepare('SELECT count(*) AS n FROM orders').get().n,1);await reopened.close();
});

test('public production does not expose first-admin registration',async()=>{
  const app=await createApp({dataDirectory:path.resolve('outputs',`production-test-${randomUUID()}`),production:true,publicUrl:'https://pos.example.test'});
  try{
    const request=new Request('https://pos.example.test/api/auth/setup',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({email:'bad@example.test',name:'Bad',password:'long-enough-test-password'})});
    assert.equal((await app.auth.handle(request,'setup',{local:true})).status,403);
  }finally{await app.close();}
});
