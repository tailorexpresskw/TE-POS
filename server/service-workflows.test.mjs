import {test} from 'node:test';
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import path from 'node:path';
import {createApp} from './index.mjs';

async function fixture(){
  const app=await createApp({dataDirectory:path.resolve('outputs','services-'+randomUUID()),production:false,push:false});
  await new Promise(resolve=>app.server.listen(0,'127.0.0.1',resolve));
  const base=`http://127.0.0.1:${app.server.address().port}`,password='Test-only-'+randomUUID(),cookies={},members={};
  async function call(route,user='admin',body,status=200){
    const response=await fetch(base+'/api/'+route,{method:body?'POST':'GET',headers:{Cookie:cookies[user]??'',...(body?{'Content-Type':'application/json',Origin:base}:{})},body:body?JSON.stringify(body):undefined});
    const data=await response.json();assert.equal(response.status,status,`${user} ${route}: ${JSON.stringify(data)}`);return data;
  }
  async function login(username){const response=await fetch(base+'/api/auth/login',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({username,password})});assert.equal(response.status,200);cookies[username]=response.headers.get('set-cookie').split(';')[0];}
  await app.auth.createOwner({name:'Admin',username:'admin',password});await login('admin');
  for(const [name,role,branch]of [['reception','reception','zahra'],['tailora','tailor','zahra'],['tailorb','tailor','zahra'],['manager','manager','zahra'],['supervisor','supervisor','zahra'],['other','reception','avenues']]){
    members[name]=(await call('members','admin',{name,username:name,role,branches:[branch],password})).id;await login(name);
  }
  const invoice=(extra={})=>({id:randomUUID(),branch:'zahra',kind:'sale',lines:[{id:'1001',qty:2,price:2000,note:'Two skirts'},{id:'1001',qty:1,price:2000,note:'Third skirt'}],payments:[],...extra});
  async function detail(id,user='admin'){return call('tracking/'+id,user);}
  async function action(id,user,body,status=200){const current=await detail(id,user);return call('tracking/'+id,user,{version:current.job.version,...body},status);}
  async function finish(id,user,taskId){await action(id,user,{action:'progress',taskIds:[taskId],status:'In Progress'});await action(id,user,{action:'progress',taskIds:[taskId],status:'Awaiting Review'});return action(id,'reception',{action:'review',taskIds:[taskId],approved:true});}
  return {app,base,cookies,members,call,invoice,detail,action,finish};
}

