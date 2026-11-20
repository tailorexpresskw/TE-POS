import {test} from 'node:test';
import assert from 'node:assert/strict';
import http from 'node:http';
import {randomUUID,randomBytes} from 'node:crypto';
import path from 'node:path';
import {createRequire} from 'node:module';
import {createApp} from './index.mjs';
const {installPosIntegration,guardPosDelivery}=createRequire(import.meta.url)('../integrations/inventory/pos-deliveries.cjs');

async function inventory(){
  let data={branches:[{id:'B001',name:'Main Storage'},{id:'B008',name:'Zahra'},{id:'B003',name:'Avenues'}],deliveryAreas:[{name:'Test Area',nameAr:'',zone:'One',charge:'2.000',active:true}],deliveries:[],users:[{id:'driver',name:'Test Driver'}],items:[{id:'unchanged',baseQty:10}],requests:[]};
  const key=randomBytes(32).toString('hex'),routes=[];
  const app=Object.fromEntries(['get','post','put','patch','delete'].map(method=>[method,(route,...handlers)=>{routes.push({method:method.toUpperCase(),route,handler:handlers.at(-1)});return app;}]));
  const loadData=async()=>structuredClone(data),saveData=async value=>{await new Promise(r=>setTimeout(r,2));data=structuredClone(value);};
  installPosIntegration({app,loadData,saveData,mainStorageBranchId:'B001',token:key});
  app.post('/driver/:requestId',async(req,res)=>{
    try{const value=await loadData(),delivery=value.deliveries.find(d=>d.posRequestId===req.params.requestId);assert.ok(delivery);guardPosDelivery(delivery,req.body.status);delivery.driverUserId='driver';delivery.driverEtaLabel='30 minutes';delivery.status=req.body.status;if(delivery.status==='delivered')delivery.deliveredAt=new Date().toISOString();await saveData(value);res.json({ok:true});}
    catch(error){res.status(error.status||500).json({error:error.message});}
  });
  app.post('/legacy',async(req,res)=>{const value=await loadData();await new Promise(r=>setTimeout(r,2));value.requests.push({id:req.body.id});await saveData(value);res.json({ok:true});});
  const server=http.createServer(async(req,res)=>{
    const route=routes.find(r=>r.method===req.method&&new RegExp('^'+r.route.replace(/:[^/]+/g,'([^/]+)')+'$').test(req.url));
    if(!route){res.writeHead(404);res.end('{}');return;}
    const names=[...route.route.matchAll(/:([^/]+)/g)].map(m=>m[1]),matches=req.url.match(new RegExp('^'+route.route.replace(/:[^/]+/g,'([^/]+)')+'$'));
    req.params=Object.fromEntries(names.map((n,i)=>[n,decodeURIComponent(matches[i+1])]));const chunks=[];for await(const chunk of req)chunks.push(chunk);req.body=chunks.length?JSON.parse(Buffer.concat(chunks).toString()):{};
    const response={set:(name,value)=>res.setHeader(name,value),status:status=>{res.statusCode=status;return response;},json:body=>{res.setHeader('Content-Type','application/json');res.end(JSON.stringify(body));}};
    route.handler(req,response,error=>{res.statusCode=500;res.end(JSON.stringify({error:error.message}));});
  });
  await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
  const url='http://127.0.0.1:'+server.address().port;
  return {url,key,server,data:()=>data,mutate:fn=>fn(data),close:()=>new Promise(resolve=>server.close(resolve))};
}
async function fixture({fetcher}={}){
  const storage=await inventory();
  const app=await createApp({dataDirectory:path.resolve('outputs','deliveries-'+randomUUID()),production:false,push:false,inventory:{url:storage.url,key:storage.key,start:false,fetcher:fetcher??fetch}});
  await new Promise(resolve=>app.server.listen(0,'127.0.0.1',resolve));
  const base='http://127.0.0.1:'+app.server.address().port,password='Test-'+randomUUID(),cookies={},ids={};
  async function call(route,user='admin',body,status=200){const response=await fetch(base+'/api/'+route,{method:body?'POST':'GET',headers:{...(cookies[user]?{Cookie:cookies[user]}:{}),...(body?{'Content-Type':'application/json',Origin:base}:{})},body:body?JSON.stringify(body):undefined});const result=await response.json();assert.equal(response.status,status,`${user} ${route}: ${JSON.stringify(result)}`);return result;}
  async function login(username){const response=await fetch(base+'/api/auth/login',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({username,password})});assert.equal(response.status,200);cookies[username]=response.headers.get('set-cookie').split(';')[0];}
  await app.auth.createOwner({name:'Admin',username:'admin',password});await login('admin');
  for(const [username,role,branches]of [['reception','reception',['zahra']],['other','reception',['avenues']],['tailor','tailor',['zahra']],['supervisor','supervisor',['zahra']]]){ids[username]=(await call('members','admin',{username,role,branches,name:username,password})).id;await login(username);}
  await call('inventory-connection','admin',{mappings:[{branch:'zahra',inventoryBranchId:'B008'},{branch:'avenues',inventoryBranchId:'B003'}]});
  const customer=await call('customers','admin',{name:'Test Customer',phone:'55551234',address:'Block 1, Street 2, House 3'});
  async function sale(branch='zahra'){const original=await call('orders','admin',{id:randomUUID(),branch,kind:'sale',customerId:customer.id,tailorId:branch==='zahra'?ids.tailor:'',lines:[{id:'1001',price:2000,qty:1,note:'Internal measurement, do not send'}],payments:[]});const result=await call('orders/'+original.id,'admin',{action:'charge',id:randomUUID(),version:original.version,chargeKind:'delivery',name:'Delivery fee',amount:2000});return {...result,_deliveryInvoice:result.adjustment};}
  async function request(order,user='reception',body={}){return call('orders/'+order.id+'/delivery',user,{action:'create',version:order.version,deliveryInvoiceId:order._deliveryInvoice.id,areaName:'Test Area',...body});}
  function forceDue(){app.storage.sqlite.prepare("UPDATE customer_deliveries SET next_attempt=''").run();}
  async function approve(order){for(const status of ['In Progress','Awaiting Review']){const current=(await call('tracking/'+order.id,'tailor')).job;await call('tracking/'+order.id,'tailor',{action:'progress',status,version:current.version});}const current=(await call('tracking/'+order.id,'reception')).job;await call('tracking/'+order.id,'reception',{action:'review',version:current.version,approved:true});}
  return {app,storage,call,sale,request,forceDue,approve,ids,close:async()=>{await app.close();await storage.close();}};
}

