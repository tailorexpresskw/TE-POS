import {test} from 'node:test';
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import path from 'node:path';
import {createApp} from './index.mjs';

test('username accounts and branch managers retain Admin-only user creation',async()=>{
  const app=await createApp({dataDirectory:path.resolve('outputs','username-manager-'+randomUUID()),production:false});
  await new Promise(resolve=>app.server.listen(0,'127.0.0.1',resolve));
  const base=`http://127.0.0.1:${app.server.address().port}`,password='Test-only-'+randomUUID();
  const cookies={};
  async function call(route,user,body,status=200){
    const response=await fetch(base+'/api/'+route,{method:body?'POST':'GET',headers:{...(cookies[user]?{Cookie:cookies[user]}:{}),...(body?{'Content-Type':'application/json',Origin:base}:{})},body:body?JSON.stringify(body):undefined});
    const result=await response.json();assert.equal(response.status,status,`${route}: ${JSON.stringify(result)}`);return result;
  }
  async function login(user,username){
    const response=await fetch(base+'/api/auth/login',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({username,password})});
    assert.equal(response.status,200);cookies[user]=response.headers.get('set-cookie').split(';')[0];
  }
  try{
    await app.auth.createOwner({name:'Admin',username:'Admin',password});await login('admin',' ADMIN ');
    const manager=await call('members','admin',{name:'Branch Manager',username:'Zahra.Manager',password,role:'manager',branches:['zahra']});
    await login('manager','ZAHRA.MANAGER');
    const boot=await call('boot','manager');assert.equal(boot.member.role,'manager');assert.deepEqual(boot.branches.map(b=>b.id),['zahra']);
    assert.equal(boot.member.username,'zahra.manager');
    await call('members','manager',{name:'Bad',username:'bad',password,role:'admin',branches:[]},403);
    await call('admin','manager',undefined,403);
    await call('auth/setup','manager',{name:'Bad',username:'bad',password},403);
    await call('members','admin',{name:'Duplicate',username:'ZAHRA.MANAGER',password,role:'reception',branches:['zahra']},409);
    await call('members','admin',{name:'Invalid',username:'bad user',password,role:'reception',branches:['zahra']},400);
    await call('members','admin',{id:randomUUID(),name:'Missing',username:'missing',role:'manager',branches:['zahra']},404);
    const invoice={id:randomUUID(),branch:'zahra',kind:'sale',lines:[{id:'1001',qty:1,price:2500}],discount:100,payments:[]};
    const sale=await call('orders','manager',invoice);assert.equal(sale.total,2400);
    await call('orders','manager',{...invoice,id:randomUUID(),branch:'avenues'},403);
    await call('data?branch=avenues','manager',undefined,403);
    await call('tracking?branch=all','manager',undefined,403);
    await call('dashboard?branch=all','manager',undefined,403);
    assert.equal((await call('dashboard?branch=zahra','manager')).totals.total,2400);
    const tailor=await call('members','admin',{name:'Tailor',username:'tailor.one',password,role:'tailor',branches:['zahra']});
    const assigned=await call('orders/'+sale.id,'manager',{action:'assign',tailorId:tailor.id,version:sale.version});
    const progress=await call('tracking/'+sale.id,'manager',{action:'progress',status:'Completed',note:'Manager verified completed work',version:assigned.version});assert.equal(progress.job_status,'Completed');
    await call('members','admin',{id:manager.id,name:'Branch Manager',username:'manager.new',role:'manager',branches:['zahra']});
    await call('auth/login','anonymous',{username:'zahra.manager',password},401);await login('manager','manager.new');
    await call('members','admin',{id:manager.id,name:'Branch Manager',username:'',role:'manager',branches:['zahra']},400);
    const admin=await call('admin','admin');assert.ok(admin.members.some(m=>m.id===manager.id&&m.username==='manager.new'));
    assert.ok(!JSON.stringify(admin).includes(password));
  }finally{await app.close();}
});

