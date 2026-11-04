import source from './catalogue.json' with {type:'json'};
import {BRANCHES, METHODS, STATUSES, COUPONS, JOB_STATUSES, ROLES, canonicalRole, isManagerRole, check, integer, text, canAccess, calculate, kuwaitDay} from './domain.ts';

import {createTracking} from './tracking.ts';
import type {Database, DocumentStore, Row} from './storage.ts';

export function createService(runtime: {database: Database; bucket: DocumentStore; authenticate: (request:Request)=>Promise<{userId:string}|null>; setPassword:(id:string,password:string)=>Promise<void>}) {
const now=()=>new Date().toISOString();
const uuid=()=>crypto.randomUUID();
const db=()=>runtime.database;
const stmt=(sql:string,...args:any[])=>db().prepare(sql).bind(...args);
async function all(sql:string,...args:any[]):Promise<Row[]> {return (await stmt(sql,...args).all()).results as Row[];}
async function first(sql:string,...args:any[]):Promise<Row|null> {return stmt(sql,...args).first();}
function log(branch:string, actor:Row, action:string, entity:string, detail='',whenChanged=false) {
  return stmt('INSERT INTO audit (id,branch,actor,action,entity,detail,created_at) SELECT ?,?,?,?,?,?,?'+(whenChanged?' WHERE changes()=1':''),uuid(),branch,actor.user_id,action,entity,detail,now());
}
const tracking=createTracking({all,first,stmt,db,log});
async function identity(request:Request) {
  const user=await runtime.authenticate(request); check(user,'Sign in to continue.',401);
  const member=await first('SELECT * FROM members WHERE user_id=? AND active=1',user.userId);
  check(member,'Your account has not been given staff access. Ask your administrator.',403);
  member.role=canonicalRole(member.role);check(ROLES.includes(member.role),'Your role is not configured. Ask an administrator.',403);
  member.branches=JSON.parse(member.branches); return member;
}
function branchAccess(member:Row,branch:string) {check(canAccess(member as any,branch),'You do not have access to this branch.',403);}
function manager(member:Row) {check(['admin','manager'].includes(member.role),'Manager access required.',403);}
function admin(member:Row) {check(member.role==='admin','Administrator access required.',403);}
async function catalogue() {
  const overrides=await all('SELECT * FROM prices');
  return source.map(p=>({...p,...overrides.find(o=>o.id===p.id),active:overrides.find(o=>o.id===p.id)?.active??1}));
}
async function order(member:Row,id:string) {
  const result=await first('SELECT o.*,m.name tailor_name,m.active tailor_active FROM orders o LEFT JOIN members m ON m.id=o.tailor_id WHERE o.id=?',id); check(result,'Sale not found.',404); branchAccess(member,result.branch); return result;
}
function decode(row:Row) {return {...row,lines:JSON.parse(row.lines)};}
function dateRange(url:URL) {
  const from=url.searchParams.get('from')||kuwaitDay(); const to=url.searchParams.get('to')||from;
  check(/^\d{4}-\d{2}-\d{2}$/.test(from)&&/^\d{4}-\d{2}-\d{2}$/.test(to)&&from<=to,'Select a valid date range.');
  return [new Date(from+'T00:00:00+03:00').toISOString(),new Date(to+'T23:59:59.999+03:00').toISOString()];
}
async function read(member:Row,path:string[],url:URL):Promise<any> {
  if(path[0]==='boot') {
    const staff=await all('SELECT id,name,role,branches,active FROM members WHERE active=1');
    const visibleStaff=staff.map((s):Row=>({...s,role:canonicalRole(s.role),branches:JSON.parse(s.branches)})).filter(s=>member.role==='admin'||(member.role==='tailor'?s.id===member.id:s.branches.some((b:string)=>canAccess(member as any,b))));
    return {member,branches:BRANCHES.filter(b=>canAccess(member as any,b.id)),catalogue:member.role==='tailor'?[]:await catalogue(),methods:member.role==='tailor'?[]:METHODS,statuses:STATUSES,jobStatuses:JOB_STATUSES,coupons:member.role==='tailor'?[]:COUPONS,staff:visibleStaff};
  }
  if(path[0]==='tracking')return tracking.read(member,path[1],url);
  tracking.office(member);
  if(path[0]==='dashboard'){const [start,end]=dateRange(url);return tracking.dashboard(member,url,start,end);}
  if(path[0]==='customers') {
    if(path[1]) {
      const branch=text(url.searchParams.get('branch'),30);branchAccess(member,branch);
      const customer=await first('SELECT * FROM customers WHERE id=?',text(path[1],100));check(customer,'Customer not found.',404);
      const summary=await first("SELECT COUNT(*) bills,COALESCE(SUM(total),0) total,COALESCE(SUM(paid),0) paid,COALESCE(SUM(total-paid),0) due,MIN(created_at) first_bill,MAX(created_at) last_bill FROM orders WHERE customer_id=? AND branch=? AND kind='sale' AND status NOT IN ('Voided','Refunded')",customer.id,branch);
      const history=await all("SELECT id,bill,branch,total,paid,status,created_at FROM orders WHERE customer_id=? AND branch=? AND kind='sale' ORDER BY created_at DESC LIMIT 100",customer.id,branch);
      return {customer,summary,history};
    }
    const q=text(url.searchParams.get('q'),100); if(!q) return [];
    const digits=q.replace(/[^0-9]/g,'');
    return all("SELECT * FROM customers WHERE instr(lower(name),lower(?))>0 OR instr(phone,?)>0 OR (?<>'' AND instr(replace(replace(replace(replace(replace(phone,' ',''),'-',''),'(',''),')',''),'+',''),?)>0) ORDER BY name LIMIT 30",q,q,digits,digits);
  }
  if(path[0]==='data') {
    const branch=text(url.searchParams.get('branch'),30); branchAccess(member,branch);
    const [start,end]=dateRange(url);
    const sales=await all("SELECT o.*,m.name tailor_name,m.active tailor_active FROM orders o LEFT JOIN members m ON m.id=o.tailor_id WHERE o.branch=? AND ((o.created_at BETWEEN ? AND ?) OR o.kind IN ('held','quotation')) ORDER BY o.created_at DESC LIMIT 1000",branch,start,end);
    return {orders:sales.map(decode),payments:await all('SELECT * FROM payments WHERE branch=? AND created_at BETWEEN ? AND ? ORDER BY created_at DESC LIMIT 5000',branch,start,end),expenses:await all('SELECT * FROM expenses WHERE branch=? AND created_at BETWEEN ? AND ? ORDER BY created_at DESC LIMIT 1000',branch,start,end)};
  }
  if(path[0]==='orders' && path[1]) {
    const sale=await order(member,path[1]);
    return {order:decode(sale),payments:await all('SELECT * FROM payments WHERE order_id=? ORDER BY created_at',sale.id),attachments:await all('SELECT id,name,type FROM attachments WHERE order_id=?',sale.id)};
  }
  if(path[0]==='admin') {
    admin(member); const [start,end]=dateRange(url);
    return {members:(await all('SELECT id,email,username,name,role,branches,active FROM members ORDER BY role,name')).map(m=>({...m,role:canonicalRole(m.role)})),audit:await all('SELECT * FROM audit ORDER BY created_at DESC LIMIT 150'),summary:await all("SELECT branch,COUNT(*) count,SUM(total) total,SUM(paid) paid,SUM(total-paid) due FROM orders WHERE kind='sale' AND status NOT IN ('Voided','Refunded') AND created_at BETWEEN ? AND ? GROUP BY branch",start,end)};
  }
  check(false,'Endpoint not found.',404);
}
async function write(member:Row,path:string[],body:Row):Promise<any> {
  if(path[0]==='tracking'&&path[1])return tracking.progress(member,path[1],body);
  tracking.office(member);
  if(path[0]==='customers') {
    const name=text(body.name,100),phone=text(body.phone,30),address=text(body.address,500);
    check(name.length>0,'Enter a customer name.'); check(!phone || /^[+\d\s()-]{5,30}$/.test(phone),'Enter a valid phone number.');
    if(body.branch)branchAccess(member,text(body.branch,30));
    if(path[1]) {
      const id=text(path[1],100);check(await first('SELECT id FROM customers WHERE id=?',id),'Customer not found.',404);
      await db().batch([stmt('UPDATE customers SET name=?,phone=?,address=? WHERE id=?',name,phone,address,id),log(text(body.branch,30),member,'customer.updated',id)]);
      return first('SELECT * FROM customers WHERE id=?',id);
    }
    const id=uuid(); await db().batch([stmt('INSERT INTO customers (id,name,phone,address,created_at) VALUES (?,?,?,?,?)',id,name,phone,address,now()),log('',member,'customer.created',id)]);
    return {id,name,phone,address};
  }
  if(path[0]==='orders' && !path[1]) {
    const branch=text(body.branch,30); branchAccess(member,branch);
    const id=text(body.id,100); check(/^[a-zA-Z0-9-]{16,100}$/.test(id),'Missing transaction identifier.');
    const existing=await first('SELECT * FROM orders WHERE id=?',id);
    if(existing) {branchAccess(member,existing.branch); return decode(existing);}
    const kind=text(body.kind,20); check(['sale','held','quotation'].includes(kind),'Invalid order type.');
    const totals=calculate(body,await catalogue(),isManagerRole(member.role));
    const paymentList=body.payments??[]; check(Array.isArray(paymentList)&&paymentList.length<=8,'Invalid payments.');
    const payments=paymentList.map((p:any)=>({amount:integer(p.amount,'Payment',1),method:text(p.method,40),reference:text(p.reference,120)}));
    check(payments.every(p=>METHODS.includes(p.method)),'Unknown payment method.');
    const paid=payments.reduce((s,p)=>s+p.amount,0); check(paid<=totals.total,'Payment exceeds total.'); check(kind==='sale' || paid===0,'Held orders and quotations cannot receive payments.');
    const customer=body.customerId ? await first('SELECT * FROM customers WHERE id=?',text(body.customerId,100)) : null;
    check(!body.customerId || customer,'Customer not found.');
    const staff=text(body.staff,100); if(staff) {const s=await first('SELECT * FROM members WHERE id=? AND active=1',staff); check(s && canAccess({...s,branches:JSON.parse(s.branches)} as any,branch),'Employee is not assigned to this branch.');}
    const tailorId=text(body.tailorId,100);await tracking.validateTailor(branch,tailorId);
    const timestamp=now(),b=BRANCHES.find(b=>b.id===branch)!;
    const bill=`${b.code}-${kuwaitDay().replaceAll('-','')}-${id.slice(-8).toUpperCase()}`;
    const sourceId=text(body.sourceId,100); let sourceOrder:Row|null=null;
    if(sourceId) {sourceOrder=await order(member,sourceId); check(sourceOrder.branch===branch&&['held','quotation'].includes(sourceOrder.kind),'This saved order has already been converted.',409);}
    const docs=body.attachments??[]; check(Array.isArray(docs)&&docs.length<=10,'Maximum 10 documents.');
    for(const doc of docs) check(await first('SELECT id FROM attachments WHERE id=? AND branch=? AND (order_id IS NULL OR order_id=?)',text(doc,100),branch,sourceId),'Document is unavailable.');
    const operations=[];
    if(sourceOrder) operations.push(stmt("UPDATE orders SET kind='converted',version=version+1 WHERE id=? AND kind IN ('held','quotation') AND version=? RETURNING id",sourceId,integer(body.sourceVersion,'Saved order version')));
    // A unique source marker makes conversion safe even when two tills resume the same draft.
    const externalId=sourceId?`converted:${sourceId}`:null;
    operations.push(stmt('INSERT INTO orders (id,branch,bill,kind,customer_id,customer_name,phone,address,lines,subtotal,discount,extra,total,paid,notes,cashier,cashier_id,staff,aggregator,status,created_at,updated_at,due_date,version,external_id,coupon,tailor_id,job_status,assigned_at,job_updated_at) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)',id,branch,bill,kind,customer?.id??null,customer?.name??'Walk-in customer',customer?.phone??'',customer?.address??'',JSON.stringify(totals.lines),totals.subtotal,totals.discount,totals.extra,totals.total,paid,text(body.notes,4000),member.name,member.user_id,staff,text(body.aggregator,100),kind==='held'?'Held':kind==='quotation'?'Quotation':'Ongoing',timestamp,timestamp,text(body.dueDate,30),0,externalId,text(body.coupon,50),tailorId||null,'Pending',tailorId?timestamp:'',tailorId?timestamp:''));
    if(tailorId&&kind==='sale')operations.push(tracking.event(member,{id,branch},'assigned',JSON.stringify({from:'',to:tailorId,note:'Assigned at invoicing'})));
    for(const p of payments) operations.push(stmt('INSERT INTO payments (id,order_id,branch,amount,method,reference,actor,created_at) VALUES (?,?,?,?,?,?,?,?)',uuid(),id,branch,p.amount,p.method,p.reference,member.user_id,timestamp));
    for(const doc of docs) operations.push(stmt('UPDATE attachments SET order_id=? WHERE id=?',id,doc));
    operations.push(log(branch,member,`${kind}.created`,id,sourceId?`Converted ${sourceId}`:''));
    await db().batch(operations); return decode((await first('SELECT * FROM orders WHERE id=?',id))!);
  }
  if(path[0]==='orders' && path[1]) {
    const sale=await order(member,path[1]),action=text(body.action,40);
    const version=integer(body.version,'Version');
    if(action==='payment') {
      const duplicate=await first('SELECT * FROM payments WHERE id=?',text(body.id,100));
      if(duplicate) {check(duplicate.order_id===sale.id,'Payment identifier conflict.',409);return decode(sale);}
    }
    check(version===sale.version,'This sale changed. Refresh and try again.',409);
    check(sale.kind==='sale','Only sales can be updated.');
    if(action==='assign'){await tracking.assign(member,sale,body);}
    else if(action==='payment') {
      check(!['Voided','Refunded'].includes(sale.status),'This sale is no longer payable.');
      const id=text(body.id,100); check(/^[a-zA-Z0-9-]{16,100}$/.test(id),'Missing payment identifier.');
      const duplicate=await first('SELECT * FROM payments WHERE id=?',id);
      if(duplicate) {check(duplicate.order_id===sale.id,'Payment identifier conflict.',409); return decode(sale);}
      const amount=integer(body.amount,'Payment',1),method=text(body.method,40); check(METHODS.includes(method),'Unknown payment method.'); check(amount<=sale.total-sale.paid,'Payment exceeds balance due.');
      const timestamp=now();
      const results=await db().batch([
        stmt('UPDATE orders SET paid=paid+?,version=version+1,updated_at=? WHERE id=? AND version=? AND paid+?<=total RETURNING id',amount,timestamp,sale.id,version,amount),
        log(sale.branch,member,'payment.recorded',sale.id,JSON.stringify({amount,method}),true),
        stmt('INSERT INTO payments (id,order_id,branch,amount,method,reference,actor,created_at) SELECT ?,?,?,?,?,?,?,? WHERE changes()=1',id,sale.id,sale.branch,amount,method,text(body.reference,120),member.user_id,timestamp),
      ]);
      check(results[0].results.length,'Another payment was recorded. Refresh and try again.',409);
    } else if(action==='status') {
      const status=text(body.status,40); check(STATUSES.includes(status),'Invalid status.');
      check(!['Voided','Refunded'].includes(sale.status),'This sale cannot change status.');
      const next=STATUSES.indexOf(status),current=STATUSES.indexOf(sale.status);
      check(next===current+1 || isManagerRole(member.role),'Advance one status at a time.');
      check(status!=='Closed' || sale.paid===sale.total,'Collect the outstanding balance before closing.');
      const result=await db().batch([stmt('UPDATE orders SET status=?,version=version+1,updated_at=? WHERE id=? AND version=? RETURNING id',status,now(),sale.id,version),log(sale.branch,member,'sale.status',sale.id,status,true)]);
      check(result[0].results.length,'Sale changed. Refresh and try again.',409);
    } else if(action==='staff') {
      const staff=text(body.staff,100); const person=await first('SELECT * FROM members WHERE id=? AND active=1',staff);
      check(person&&canAccess({...person,branches:JSON.parse(person.branches)} as any,sale.branch),'Employee is not assigned to this branch.');
      const result=await db().batch([stmt('UPDATE orders SET staff=?,version=version+1,updated_at=? WHERE id=? AND version=? RETURNING id',staff,now(),sale.id,version),log(sale.branch,member,'sale.staff',sale.id,staff,true)]);
      check(result[0].results.length,'Sale changed. Refresh and try again.',409);
    } else if(action==='void' || action==='refund') {
      manager(member); check(!['Voided','Refunded'].includes(sale.status),'This sale was already reversed.');
      if(action==='refund')check(METHODS.includes(body.method),'Select a valid refund method.');
      check(action==='refund' || sale.paid===0,'Refund payments before voiding a paid sale.');
      const reason=text(body.reason,1000); check(reason.length>=3,'Enter a reason.');
      const result=await db().batch([
        stmt('UPDATE orders SET status=?,paid=0,version=version+1,updated_at=? WHERE id=? AND version=? RETURNING id',action==='refund'?'Refunded':'Voided',now(),sale.id,version),
        log(sale.branch,member,`sale.${action}`,sale.id,reason,true),
        stmt('INSERT INTO payments (id,order_id,branch,amount,method,reference,actor,created_at) SELECT ?,?,?,?,?,?,?,? WHERE changes()=1 AND ?>0',uuid(),sale.id,sale.branch,-sale.paid,text(body.method,40)||'Cash',reason,member.user_id,now(),sale.paid),
      ]); check(result[0].results.length,'Sale changed. Refresh and try again.',409);
    } else if(action==='method') {
      manager(member); check(METHODS.includes(body.method),'Unknown payment method.');
      check(await first('SELECT id FROM payments WHERE id=? AND order_id=?',text(body.paymentId,100),sale.id),'Payment not found.');
      await db().batch([stmt('UPDATE payments SET method=? WHERE id=? AND order_id=?',body.method,body.paymentId,sale.id),log(sale.branch,member,'payment.method',sale.id,JSON.stringify({payment:body.paymentId,method:body.method}))]);
    } else check(false,'Unknown action.');
    return decode((await first('SELECT * FROM orders WHERE id=?',sale.id))!);
  }
  if(path[0]==='expenses') {
    const branch=text(body.branch,30); branchAccess(member,branch);
    const amount=integer(body.amount,'Expense amount',1),description=text(body.description,1000),category=text(body.category,100),method=text(body.method,40); check(description&&category,'Enter a category and description.'); check(METHODS.includes(method),'Unknown payment method.');
    const id=text(body.id,100); check(/^[a-zA-Z0-9-]{16,100}$/.test(id),'Missing expense identifier.');
    const duplicate=await first('SELECT * FROM expenses WHERE id=?',id); if(duplicate) {branchAccess(member,duplicate.branch);return duplicate;}
    await db().batch([stmt('INSERT INTO expenses (id,branch,category,description,amount,method,actor,created_at) VALUES (?,?,?,?,?,?,?,?)',id,branch,category,description,amount,method,member.user_id,now()),log(branch,member,'expense.created',id)]); return {id};
  }
  if(path[0]==='members') {
    admin(member);
    const existing=body.id?await first('SELECT * FROM members WHERE id=?',text(body.id,100)):null;
    check(!body.id||existing,'Staff account not found.',404);
    const name=text(body.name,100),email=text(existing?.email??body.email,200).toLowerCase(),role=canonicalRole(text(body.role,20)),branches=body.branches;
    const username=text(body.username??existing?.username,50).toLowerCase();
    check(name&&(username||(email&&!email.endsWith('@users.invalid')))&&(!email||/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)),'Enter a name and username.');
    check(!username||/^[a-z0-9][a-z0-9._-]{2,49}$/.test(username),'Use a username with 3–50 letters, numbers, dots, hyphens or underscores.');
    check(ROLES.includes(role),'Invalid role.');
    check(Array.isArray(branches)&&branches.every(b=>BRANCHES.some(x=>x.id===b)),'Invalid branch assignments.'); check(role==='admin'||branches.length>0,'Assign at least one branch.');
    const password=body.password??'';check(typeof password==='string'&&password.length<=256,'Invalid password.'); check(body.id || password.length>=12,'Set an initial password with at least 12 characters.'); check(!password || password.length>=12,'Use a password with at least 12 characters.');
    const id=body.id?text(body.id,100):uuid(); check(id!=='owner','The initial owner cannot be changed.'); check(id!==member.id,'You cannot change your own access.');
    if(username)check(!await first('SELECT id FROM members WHERE username=? AND id<>?',username,id),'This username is already in use.',409);
    if(email)check(!await first('SELECT id FROM members WHERE lower(email)=? AND id<>?',email,id),'This email is already in use.',409);
    await db().batch([stmt('INSERT INTO members (id,user_id,email,username,name,role,branches,active) VALUES (?,NULL,?,?,?,?,?,?) ON CONFLICT(id) DO UPDATE SET username=excluded.username,name=excluded.name,role=excluded.role,branches=excluded.branches,active=excluded.active',id,email||`${id}@users.invalid`,username||null,name,role,JSON.stringify(branches),body.active===0?0:1),log('',member,'staff.updated',id,JSON.stringify({username,email,role,branches,active:body.active}))]);
    if(password)await runtime.setPassword(id,password);
    return {id};
  }
  if(path[0]==='prices') {
    admin(member); const product=source.find(p=>p.id===body.id); check(product,'Item not found.'); const price=integer(body.price,'Price');
    await db().batch([stmt('INSERT INTO prices (id,price,active) VALUES (?,?,?) ON CONFLICT(id) DO UPDATE SET price=excluded.price,active=excluded.active',product.id,price,body.active===0?0:1),log('',member,'catalogue.updated',product.id,JSON.stringify({price,active:body.active}))]);return {ok:true};
  }
  check(false,'Endpoint not found.',404);
}
async function api(request:Request,path:string[]) {
  try {
    const member=await identity(request);
    if(request.method==='GET') return Response.json(await read(member,path,new URL(request.url)),{headers:{'Cache-Control':'no-store'}});
    check(request.method==='POST','Method not allowed.',405);
    // Same-origin requests only, including behind the hosting proxy.
    const origin=request.headers.get('origin'); check(!origin || origin===new URL(request.url).origin,'Cross-origin write rejected.',403);
    check((request.headers.get('content-type')??'').includes('application/json'),'JSON required.',415);
    const raw=await request.text(); check(raw.length<=150_000,'Request too large.',413);
    const body=JSON.parse(raw); check(body&&typeof body==='object'&&!Array.isArray(body),'Invalid request.');
    return Response.json(await write(member,path,body),{headers:{'Cache-Control':'no-store'}});
  } catch(error:any) {
    const conflict=String(error.message).includes('UNIQUE constraint failed');
    const status=error.status??(error instanceof SyntaxError?400:conflict?409:500);
    if(status===500) console.error('POS request failed',error.message);
    return Response.json({error:status===500?'The request could not be saved. Refresh and try again.':conflict?'This record was already saved or changed. Refresh and try again.':error.message},{status,headers:{'Cache-Control':'no-store'}});
  }
}
async function document(request:Request,id:string) {
  try {
    const member=await identity(request);
    if(request.method==='GET') {
      const doc=await first('SELECT * FROM attachments WHERE id=?',id); check(doc,'Document not found.',404); branchAccess(member,doc.branch);
      if(member.role==='tailor'){check(doc.order_id,'This document is not assigned to you.',403);await tracking.job(member,doc.order_id);}
      const file=await runtime.bucket.get(doc.object_key); check(file,'File not found.',404);
      return new Response(file.body,{headers:{'Content-Type':doc.type,'Content-Disposition':`attachment; filename*=UTF-8''${encodeURIComponent(doc.name)}`,'X-Content-Type-Options':'nosniff','Cache-Control':'private, no-store'}});
    }
    check(request.method==='POST','Method not allowed.',405);
    tracking.office(member);
    const origin=request.headers.get('origin'); check(!origin||origin===new URL(request.url).origin,'Cross-origin write rejected.',403);
    const branch=new URL(request.url).searchParams.get('branch')??''; branchAccess(member,branch);
    const type=request.headers.get('content-type')??''; check(['image/jpeg','image/png','image/webp','application/pdf'].includes(type),'Upload a PDF, JPG, PNG or WebP.');
    check(Number(request.headers.get('content-length')??0)<=5*1024*1024,'Maximum file size is 5 MB.',413);
    const bytes=await request.arrayBuffer(); check(bytes.byteLength>0&&bytes.byteLength<=5*1024*1024,'Maximum file size is 5 MB.',413);
    const docId=uuid(),key=`documents/${branch}/${docId}`,name=text(request.headers.get('x-file-name')?decodeURIComponent(request.headers.get('x-file-name')!):'document',150);
    await runtime.bucket.put(key,bytes);
    try {await stmt('INSERT INTO attachments (id,branch,order_id,name,type,object_key,created_at) VALUES (?,?,NULL,?,?,?,?)',docId,branch,name,type,key,now()).run();} catch(e) {await runtime.bucket.delete(key);throw e;}
    return Response.json({id:docId,name,type});
  } catch(e:any) {return Response.json({error:e.status?e.message:'Document operation failed.'},{status:e.status??500});}
}

return {api,document};
}