test('Reception sends a draft linked to its delivery sub-invoice; inventory sees nothing before approval',async()=>{
  const f=await fixture();try{
    const {call,app,storage}=f,order=await f.sale(),before=JSON.stringify(app.storage.sqlite.prepare('SELECT total,paid FROM orders WHERE id=?').get(order.id));
    await call('inventory-connection','reception',undefined,403);await call('inventory-connection','reception',{mappings:[]},403);
    await call('orders/'+order.id+'/delivery','other',undefined,403);await call('orders/'+order.id+'/delivery','tailor',undefined,403);
    const config=await call('inventory-connection');assert.equal(config.connected,true);assert.ok(!JSON.stringify(config).includes(storage.key));
    const rows=await Promise.all([f.request(order),f.request(order,'reception',{branch:'avenues',fromBranchId:'B003'})]);let local=rows[0];assert.equal(rows[0].id,rows[1].id);
    assert.equal(local.payload.fromBranchId,'B008');assert.equal(local.payload.invoiceNo,order._deliveryInvoice.bill);assert.equal(local.delivery_invoice_id,order._deliveryInvoice.id);assert.equal(local.desired_status,'draft');assert.equal(local.approved_at,'');
    assert.ok(!JSON.stringify(local.payload).includes('Internal measurement'));
    await call('orders/'+order.id+'/delivery','reception',{action:'create',version:order.version,deliveryInvoiceId:order._deliveryInvoice.id,areaName:'Test Area',address:'A different address'},409);
    await app.deliveries.flush();assert.equal(storage.data().deliveries.length,0);
    await call('orders/'+order.id+'/delivery','reception',{action:'send',revision:local.revision},409);
    await call('orders/'+order.id+'/delivery','supervisor',{action:'send',revision:local.revision},403);
    await f.approve(order);await app.deliveries.flush();assert.equal(storage.data().deliveries.length,0,'Checking work alone must not submit delivery');
    local=await call('orders/'+order.id+'/delivery','reception',{action:'send',revision:local.revision});assert.ok(local.approved_at);assert.equal(local.approved_by,f.ids.reception);
    await app.deliveries.flush();assert.equal(storage.data().deliveries.length,1);assert.equal(storage.data().deliveries[0].status,'ready');assert.equal(storage.data().deliveries[0].invoiceNo,order._deliveryInvoice.bill);
    let response=await fetch(storage.url+'/driver/'+local.id,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({status:'in_transit'})});assert.equal(response.status,200);
    f.forceDue();await app.deliveries.flush();local=(await call('orders/'+order.id+'/delivery','reception')).delivery;assert.equal(local.remote_status,'in_transit');assert.equal(local.driver_name,'Test Driver');assert.equal(local.eta_label,'30 minutes');
    await call('orders/'+order.id+'/delivery','reception',{action:'cancel',revision:local.revision},409);
    await fetch(storage.url+'/driver/'+local.id,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({status:'delivered'})});f.forceDue();await app.deliveries.flush();
    const status=await call('orders/'+order.id+'/customer-status','reception');assert.equal(status.delivery.status,'delivered');assert.ok(status.delivery.deliveredAt);
    assert.equal(JSON.stringify(app.storage.sqlite.prepare('SELECT total,paid FROM orders WHERE id=?').get(order.id)),before);assert.equal(storage.data().items[0].baseQty,10);assert.equal(storage.data().deliveries.length,1);
    assert.ok((await call('notifications','reception')).items.some(n=>n.type==='delivery'&&n.message.includes('delivered')));assert.ok(!(await call('notifications','other')).items.some(n=>n.type==='delivery'));
  }finally{await f.close();}
});