test('Admin-only accounts, branch invoices, tailor assignment and private tracking',async()=>{
  const app=await createApp({dataDirectory:path.resolve('outputs','workflow-'+randomUUID()),production:false});
  await new Promise(resolve=>app.server.listen(0,'127.0.0.1',resolve));
  const base=`http://127.0.0.1:${app.server.address().port}`,password='Test-only-'+randomUUID();
  const cookies=new Map(),users=new Map();
  async function call(route,user='admin',body,status=200){
    const response=await fetch(base+'/api/'+route,{method:body?'POST':'GET',headers:{...(cookies.has(user)?{Cookie:cookies.get(user)}:{}),...(body?{'Content-Type':'application/json',Origin:base}:{})},body:body?JSON.stringify(body):undefined});
    const result=await response.json();assert.equal(response.status,status,`${route}: ${JSON.stringify(result)}`);return result;
  }
  async function login(name,email){const response=await fetch(base+'/api/auth/login',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({email,password})});assert.equal(response.status,200);cookies.set(name,response.headers.get('set-cookie').split(';')[0]);}
  async function add(name,role,branch){const u=await call('members','admin',{name,email:name+'@workflow.test',role,branches:[branch],password});users.set(name,u.id);await login(name,name+'@workflow.test');}
  const newInvoice=(extra={})=>({id:randomUUID(),branch:'zahra',kind:'sale',lines:[{id:'1001',qty:1,price:2000,note:'Hem to 90 cm'}],payments:[],...extra});
  try{
    await call('auth/setup','anonymous',{name:'Bad',email:'bad@workflow.test',password},403);
    assert.equal(app.auth.needsSetup(),true);
    await app.auth.createOwner({name:'Admin',email:'admin@workflow.test',password});await login('admin','admin@workflow.test');
    await add('reception','reception','zahra');await add('otherReception','reception','avenues');
    await add('tailorA','tailor','zahra');await add('tailorB','tailor','zahra');await add('otherTailor','tailor','avenues');
    for(const user of ['reception','tailorA']){
      await call('members',user,{name:'Escalation',email:'escalation@workflow.test',role:'admin',branches:[],password},403);
      await call('auth/setup',user,{name:'Escalation',email:'escalation@workflow.test',password},403);
    }
    const receptionBoot=await call('boot','reception');assert.deepEqual(receptionBoot.branches.map(b=>b.id),['zahra']);
    assert.ok(!receptionBoot.staff.some(s=>s.id===users.get('otherTailor')));
    await call('orders','reception',newInvoice({lines:[{id:'1001',qty:1,price:1}]}),403);
    await call('orders','reception',newInvoice({discount:100}),403);
    await call('orders','reception',newInvoice({branch:'avenues'}),403);
    for(const tailorId of [users.get('otherTailor'),users.get('reception'),'owner'])await call('orders','reception',newInvoice({tailorId}),400);
    let invoice=await call('orders','reception',newInvoice());assert.equal(invoice.tailor_id,null);
    assert.equal((await call('tracking?branch=zahra','tailorA')).jobs.length,0);
    assert.equal((await call('tracking?branch=zahra','reception')).summary.unassigned,1);
    await call('orders/'+invoice.id,'otherReception',{action:'assign',tailorId:users.get('otherTailor'),version:invoice.version},403);
    await call('orders/'+invoice.id,'reception',{action:'assign',tailorId:users.get('otherTailor'),version:invoice.version},400);
    invoice=await call('orders/'+invoice.id,'reception',{action:'assign',tailorId:users.get('tailorA'),version:invoice.version});
    assert.equal(invoice.tailor_id,users.get('tailorA'));assert.ok(invoice.assigned_at);
    const assigned=await call('tracking?branch=zahra','tailorA');assert.equal(assigned.jobs.length,1);
    for(const field of ['total','paid','subtotal','phone','address','cashier'])assert.ok(!(field in assigned.jobs[0]),field);
    assert.ok(!('price' in assigned.jobs[0].lines[0]));assert.equal(assigned.jobs[0].lines[0].note,'Hem to 90 cm');
    const tailorBoot=await call('boot','tailorA');assert.equal(tailorBoot.catalogue.length,0);assert.equal(tailorBoot.methods.length,0);
    for(const route of ['data?branch=zahra','dashboard?branch=zahra','orders/'+invoice.id,'customers?q=any','admin'])await call(route,'tailorA',undefined,403);
    await call('tracking?branch=all','reception',undefined,403);await call('tracking?branch=avenues','tailorA',undefined,403);
    await call('tracking/'+invoice.id,'tailorB',undefined,403);
    await call('tracking/'+invoice.id,'reception',{action:'progress',version:invoice.version,status:'In Progress'},403);
    await call('tracking/'+invoice.id,'tailorA',{action:'progress',version:invoice.version,status:'Completed'},400);
    let work=await call('tracking/'+invoice.id,'tailorA',{action:'progress',version:invoice.version,status:'In Progress',note:'Work started'});assert.equal(work.job_status,'In Progress');
    await call('orders/'+invoice.id,'reception',{action:'assign',tailorId:users.get('tailorB'),version:work.version},400);
    invoice=await call('orders/'+invoice.id,'reception',{action:'assign',tailorId:users.get('tailorB'),version:work.version,reason:'Shift handover'});assert.equal(invoice.job_status,'Pending');
    await call('tracking/'+invoice.id,'tailorA',{action:'progress',version:work.version,status:'Completed'},403);
    await call('tracking/'+invoice.id,'tailorA',undefined,403);
    work=await call('tracking/'+invoice.id,'tailorB',{action:'progress',version:invoice.version,status:'In Progress'});
    const attempts=await Promise.all([0,1].map(()=>fetch(base+'/api/tracking/'+invoice.id,{method:'POST',headers:{Cookie:cookies.get('tailorB'),'Content-Type':'application/json',Origin:base},body:JSON.stringify({action:'progress',version:work.version,status:'Completed',note:'Finished'})})));
    assert.deepEqual(attempts.map(r=>r.status).sort(),[200,409]);
    const completed=await call('tracking/'+invoice.id,'tailorB');assert.equal(completed.job.job_status,'Completed');assert.equal(completed.events.filter(e=>JSON.parse(e.detail).note==='Finished').length,1);assert.ok(completed.events.some(e=>JSON.parse(e.detail).note==='Shift handover'));
    const duringPrint=await call('orders','reception',newInvoice({tailorId:users.get('tailorA')}));assert.equal(duringPrint.tailor_id,users.get('tailorA'));
    const other=await call('orders','otherReception',newInvoice({branch:'avenues',tailorId:users.get('otherTailor')}));
    await call('orders/'+other.id,'reception',undefined,403);await call('orders/'+other.id,'reception',{action:'assign',tailorId:users.get('tailorA'),version:0},403);
    const branch=await call('data?branch=zahra','reception');assert.ok(branch.orders.every(o=>o.branch==='zahra'));
    const global=await call('dashboard?branch=all','admin');assert.equal(global.totals.invoices,3);assert.equal(global.branches.length,9);
    const branchDash=await call('dashboard?branch=zahra','reception');assert.equal(branchDash.totals.invoices,2);assert.equal(branchDash.branches.length,1);
    const file=await fetch(base+'/api/documents?branch=zahra',{method:'POST',headers:{Cookie:cookies.get('reception'),'Content-Type':'application/pdf',Origin:base},body:'%PDF-1.4 test'});assert.equal(file.status,200);const doc=await file.json();
    const withDoc=await call('orders','reception',newInvoice({tailorId:users.get('tailorA'),attachments:[doc.id]}));
    assert.equal((await fetch(base+'/api/documents/'+doc.id,{headers:{Cookie:cookies.get('tailorA')}})).status,200);
    assert.equal((await fetch(base+'/api/documents/'+doc.id,{headers:{Cookie:cookies.get('tailorB')}})).status,403);
    assert.equal((await fetch(base+'/api/documents?branch=zahra',{method:'POST',headers:{Cookie:cookies.get('tailorA'),'Content-Type':'application/pdf',Origin:base},body:'%PDF'})).status,403);
    assert.equal((await call('tracking/'+withDoc.id,'tailorA')).attachments.length,1);
    const customer=await call('customers','reception',{name:'Customer One',phone:'+965 5555-1234',address:'Test address',branch:'zahra'});
    assert.ok((await call('customers?q=55551234','reception')).some(c=>c.id===customer.id));
    assert.ok((await call('customers?q=Customer%20One','reception')).some(c=>c.id===customer.id));
    const customerSale=await call('orders','reception',newInvoice({customerId:customer.id,tailorId:users.get('tailorA'),lines:[{id:'1001',qty:1,price:2000,note:'First garment: 90 cm'},{id:'1001',qty:1,price:2000,note:'Second garment: 95 cm'}]}));
    await call('orders','otherReception',newInvoice({branch:'avenues',customerId:customer.id}));
    const profile=await call('customers/'+customer.id+'?branch=zahra','reception');
    assert.equal(profile.customer.address,'Test address');assert.equal(profile.history.length,1);assert.equal(profile.summary.total,4000);assert.equal(profile.summary.due,4000);
    assert.ok(profile.history.every(o=>o.branch==='zahra'));
    await call('customers/'+customer.id+'?branch=avenues','reception',undefined,403);
    await call('customers/'+customer.id+'?branch=zahra','tailorA',undefined,403);
    await call('customers/'+customer.id,'tailorA',{name:'Bad',phone:'55551234'},403);
    await call('customers/'+customer.id,'reception',{name:'Customer Updated',phone:'55551234',address:'New address',branch:'zahra'});
    assert.equal((await call('customers/'+customer.id+'?branch=zahra','reception')).customer.name,'Customer Updated');
    assert.equal((await call('orders/'+customerSale.id,'reception')).order.customer_name,'Customer One');
    const job=(await call('tracking/'+customerSale.id,'tailorA')).job;
    assert.deepEqual(job.lines.map(l=>l.note),['First garment: 90 cm','Second garment: 95 cm']);
  }finally{await app.close();}
});