test('split services, reception quality checks and fault/no-fault backjob credits',async()=>{
  const f=await fixture(),{app,call,members,invoice,detail,action,finish}=f;
  try{
    const sale=await call('orders','admin',invoice({tailorId:members.tailora}));
    const original=(await detail(sale.id)).job.tasks;assert.equal(original.length,2);
    await call('orders/'+sale.id,'reception',{action:'assign',version:sale.version,taskIds:[original[1].id],tailorId:members.tailorb});
    const a=await detail(sale.id,'tailora'),b=await detail(sale.id,'tailorb');
    assert.equal(a.job.tasks.length,1);assert.equal(a.job.lines.length,1);assert.equal(b.job.lines.length,1);
    assert.ok(!('price' in a.job.tasks[0])&&!('price' in a.job.lines[0])&&!('phone' in a.job));
    await action(sale.id,'tailora',{action:'progress',taskIds:[original[1].id],status:'In Progress'},403);
    await action(sale.id,'tailora',{action:'progress',taskIds:[original[0].id],status:'Completed'},403);
    await action(sale.id,'tailora',{action:'progress',taskIds:[original[0].id],status:'In Progress'});
    const submitted=await action(sale.id,'tailora',{action:'progress',taskIds:[original[0].id],status:'Awaiting Review'});
    assert.equal(submitted.job_status,'Awaiting Review');
    await action(sale.id,'supervisor',{action:'review',taskIds:[original[0].id],approved:true},403);
    const current=await detail(sale.id);await call('orders/'+sale.id,'reception',{action:'status',status:'Prepared',version:current.job.version},400);
    assert.ok((await call('notifications','reception')).items.some(n=>n.type==='review'));
    await action(sale.id,'reception',{action:'review',taskIds:[original[0].id],approved:false,note:'Please correct the hem'});
    await action(sale.id,'tailora',{action:'progress',taskIds:[original[0].id],status:'Awaiting Review'});
    const approve=await detail(sale.id);
    const results=await Promise.all([0,1].map(()=>fetch(f.base+'/api/tracking/'+sale.id,{method:'POST',headers:{Cookie:f.cookies.reception,'Content-Type':'application/json',Origin:f.base},body:JSON.stringify({action:'review',taskIds:[original[0].id],approved:true,version:approve.job.version})})));
    assert.deepEqual(results.map(r=>r.status).sort(),[200,409]);
    await finish(sale.id,'tailorb',original[1].id);assert.equal((await detail(sale.id)).job.job_status,'Completed');
    const ready=await detail(sale.id);await call('orders/'+sale.id,'admin',{action:'status',status:'Prepared',version:ready.job.version});
    let credits=app.storage.sqlite.prepare('SELECT tailor_id,SUM(amount) amount FROM work_credits GROUP BY tailor_id').all();
    assert.equal(credits.find(c=>c.tailor_id===members.tailora).amount,4000);
    let back=await action(sale.id,'reception',{action:'backjob',parentTaskId:original[0].id,quantity:1,tailorId:members.tailorb,fault:'tailor',note:'Previous hem was uneven'});
    const back1=back.tasks.find(t=>t.kind==='backjob');assert.equal(back.job_status,'Pending');
    assert.equal((await call('orders/'+sale.id)).order.status,'Ongoing');
    await finish(sale.id,'tailorb',back1.id);
    credits=app.storage.sqlite.prepare('SELECT tailor_id,SUM(amount) amount FROM work_credits GROUP BY tailor_id').all();
    assert.equal(credits.find(c=>c.tailor_id===members.tailora).amount,2000);assert.equal(credits.find(c=>c.tailor_id===members.tailorb).amount,4000);
    back=await action(sale.id,'reception',{action:'backjob',parentTaskId:back1.id,quantity:1,tailorId:members.tailora,fault:'no_fault',note:'Customer requested another fit while the previous tailor was away'});
    const back2=back.tasks.find(t=>t.parent_task_id===back1.id);await finish(sale.id,'tailora',back2.id);
    const dashboard=await call('dashboard?branch=all');assert.equal(dashboard.totals.total,6000);
    assert.equal(dashboard.tailorPerformance.find(c=>c.id===members.tailora).amount,4000);assert.equal(dashboard.tailorPerformance.find(c=>c.id===members.tailorb).amount,4000);
    assert.ok((await call('notifications','manager')).items.some(n=>n.type==='backjob'));
    await call('tracking/'+sale.id,'other',undefined,403);
    const customer=await call('orders/'+sale.id+'/customer-status','reception');assert.ok(!JSON.stringify(customer).includes('uneven'));assert.ok(!JSON.stringify(customer).includes(members.tailora));
    assert.ok(app.storage.sqlite.prepare('SELECT COUNT(*) n FROM integration_events').get().n>0);
  }finally{await app.close();}
});

test('Admin grants, item quantities, immutable linked documents, refund races and paid cancellations',async()=>{
  const {app,call,members,invoice}=await fixture();
  try{
    const sale=await call('orders','admin',invoice({discount:333,payments:[{amount:5667,method:'Cash'}]}));
    const refund={action:'refund',id:randomUUID(),version:sale.version,lines:[{index:0,qty:1}],reason:'Customer returned one skirt',method:'Cash'};
    await call('orders/'+sale.id,'reception',refund,403);
    await call('members','admin',{id:members.reception,name:'Reception',username:'reception',role:'reception',branches:['zahra'],permissions:{refund:true,cancel:true}});
    const first=await call('orders/'+sale.id,'reception',refund);assert.equal(first.total,5667);assert.equal(first.refunded_total,1889);assert.equal(first.paid,3778);assert.equal(first.due,0);
    assert.equal(first.adjustment.document_type,'refund');assert.equal(first.adjustment.parent_order_id,sale.id);
    assert.equal((await call('orders/'+sale.id,'reception',refund)).adjustment.id,first.adjustment.id);
    await call('orders/'+sale.id,'reception',{...refund,id:randomUUID(),version:first.version,lines:[{index:0,qty:2}]},400);
    const charge=await call('orders/'+sale.id,'reception',{action:'charge',id:randomUUID(),version:first.version,name:'Delivery fee',amount:1500,paid:0});
    assert.equal(charge.total,5667);assert.equal(charge.adjustment.total,1500);assert.equal(charge.adjustment.document_type,'charge');
    const detail=await call('orders/'+sale.id);assert.equal(detail.related.length,2);assert.equal(detail.refundOptions[0].remaining_qty,1);
    assert.equal((await call('exceptions?branch=all&type=refund','supervisor')).items.length,1);
    await call('exceptions?branch=zahra&type=refund','other',undefined,403);
    await call('exceptions?branch=zahra&type=refund','tailora',undefined,403);
    assert.equal((await call('orders/'+first.adjustment.id)).order.due,0);
    await call('orders/'+sale.id,'reception',{action:'cancel',id:randomUUID(),version:charge.version,reason:'Customer request',method:'Cash'},400);
    const cancelled=await call('orders/'+sale.id,'reception',{action:'cancel',id:randomUUID(),version:charge.version,reasonCode:'Customer request',reason:'Customer cancelled remaining services',method:'Cash'});
    assert.equal(cancelled.status,'Voided');assert.equal(cancelled.total,5667);assert.equal(cancelled.refunded_total,5667);assert.equal(cancelled.paid,0);
    assert.equal(cancelled.adjustment.document_type,'cancellation');assert.equal(cancelled.adjustment.total,3778);
    assert.equal(app.storage.sqlite.prepare('SELECT SUM(amount) n FROM payments WHERE order_id=?').get(sale.id).n,0);
    assert.ok((await call('notifications','supervisor')).items.some(n=>n.type==='cancellation'));
    assert.ok((await call('notifications','manager')).items.some(n=>n.type==='refund'));
    assert.equal((await call('orders/'+charge.adjustment.id)).order.due,1500);
    await call('members','admin',{id:members.reception,name:'Reception',username:'reception',role:'reception',branches:['zahra'],permissions:{refund:false,cancel:false}});
    await call('orders/'+charge.adjustment.id,'reception',{action:'refund',id:randomUUID(),version:0,full:true,reason:'Delivery cancelled',method:'Cash'},403);
    await call('orders/'+charge.adjustment.id,'other',undefined,403);
  }finally{await app.close();}
});