test('local drafts never create inventory records, including cancellation or delivery-invoice reversal',async()=>{
  const f=await fixture();try{
    const order=await f.sale();let row=await f.request(order);await f.app.deliveries.flush();assert.equal(f.storage.data().deliveries.length,0);
    row=await f.call('orders/'+order.id+'/delivery','reception',{action:'cancel',revision:row.revision});await f.app.deliveries.flush();assert.equal(row.sync_state,'local');assert.equal(f.storage.data().deliveries.length,0);
    const next=await f.sale();await f.request(next);await f.call('orders/'+next._deliveryInvoice.id,'admin',{action:'cancel',id:randomUUID(),version:0,reason:'Delivery not required',reasonCode:'Customer request'});await f.app.deliveries.flush();
    assert.equal((await f.call('orders/'+next.id+'/delivery','reception')).delivery.desired_status,'cancelled');assert.equal(f.storage.data().deliveries.length,0);
    const raw=await f.call('orders','admin',{id:randomUUID(),branch:'zahra',kind:'sale',lines:[{id:'1001',qty:1,price:2000}],payments:[]});
    await f.call('orders/'+raw.id+'/delivery','reception',{action:'create',version:raw.version,areaName:'Test Area',customerName:'Test',customerPhone:'55551234',address:'Test address'},409);
    const data={...row.payload,requestId:'pos-'+randomUUID(),desiredStatus:'ready',revision:0};
    const reject=await fetch(f.storage.url+'/api/integrations/pos/deliveries',{method:'POST',headers:{Authorization:'Bearer '+f.storage.key,'Content-Type':'application/json'},body:JSON.stringify(data)});assert.equal(reject.status,409);assert.equal(f.storage.data().deliveries.length,0);
  }finally{await f.close();}
});

