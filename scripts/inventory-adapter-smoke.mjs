// Run only against prepared source and isolated synthetic data; never the live app.
import {spawn} from 'node:child_process';
import {mkdirSync,writeFileSync,readFileSync,existsSync} from 'node:fs';
import {randomUUID,randomBytes,createHash} from 'node:crypto';
import http from 'node:http';
import path from 'node:path';
import assert from 'node:assert/strict';
import {createApp} from '../server/index.mjs';
const source=path.resolve(process.argv[2]||''),prepared=path.resolve('work/inventory-integration'),stage=existsSync(path.join(prepared,'server.js'))?prepared:source,directory=path.resolve('outputs','inventory-smoke-'+randomUUID());
assert.ok(source&&readFileSync(path.join(source,'package.json'),'utf8').includes('storage-app-backend'),'Pass the inventory source directory.');
const originalHash=createHash('sha256').update(readFileSync(path.join(source,'data.json'))).digest('hex');
mkdirSync(directory,{recursive:true});const key=randomBytes(32).toString('hex'),password='Test-'+randomUUID();
writeFileSync(path.join(directory,'inventory.json'),JSON.stringify({branches:[{id:'B001',name:'Main Storage'},{id:'B008',name:'Zahra'},{id:'B003',name:'Avenues'}],users:[{id:'a',name:'Test Admin',role:'admin',password},{id:'d',name:'Test Driver',role:'driver',password}],deliveryAreas:[{name:'Test Area',zone:'One',charge:'2.000',active:true}],deliveries:[],items:[{id:'test-item',baseQty:10}],budgets:[]}));
const probe=http.createServer();await new Promise(r=>probe.listen(0,'127.0.0.1',r));const port=probe.address().port;await new Promise(r=>probe.close(r));
const child=spawn(process.execPath,[path.join(stage,'server.js')],{cwd:stage,env:{...process.env,PORT:String(port),DATA_FILE:path.join(directory,'inventory.json'),NODE_PATH:path.join(source,'node_modules'),POS_INTEGRATION_KEY:key},stdio:['ignore','pipe','pipe'],windowsHide:true});
let output='';child.stdout.on('data',b=>output+=b);child.stderr.on('data',b=>output+=b);
const url='http://127.0.0.1:'+port;let pos;
try{
  let ready=false;for(let i=0;i<100;i++){try{const r=await fetch(url+'/api/integrations/pos/catalogue',{headers:{Authorization:'Bearer '+key}});if(r.ok){ready=true;break;}}catch{}if(child.exitCode!==null)throw new Error('Inventory test process exited: '+output);await new Promise(r=>setTimeout(r,100));}assert.ok(ready,'Prepared inventory server did not start.');
  pos=await createApp({dataDirectory:path.join(directory,'pos'),production:false,push:false,inventory:{url,key,start:false}});
  await new Promise(r=>pos.server.listen(0,'127.0.0.1',r));const base='http://127.0.0.1:'+pos.server.address().port;
  await pos.auth.createOwner({name:'Test Admin',username:'admin',password});const login=await fetch(base+'/api/auth/login',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({username:'admin',password})});const cookie=login.headers.get('set-cookie').split(';')[0];
  async function api(route,body,status=200){const r=await fetch(base+'/api/'+route,{method:body?'POST':'GET',headers:{Cookie:cookie,...(body?{'Content-Type':'application/json',Origin:base}:{})},body:body?JSON.stringify(body):undefined});const data=await r.json();assert.equal(r.status,status,JSON.stringify(data));return data;}
  async function storage(route,body,status=200,method='POST'){const r=await fetch(url+'/api/'+route,{method,headers:{'Content-Type':'application/json'},body:JSON.stringify(body)});const data=await r.json();assert.equal(r.status,status,JSON.stringify(data));return data;}
  await api('inventory-connection',{mappings:[{branch:'zahra',inventoryBranchId:'B008'}]});
  const tailor=await api('members',{username:'test.tailor',name:'Test Tailor',role:'tailor',branches:['zahra'],password});
  const customer=await api('customers',{name:'Test Customer',phone:'55551234',address:'Test block, street and house'});
  let order=await api('orders',{id:randomUUID(),branch:'zahra',kind:'sale',customerId:customer.id,tailorId:tailor.id,lines:[{id:'1001',price:2000,qty:1}],payments:[]});
  const chargeResult=await api('orders/'+order.id,{action:'charge',id:randomUUID(),version:order.version,chargeKind:'delivery',name:'Delivery fee',amount:2000});order=chargeResult;const deliveryInvoice=chargeResult.adjustment;
  let row=await api('orders/'+order.id+'/delivery',{action:'create',version:order.version,deliveryInvoiceId:deliveryInvoice.id,areaName:'Test Area',fromBranchId:'B003'});
  await Promise.all([pos.deliveries.flush(),storage('budgets',{branchId:'B008',month:'2026-11',planned:100,adminUserId:'a'},201)]);
  row=(await api('orders/'+order.id+'/delivery')).delivery;assert.equal(row.desired_status,'draft');
  const beforeApproval=JSON.parse(readFileSync(path.join(directory,'inventory.json'),'utf8'));assert.equal(beforeApproval.deliveries.length,0);assert.equal(beforeApproval.budgets.length,1);assert.equal(beforeApproval.items[0].baseQty,10);
  await api('orders/'+order.id+'/delivery',{action:'send',revision:row.revision},409);
  for(const status of ['In Progress','Awaiting Review']){const job=(await api('tracking/'+order.id)).job;await api('tracking/'+order.id,{action:'progress',status,version:job.version});}
  let job=(await api('tracking/'+order.id)).job;await api('tracking/'+order.id,{action:'review',version:job.version,approved:true});
  row=await api('orders/'+order.id+'/delivery',{action:'send',revision:row.revision});await pos.deliveries.flush();
  row=(await api('orders/'+order.id+'/delivery')).delivery;
  const remote=JSON.parse(readFileSync(path.join(directory,'inventory.json'),'utf8'));assert.equal(remote.deliveries.length,1);assert.equal(remote.deliveries[0].fromBranchId,'B008');assert.equal(remote.deliveries[0].invoiceNo,deliveryInvoice.bill);assert.equal(remote.deliveries[0].status,'ready');
  await storage('deliveries/'+row.remote_id+'/assign-driver',{userId:'a',driverUserId:'d'});
  await storage('deliveries/'+row.remote_id+'/status',{userId:'a',status:'ready'},409);
  await storage('deliveries/'+row.remote_id,{userId:'a'},409,'DELETE');
  await storage('deliveries/'+row.remote_id+'/status',{userId:'d',status:'in_transit'});
  await storage('deliveries/'+row.remote_id+'/eta',{userId:'d',etaLabel:'30 minutes',etaAt:''});
  pos.storage.sqlite.prepare("UPDATE customer_deliveries SET next_attempt=''").run();await pos.deliveries.flush();
  row=(await api('orders/'+order.id+'/delivery')).delivery;assert.equal(row.remote_status,'in_transit');assert.equal(row.driver_name,'Test Driver');assert.equal(row.eta_label,'30 minutes');
  await storage('deliveries/'+row.remote_id+'/status',{userId:'d',status:'delivered'});
  pos.storage.sqlite.prepare("UPDATE customer_deliveries SET next_attempt=''").run();await pos.deliveries.flush();assert.equal((await api('orders/'+order.id+'/customer-status')).delivery.status,'delivered');
  assert.equal(JSON.parse(readFileSync(path.join(directory,'inventory.json'),'utf8')).deliveries.length,1);
  assert.equal(createHash('sha256').update(readFileSync(path.join(source,'data.json'))).digest('hex'),originalHash);
  console.log('Actual inventory-server smoke passed: POS request, fixed branch, legacy JSON write preservation, reception approval, driver pickup/ETA/delivery, duplicate prevention and deletion protection. Original inventory data unchanged.');
}finally{if(pos)await pos.close();if(child.exitCode===null){const stopped=new Promise(r=>child.once('exit',r));child.kill();await stopped;}}
