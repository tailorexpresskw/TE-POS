import {test} from 'node:test';
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import path from 'node:path';
import {createApp} from './index.mjs';

test('Admin creates durable branches; Supervisors only oversee their assigned branches',async()=>{
  const directory=path.resolve('outputs','branches-'+randomUUID());
  const app=await createApp({dataDirectory:directory,production:false,push:false});
  await new Promise(resolve=>app.server.listen(0,'127.0.0.1',resolve));
  const base=`http://127.0.0.1:${app.server.address().port}`,password='Test-only-'+randomUUID(),cookies={};
  async function call(route,user='admin',body,status=200){
    const response=await fetch(base+'/api/'+route,{method:body?'POST':'GET',headers:{Cookie:cookies[user]??'',...(body?{'Content-Type':'application/json',Origin:base}:{})},body:body?JSON.stringify(body):undefined});
    const data=await response.json();assert.equal(response.status,status,`${user} ${route}: ${JSON.stringify(data)}`);return data;
  }
  async function login(username){
    const response=await fetch(base+'/api/auth/login',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({username,password})});
    assert.equal(response.status,200);cookies[username]=response.headers.get('set-cookie').split(';')[0];
  }
  const sale=(branch,extra={})=>({id:randomUUID(),branch,kind:'sale',lines:[{id:'1001',qty:1,price:2000}],payments:[],...extra});
  let branchId;
  try{
    await app.auth.createOwner({name:'Admin',username:'admin',password});await login('admin');
    assert.equal((await call('boot')).branches.some(b=>b.id==='aventura'),false);
    await call('orders','admin',sale('aventura'),403);
    await call('branches','admin',{name:'X',code:'NEW'},400);
    await call('branches','admin',{name:'New Branch',code:'bad code'},400);
    const branch=await call('branches','admin',{name:'New Branch',code:'nb'});branchId=branch.id;
    assert.equal(branch.code,'NB');assert.ok((await call('boot')).branches.some(b=>b.id===branchId));
    await call('branches','admin',{name:'new branch',code:'XX'},409);
    await call('branches','admin',{name:'Another Branch',code:'nb'},409);
    for(const [username,role,branches] of [
      ['supervisor','supervisor',['zahra',branchId]],['reception','reception',[branchId]],
      ['manager','manager',['zahra']],['tailor','tailor',[branchId]],
    ]){await call('members','admin',{username,name:username,role,branches,password});await login(username);}
    await call('members','admin',{username:'retired',name:'Retired',role:'supervisor',branches:['aventura'],password},400);
    await call('members','admin',{username:'unknown',name:'Unknown',role:'supervisor',branches:['unknown'],password},400);
    await call('members','admin',{username:'empty',name:'Empty',role:'supervisor',branches:[],password},400);
    for(const user of ['supervisor','manager','reception','tailor']){
      await call('branches',user,{name:'Forbidden',code:'NO'},403);
      await call('members',user,{username:'forged',name:'Forged',role:'admin',branches:[],password},403);
    }
    const boot=await call('boot','supervisor');assert.equal(boot.member.role,'supervisor');
    assert.deepEqual(boot.branches.map(b=>b.id).sort(),[branchId,'zahra'].sort());
    const first=await call('orders','reception',sale(branchId));assert.match(first.bill,/^NB-/);
    await call('orders','admin',sale('zahra'));await call('orders','admin',sale('avenues'));
    const combined=await call('dashboard?branch=all','supervisor');assert.equal(combined.totals.invoices,2);
    assert.deepEqual(combined.branches.map(b=>b.id).sort(),[branchId,'zahra'].sort());
    assert.equal((await call('tracking?branch=all','supervisor')).jobs.length,2);
    assert.equal((await call('dashboard?branch='+branchId,'supervisor')).totals.invoices,1);
    for(const route of ['data?branch=avenues','dashboard?branch=avenues','tracking?branch=avenues','admin'])await call(route,'supervisor',undefined,403);
    await call('orders','supervisor',sale('avenues'),403);
    await call('orders','supervisor',sale('made-up'),403);
    const tailor=boot.staff.find(m=>m.role==='tailor');
    const assigned=await call('orders/'+first.id,'supervisor',{action:'assign',tailorId:tailor.id,version:first.version});
    const done=await call('tracking/'+first.id,'tailor',{action:'progress',status:'In Progress',version:assigned.version});
    await call('tracking/'+first.id,'tailor',{action:'progress',status:'Completed',version:done.version});
    assert.ok((await call('notifications','supervisor')).items.some(n=>n.order_id===first.id&&n.type==='completed'));
    // Revocation takes effect with the existing session, including combined queries and inbox.
    await call('members','admin',{id:boot.member.id,name:'Supervisor',username:'supervisor',role:'supervisor',branches:['zahra']});
    assert.equal((await call('tracking?branch=all','supervisor')).jobs.length,1);
    assert.equal((await call('dashboard?branch=all','supervisor')).totals.invoices,1);
    assert.equal((await call('notifications','supervisor')).items.length,0);
    await call('orders/'+first.id,'supervisor',undefined,403);
  }finally{await app.close();}
  const reopened=await createApp({dataDirectory:directory,production:false,push:false});
  try{assert.equal(reopened.storage.sqlite.prepare('SELECT code FROM branches WHERE id=?').get(branchId).code,'NB');}
  finally{await reopened.close();}
});