test('approved requests retry idempotently after a lost response; cancelled history and JSON writes persist',async()=>{
  let drop=true;const f=await fixture({fetcher:async(url,options)=>{const response=await fetch(url,options);if(options.body&&drop){drop=false;throw new Error('Simulated lost response');}return response;}});
  try{
    const order=await f.sale();await f.request(order);await f.approve(order);const sent=await f.call('orders/'+order.id+'/delivery','reception',{action:'send',revision:0});await f.app.deliveries.flush();assert.equal(f.storage.data().deliveries.length,1);assert.equal((await f.call('orders/'+order.id+'/delivery','reception')).delivery.sync_state,'retry');
    f.forceDue();await f.app.deliveries.flush();assert.equal(f.storage.data().deliveries.length,1);let row=(await f.call('orders/'+order.id+'/delivery','reception')).delivery;assert.equal(row.sync_state,'synced');
    row=await f.call('orders/'+order.id+'/delivery','reception',{action:'cancel',revision:row.revision});await f.app.deliveries.flush();assert.equal(f.storage.data().deliveries[0].status,'cancelled');assert.throws(()=>guardPosDelivery(f.storage.data().deliveries[0],'in_transit'),/cancelled/);
    const headers={Authorization:'Bearer '+f.storage.key,'Content-Type':'application/json'},payload={...sent.payload,requestId:sent.id,revision:sent.revision,desiredStatus:'ready',approvedAt:sent.approved_at,approvedBy:sent.approved_by};
    const response=await fetch(f.storage.url+'/api/integrations/pos/deliveries',{method:'POST',headers,body:JSON.stringify(payload)});assert.equal((await response.json()).status,'cancelled');
    assert.equal((await fetch(f.storage.url+'/api/integrations/pos/catalogue')).status,401);
    assert.equal((await fetch(f.storage.url+'/api/integrations/pos/deliveries',{method:'POST',headers,body:JSON.stringify({...payload,fromBranchId:'B003',revision:3})})).status,409);
    await Promise.all(Array.from({length:12},(_,i)=>fetch(f.storage.url+'/legacy',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({id:i})})));assert.equal(f.storage.data().requests.length,12);assert.equal(f.storage.data().deliveries.length,1);
  }finally{await f.close();}
});

test('draft edits refresh the address/quote; sent delivery-invoice cancellation is synchronized',async()=>{
  const f=await fixture();try{
    await f.call('inventory-connection','admin',{mappings:[{branch:'zahra',inventoryBranchId:'B008'},{branch:'avenues',inventoryBranchId:'B008'}]},400);
    const order=await f.sale();let row=await f.request(order);f.storage.mutate(d=>d.deliveryAreas[0].charge='3.000');
    row=await f.call('orders/'+order.id+'/delivery','reception',{action:'edit',version:order.version,revision:row.revision,areaName:'Test Area',address:'New address'});assert.equal(row.payload.chargeFils,3000);assert.equal(row.desired_status,'draft');await f.app.deliveries.flush();assert.equal(f.storage.data().deliveries.length,0);
    await f.call('orders/'+order.id+'/delivery','reception',{action:'edit',version:order.version,revision:0,areaName:'Test Area'},409);
    await f.approve(order);row=await f.call('orders/'+order.id+'/delivery','reception',{action:'send',revision:row.revision});await f.app.deliveries.flush();assert.equal(f.storage.data().deliveries[0].status,'ready');
    await f.call('orders/'+order._deliveryInvoice.id,'admin',{action:'cancel',id:randomUUID(),version:0,reason:'Customer no longer wants delivery',reasonCode:'Customer request'});f.forceDue();await f.app.deliveries.flush();assert.equal(f.storage.data().deliveries[0].status,'cancelled');
    assert.ok(f.app.storage.sqlite.prepare("SELECT id FROM audit WHERE action='delivery.approved' AND entity=?").get(order.id));assert.deepEqual(f.app.storage.sqlite.prepare('PRAGMA foreign_key_check').all(),[]);
  }finally{await f.close();}
});