test('concurrent partial refunds preserve discount rounding and never return more than was paid',async()=>{
  const f=await fixture(),{app,call,invoice}=f;
  try{
    const sale=await call('orders','admin',invoice({lines:[{id:'1001',qty:3,price:2000}],discount:1000,payments:[{amount:5000,method:'Cash'}]}));
    const refund=(version)=>({id:randomUUID(),action:'refund',version,lines:[{index:0,qty:1}],reason:'Return one garment',method:'Cash'});
    await call('orders/'+sale.id,'admin',{...refund(sale.version),cashRefund:0},400);
    const first=await call('orders/'+sale.id,'admin',refund(sale.version));assert.equal(first.adjustment.total,1666);
    const attempts=await Promise.all([0,1].map(()=>fetch(f.base+'/api/orders/'+sale.id,{method:'POST',headers:{Cookie:f.cookies.admin,'Content-Type':'application/json',Origin:f.base},body:JSON.stringify(refund(first.version))})));
    assert.deepEqual(attempts.map(r=>r.status).sort(),[200,409]);
    const current=(await call('orders/'+sale.id)).order;
    const final=await call('orders/'+sale.id,'admin',{id:randomUUID(),action:'refund',version:current.version,full:true,reason:'Return final garment',method:'Cash'});
    assert.equal(final.adjustment.total,1667);assert.equal(final.refunded_total,5000);assert.equal(final.paid,0);assert.equal(final.due,0);
    assert.equal(app.storage.sqlite.prepare("SELECT SUM(total) n FROM orders WHERE parent_order_id=? AND document_type='refund'").get(sale.id).n,5000);
    assert.equal(app.storage.sqlite.prepare('SELECT SUM(amount) n FROM payments WHERE order_id=?').get(sale.id).n,0);
    await call('orders/'+sale.id,'admin',refund(final.version),400);
    const withExtra=await call('orders','admin',invoice({lines:[{id:'1001',qty:1,price:2000}],extra:1000,payments:[{amount:3000,method:'Cash'}]}));
    const serviceRefund=await call('orders/'+withExtra.id,'admin',{id:randomUUID(),action:'refund',version:withExtra.version,lines:[{index:0,qty:1}],reason:'Return garment',method:'Cash'});
    assert.equal(serviceRefund.net_total,1000);assert.equal((await call('tracking?branch=zahra')).jobs.some(j=>j.id===withExtra.id),false);
    const remaining=await call('orders/'+withExtra.id,'admin',{id:randomUUID(),action:'refund',version:serviceRefund.version,full:true,reason:'Return remaining extra charge',method:'Cash'});
    assert.equal(remaining.adjustment.total,1000);assert.equal(remaining.refunded_total,3000);assert.equal(remaining.paid,0);
  }finally{await app.close();}
});
