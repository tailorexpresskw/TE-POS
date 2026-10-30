import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
const origin=process.argv[2]??'http://127.0.0.1:8787';
assert.ok(['127.0.0.1','localhost'].includes(new URL(origin).hostname),'Run this test only against a local database.');
let checks=0;
const owner={id:'local-test-owner',email:'owner@pos.test'};
const cashier={id:'local-test-cashier',email:'cashier@pos.test'};
const other={id:'local-test-other',email:'other@pos.test'};
async function call(path,{user=owner,body,status=200}={}) {
  const response=await fetch(`${origin}/api/${path}`,{method:body?'POST':'GET',headers:{...(user?{'oai-authenticated-user-id':user.id,'oai-authenticated-user-email':user.email}:{}),...(body?{'Content-Type':'application/json',Origin:origin}:{})},body:body?JSON.stringify(body):undefined});
  const text=await response.text();let data;
  try{data=JSON.parse(text);}catch{throw new Error(`Unexpected ${response.status}: ${text.slice(0,300)}`);}
  assert.equal(response.status,status,`${path}: ${JSON.stringify(data)}`);checks++;return data;
}
await call('boot',{user:null,status:401});
const boot=await call('boot');assert.equal(boot.catalogue.length,446);assert.equal(boot.branches.length,10);
const existing=await call('admin');
for(const [user,name,branch] of [[cashier,'Cashier','zahra'],[other,'Other branch','aventura']]) {
  if(!existing.members.some(m=>m.email===user.email))await call('members',{body:{name,email:user.email,role:'cashier',branches:[branch]}});
}
await call('boot',{user:cashier});await call('boot',{user:other});
await call('data?branch=aventura',{user:cashier,status:403});await call('admin',{user:cashier,status:403});
const id=randomUUID(),draft={id,branch:'zahra',kind:'sale',lines:[{id:'1001',qty:1,price:2000}],payments:[]};
await call('orders',{user:cashier,body:{...draft,id:randomUUID(),lines:[{id:'1001',qty:1,price:1}]},status:403});
await call('orders',{user:cashier,body:{...draft,id:randomUUID(),discount:500},status:403});
const sale=await call('orders',{user:cashier,body:draft});assert.equal(sale.total,2000);
const duplicate=await call('orders',{user:cashier,body:draft});assert.equal(duplicate.id,sale.id);
await call(`orders/${id}`,{user:other,status:403});
await call(`orders/${id}`,{user:cashier,body:{action:'payment',id:randomUUID(),version:0,amount:2001,method:'Cash'},status:400});
const firstPayId=randomUUID();
const firstPay=await call(`orders/${id}`,{user:cashier,body:{action:'payment',id:firstPayId,version:0,amount:1000,method:'K-NET'}});assert.equal(firstPay.paid,1000);
await call(`orders/${id}`,{user:cashier,body:{action:'payment',id:firstPayId,version:0,amount:1000,method:'K-NET'}});
const options=[randomUUID(),randomUUID()].map(paymentId=>fetch(`${origin}/api/orders/${id}`,{method:'POST',headers:{'Content-Type':'application/json',Origin:origin,'oai-authenticated-user-id':cashier.id,'oai-authenticated-user-email':cashier.email},body:JSON.stringify({action:'payment',id:paymentId,version:1,amount:1000,method:'Cash'})}));
const outcomes=await Promise.all(options);assert.deepEqual(outcomes.map(r=>r.status).sort(),[200,409]);checks++;
const paid=await call(`orders/${id}`,{user:cashier});assert.equal(paid.order.paid,2000);assert.equal(paid.payments.reduce((s,p)=>s+p.amount,0),2000);
const auditResult=await call('admin');assert.equal(auditResult.audit.filter(a=>a.entity===id&&a.action==='payment.recorded').length,2);
await call(`orders/${id}`,{user:cashier,body:{action:'status',version:paid.order.version,status:'Closed'},status:400});
await call(`orders/${id}`,{user:cashier,body:{action:'refund',version:paid.order.version,reason:'Test refund',method:'Cash'},status:403});
await call(`orders/${id}`,{body:{action:'refund',version:paid.order.version,reason:'Local test refund',method:'Cash'}});
const refunded=await call(`orders/${id}`);assert.equal(refunded.order.status,'Refunded');assert.equal(refunded.payments.reduce((s,p)=>s+p.amount,0),0);
const upload=await fetch(`${origin}/api/documents?branch=zahra`,{method:'POST',headers:{'oai-authenticated-user-id':cashier.id,'oai-authenticated-user-email':cashier.email,'Content-Type':'application/pdf','X-File-Name':'test-measurements.pdf',Origin:origin},body:'%PDF-1.4\nLocal test fixture'});assert.equal(upload.status,200);const doc=await upload.json();checks++;
const held=await call('orders',{user:cashier,body:{...draft,id:randomUUID(),kind:'held',coupon:'family',attachments:[doc.id]}});assert.equal(held.total,1600);assert.equal(held.coupon,'family');
const converted=await call('orders',{user:cashier,body:{...draft,id:randomUUID(),coupon:'family',attachments:[doc.id],sourceId:held.id,sourceVersion:0}});assert.equal(converted.total,1600);
await call('orders',{user:cashier,body:{...draft,id:randomUUID(),sourceId:held.id,sourceVersion:0},status:409});
const file=await fetch(`${origin}/api/documents/${doc.id}`,{headers:{'oai-authenticated-user-id':other.id,'oai-authenticated-user-email':other.email}});assert.equal(file.status,403);checks++;
const detail=await call(`orders/${converted.id}`);assert.equal(detail.attachments[0].id,doc.id);
const expense={id:randomUUID(),branch:'zahra',amount:250,method:'Cash',category:'Supplies',description:'Local test fixture'};
await call('expenses',{user:cashier,body:expense});await call('expenses',{user:cashier,body:expense});
const state=await call('data?branch=zahra');assert.equal(state.expenses.filter(e=>e.id===expense.id).length,1);
console.log(`${checks} API checks passed: authentication, branch isolation, price permissions, payment concurrency, idempotency, refund ledger, document access and held-order conversion.`);
