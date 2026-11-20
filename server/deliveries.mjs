import {randomUUID,createHash} from 'node:crypto';
import {check,text,integer} from '../lib/domain.ts';

export function createDeliveries(sqlite,{url=process.env.INVENTORY_URL,key=process.env.INVENTORY_INTEGRATION_KEY,production=false,fetcher=fetch,start=true}={}) {
  const configured=Boolean(url&&key),stamp=()=>new Date().toISOString();
  if(configured){const parsed=new URL(url);check(parsed.protocol==='https:'||(!production&&parsed.protocol==='http:'&&['localhost','127.0.0.1'].includes(parsed.hostname)),'Inventory URL must use HTTPS.');check(!parsed.username&&!parsed.password&&!parsed.search&&!parsed.hash&&parsed.pathname==='/','Use the inventory app origin URL.');check(key.length>=32,'Use an inventory integration key of at least 32 characters.');}
  let running=null,timer;
  const get=id=>sqlite.prepare('SELECT * FROM customer_deliveries WHERE order_id=?').get(id);
  const invoice=id=>sqlite.prepare('SELECT * FROM orders WHERE id=?').get(id);
  function root(sale){if(sale.document_type==='charge'){check(sale.charge_kind==='delivery'&&sale.parent_order_id,'Choose a delivery sub-invoice.');const parent=invoice(sale.parent_order_id);check(parent&&parent.branch===sale.branch,'Delivery invoice parent is invalid.');return parent;}return sale;}
  function deliveryInvoice(sale,id){const child=invoice(id);check(child&&child.parent_order_id===sale.id&&child.branch===sale.branch&&child.document_type==='charge'&&child.charge_kind==='delivery'&&!['Voided','Refunded'].includes(child.status)&&child.total>child.refunded_total,'Select an active delivery sub-invoice for this order.',409);return child;}
  const mapping=branch=>sqlite.prepare('SELECT inventory_branch_id FROM inventory_branch_mappings WHERE branch=?').get(branch)?.inventory_branch_id;
  const unpack=row=>row?{...row,payload:JSON.parse(row.payload)}:null;
  function approved(sale){return sale.job_status==='Completed'&&Boolean(sqlite.prepare("SELECT id FROM work_items WHERE order_id=? AND status='Completed' LIMIT 1").get(sale.id))&&!sqlite.prepare("SELECT id FROM work_items WHERE order_id=? AND status NOT IN ('Completed','Cancelled') LIMIT 1").get(sale.id);}
  async function remote(path,{body}={}){
    check(configured,'The inventory delivery connection is not configured.',503);
    let response;try{response=await fetcher(new URL('/api/integrations/pos/'+path,url),{method:body?'POST':'GET',headers:{Authorization:'Bearer '+key,...(body?{'Content-Type':'application/json'}:{})},body:body?JSON.stringify(body):undefined,redirect:'error',signal:AbortSignal.timeout(10000)});}catch{throw Object.assign(new Error('Inventory is unreachable. The saved request will retry.'),{status:503});}
    if(!response.ok){const status=response.status,message=status===401?'Inventory rejected the integration key. Admin must check both servers.':status===404?'Inventory connector or delivery was not found. Check deployment.':status===409?'Inventory rejected a changed price, source or delivery state. Refresh and review dispatch.':status>=500?'Inventory is temporarily unavailable. The saved request will retry.':'Inventory rejected this delivery. Check its area, price and customer details.';throw Object.assign(new Error(message),{status});}
    let data;try{data=await response.json();}catch{throw Object.assign(new Error('Inventory returned an invalid response.'),{status:502});}return data;
  }
  async function catalogue(){const data=await remote('catalogue');check(data.version===2&&Array.isArray(data.branches)&&Array.isArray(data.areas),'Update the inventory connector before sending approved requests.',502);return data;}
  async function config(actor){
    check(actor.role==='admin','Administrator access required.',403);
    const result={configured,mappings:sqlite.prepare('SELECT * FROM inventory_branch_mappings').all(),branches:[],areas:[],connected:false,error:''};
    if(configured)try{Object.assign(result,await catalogue(),{connected:true});}catch(error){result.error=error.message;}
    return result;
  }
  async function saveConfig(actor,body){
    check(actor.role==='admin','Administrator access required.',403);const metadata=await catalogue();
    check(Array.isArray(body.mappings)&&body.mappings.length<=100,'Invalid branch mappings.');
    const rows=body.mappings.map(row=>({branch:text(row.branch,100),inventoryBranchId:text(row.inventoryBranchId,100)}));
    check(new Set(rows.map(r=>r.branch)).size===rows.length&&new Set(rows.map(r=>r.inventoryBranchId)).size===rows.length,'Map each branch once. Inventory branches cannot be shared.');
    for(const row of rows){check(sqlite.prepare('SELECT id FROM branches WHERE id=? AND active=1').get(row.branch),'Select an active POS branch.');check(metadata.branches.some(b=>b.id===row.inventoryBranchId),'Select an inventory branch.');}
    sqlite.exec('BEGIN IMMEDIATE');try{
      sqlite.prepare('DELETE FROM inventory_branch_mappings').run();
      for(const row of rows)sqlite.prepare('INSERT INTO inventory_branch_mappings(branch,inventory_branch_id,updated_at,updated_by) VALUES (?,?,?,?)').run(row.branch,row.inventoryBranchId,stamp(),actor.id);
      sqlite.prepare("INSERT INTO audit(id,branch,actor,action,entity,detail,created_at) VALUES (?,'',?,'inventory.branches_mapped','inventory',?,?)").run(randomUUID(),actor.id,JSON.stringify(rows),stamp());
      sqlite.exec('COMMIT');
    }catch(error){sqlite.exec('ROLLBACK');throw error;}
    return {ok:true};
  }
  async function options(sale){
    sale=root(sale);
    const branchId=mapping(sale.branch);check(branchId,'Admin must map this branch to inventory before requesting delivery.',409);
    const metadata=await catalogue();check(metadata.branches.some(b=>b.id===branchId),'The mapped inventory branch no longer exists.',409);
    return {configured,inventoryBranchId:branchId,areas:metadata.areas.filter(a=>a.name&&Number.isSafeInteger(a.chargeFils)&&a.chargeFils>=0),canMarkReady:approved(sale),delivery:unpack(get(sale.id)),deliveryInvoices:sqlite.prepare("SELECT id,bill,total,refunded_total,paid,status FROM orders WHERE parent_order_id=? AND document_type='charge' AND charge_kind='delivery' AND status NOT IN ('Voided','Refunded') AND total>refunded_total ORDER BY created_at").all(sale.id)};
  }
  function notify(row,sale,message,type='delivery'){
    const event=createHash('sha256').update(row.id+'|'+message).digest('hex'),now=stamp();
    sqlite.prepare(`INSERT OR IGNORE INTO notifications(id,member_id,order_id,branch,type,title,message,created_at,read_at)
      SELECT ?||':'||id,id,?,?,?,'Customer delivery',?,? ,'' FROM members WHERE active=1 AND role IN ('admin','manager','supervisor','reception','cashier')
      AND (role='admin' OR EXISTS(SELECT 1 FROM json_each(members.branches) WHERE value=?))`).run('delivery:'+event,sale.id,sale.branch,type,message,now,sale.branch);
  }
  function audit(actor,sale,action,detail){sqlite.prepare('INSERT INTO audit(id,branch,actor,action,entity,detail,created_at) VALUES (?,?,?,?,?,?,?)').run(randomUUID(),sale.branch,actor.id,action,sale.id,JSON.stringify(detail),stamp());}
  async function write(actor,sale,body){
    const selectedChild=sale.document_type==='charge'?sale.id:null;sale=root(sale);
    check(['admin','manager','supervisor','reception','cashier'].includes(actor.role),'Office staff access required.',403);
    check(sale.kind==='sale'&&sale.document_type==='invoice','Request delivery from the original invoice.');
    const action=text(body.action,30);let row=get(sale.id);
    if(action==='create'&&row){const saved={...JSON.parse(row.payload),deliveryInvoiceId:row.delivery_invoice_id};for(const key of ['deliveryInvoiceId','customerName','customerPhone','address','areaName','dueDate','readyTimeAt','note'])if(body[key]!==undefined)check(text(body[key],1500)===String(saved[key]??''),'A delivery draft already exists with different details. Reopen it to edit before sending.',409);return unpack(row);}
    if(['create','edit'].includes(action)){
      check(!['Voided','Refunded','Closed','Delivered'].includes(sale.status),'This invoice cannot request a new delivery.');
      if(action==='edit'){check(row,'Delivery not found.',404);check(!row.approved_at&&!row.remote_id&&row.desired_status==='draft','Sent delivery details cannot change here. Contact dispatch.',409);check(integer(body.revision,'Delivery revision')===row.revision,'This delivery changed. Refresh and try again.',409);}
      check(integer(body.version,'Invoice version')===sale.version,'The invoice changed. Refresh and try again.',409);
      const settings=await options(sale),area=settings.areas.find(a=>a.name===text(body.areaName,150));check(area,'Select an active delivery area.');
      const child=deliveryInvoice(sale,text(body.deliveryInvoiceId??selectedChild??row?.delivery_invoice_id??'',100));
      const customerName=text(body.customerName??sale.customer_name,100),customerPhone=text(body.customerPhone??sale.phone,30),address=text(body.address??sale.address,1500),dueDate=text(body.dueDate??sale.due_date,10),readyTimeAt=text(body.readyTimeAt??'',40);
      check(customerName&&/^[+\d\s()-]{5,30}$/.test(customerPhone)&&address,'Enter the customer name, phone and full address.');
      check(!dueDate||/^\d{4}-\d{2}-\d{2}$/.test(dueDate)&&Number.isFinite(Date.parse(dueDate)),'Use a valid delivery date.');
      check(!readyTimeAt||Number.isFinite(Date.parse(readyTimeAt)),'Use a valid ready time.');
      const payload={sourceOrderId:sale.id,sourceBranchId:sale.branch,fromBranchId:row?JSON.parse(row.payload).fromBranchId:settings.inventoryBranchId,invoiceNo:child.bill,deliveryInvoiceId:child.id,customerChargeFils:child.total-child.refunded_total,areaName:area.name,chargeFils:area.chargeFils,customerName,customerPhone,address,dueDate,readyTimeAt,note:text(body.note??'',1000)};
      const now=stamp();sqlite.exec('BEGIN IMMEDIATE');try{
        // The remote lookup may have taken time. Recheck financial state/version now.
        const current=invoice(sale.id);check(current.version===sale.version&&!['Voided','Refunded','Closed','Delivered'].includes(current.status),'The invoice changed. Refresh and try again.',409);
        deliveryInvoice(current,child.id);
        const latest=get(sale.id);
        if(action==='create'&&latest){sqlite.exec('COMMIT');return unpack(latest);}
        if(action==='edit'){check(latest.revision===row.revision,'The delivery changed. Refresh and try again.',409);sqlite.prepare("UPDATE customer_deliveries SET payload=?,delivery_invoice_id=?,desired_status='draft',revision=revision+1,sync_state='draft',approved_at='',approved_by=NULL,attempts=0,next_attempt='',last_error='',updated_at=? WHERE id=?").run(JSON.stringify(payload),child.id,now,row.id);}
        else sqlite.prepare("INSERT INTO customer_deliveries(id,order_id,branch,payload,delivery_invoice_id,desired_status,sync_state,created_at,updated_at,created_by) VALUES (?,?,?,?,?,'draft','draft',?,?,?)").run('pos-'+randomUUID(),sale.id,sale.branch,JSON.stringify(payload),child.id,now,now,actor.id);
        audit(actor,sale,'delivery.'+action,{area:area.name,chargeFils:area.chargeFils});sqlite.exec('COMMIT');
      }catch(error){sqlite.exec('ROLLBACK');throw error;}
      return unpack(get(sale.id));
    }
    check(row,'No delivery draft exists.',404);check(['send','ready','cancel','retry'].includes(action),'Invalid delivery action.');
    check(integer(body.revision,'Delivery revision')===row.revision,'This delivery changed. Refresh and try again.',409);
    const sending=['send','ready'].includes(action);
    if(sending){check(['admin','reception','cashier'].includes(actor.role),'Only Reception or Admin can approve and send delivery requests.',403);check(!['Voided','Refunded','Closed'].includes(sale.status)&&approved(sale),'Reception must approve every active service before sending delivery.',409);deliveryInvoice(sale,row.delivery_invoice_id);}
    if(action==='retry')check(row.approved_at,'Reception must approve the draft before it can be sent.',409);
    if(action!=='retry')check(!['in_transit','delivered','cancelled'].includes(row.remote_status)&&row.desired_status!=='cancelled','The driver has this delivery or it was already cancelled. Contact dispatch.',409);
    const desired=action==='retry'?row.desired_status:action==='cancel'?'cancelled':'ready',localCancel=action==='cancel'&&!row.approved_at&&!row.remote_id;
    sqlite.exec('BEGIN IMMEDIATE');try{sqlite.prepare("UPDATE customer_deliveries SET desired_status=?,revision=revision+1,sync_state=?,remote_status=CASE WHEN ? THEN 'cancelled' ELSE remote_status END,approved_at=?,approved_by=?,attempts=0,next_attempt='',last_error='',updated_at=? WHERE id=? AND revision=?").run(desired,localCancel?'local':'pending',localCancel?1:0,sending?stamp():row.approved_at,sending?actor.id:row.approved_by,stamp(),row.id,row.revision);check(sqlite.prepare('SELECT changes() n').get().n===1,'Delivery changed. Refresh and try again.',409);audit(actor,sale,'delivery.'+(sending?'approved':action),{deliveryInvoiceId:row.delivery_invoice_id});sqlite.exec('COMMIT');}catch(error){sqlite.exec('ROLLBACK');throw error;}
    return unpack(get(sale.id));
  }
  function snapshot(row,sale,result,revision){
    check(result.requestId===row.id&&result.fromBranchId===JSON.parse(row.payload).fromBranchId&&result.invoiceNo===JSON.parse(row.payload).invoiceNo&&['new','ready','in_transit','delivered','cancelled'].includes(result.status),'Inventory returned a mismatched delivery.',502);
    check(typeof result.id==='string'&&result.id.length<=150&&Number.isSafeInteger(result.revision)&&result.revision<=revision,'Inventory returned an invalid delivery revision.',502);
    const current=get(row.order_id),same=current.revision===revision&&result.revision===revision;
    sqlite.prepare(`UPDATE customer_deliveries SET remote_id=?,remote_status=?,driver_name=?,eta_label=?,eta_at=?,delivered_at=?,
      sync_state=CASE WHEN desired_status='draft' THEN 'draft' WHEN revision=? AND ? THEN 'synced' ELSE sync_state END,
      last_error=CASE WHEN revision=? AND ? THEN '' ELSE last_error END,next_attempt=?,updated_at=? WHERE id=?`).run(result.id,result.status,text(result.driverName??'',100),text(result.etaLabel??'',100),text(result.etaAt??'',40),text(result.deliveredAt??'',40),revision,same?1:0,revision,same?1:0,new Date(Date.now()+30000).toISOString(),stamp(),row.id);
    if(row.remote_status!==result.status||row.driver_name!==(result.driverName||'')||row.eta_label!==(result.etaLabel||''))notify(row,sale,`Invoice ${sale.bill}: delivery ${result.status.replaceAll('_',' ')}${result.driverName?' · '+text(result.driverName,100):''}${result.etaLabel?' · ETA '+text(result.etaLabel,100):''}.`);
  }
  async function process(row){
    const sale=invoice(row.order_id);if(!sale)return;
    const child=row.delivery_invoice_id?invoice(row.delivery_invoice_id):null;
    if((['Voided','Refunded'].includes(sale.status)||(child&&['Voided','Refunded'].includes(child.status)))&&!['cancelled','delivered'].includes(row.remote_status)&&row.desired_status!=='cancelled'){
      if(!row.approved_at&&!row.remote_id){sqlite.prepare("UPDATE customer_deliveries SET desired_status='cancelled',remote_status='cancelled',sync_state='local',revision=revision+1 WHERE id=?").run(row.id);return;}
      sqlite.prepare("UPDATE customer_deliveries SET desired_status='cancelled',revision=revision+1,sync_state='pending',next_attempt='' WHERE id=?").run(row.id);row=get(row.order_id);
    }else if(row.desired_status==='ready'&&row.approved_at&&!approved(sale)&&!['in_transit','delivered'].includes(row.remote_status)){
      sqlite.prepare("UPDATE customer_deliveries SET desired_status='draft',approved_at='',approved_by=NULL,revision=revision+1,sync_state='draft',next_attempt='' WHERE id=?").run(row.id);row=get(row.order_id);
    }
    if(row.desired_status==='draft'&&!row.remote_id)return;
    if(!row.approved_at&&!row.remote_id)return;
    try{
      if(row.sync_state==='attention'){
        const result=await remote('deliveries/'+encodeURIComponent(row.id));snapshot(row,sale,result,row.revision);return;
      }
      const holding=row.desired_status==='draft';
      const result=holding&&row.remote_status==='new'||row.sync_state==='synced'?await remote('deliveries/'+encodeURIComponent(row.id)):await remote('deliveries',{body:{...JSON.parse(row.payload),requestId:row.id,revision:row.revision,desiredStatus:holding?'new':row.desired_status,approvedAt:row.approved_at,approvedBy:row.approved_by??''}});
      // A completed HTTP response can arrive after a newer user edit. Do not mark that edit synced.
      snapshot(row,sale,result,row.revision);
    }catch(error){
      const current=get(row.order_id);if(current.revision!==row.revision)return;
      const attempts=row.attempts+1,attention=error.status>=400&&error.status<500&&error.status!==429;
      sqlite.prepare('UPDATE customer_deliveries SET sync_state=?,last_error=?,attempts=?,next_attempt=?,updated_at=? WHERE id=? AND revision=?').run(attention?'attention':'retry',error.status?error.message:'Delivery synchronization failed.',attempts,new Date(Date.now()+Math.min(3600000,15000*2**Math.min(attempts-1,8))).toISOString(),stamp(),row.id,row.revision);
      if(row.last_error!==error.message)notify(row,sale,`Invoice ${sale.bill}: delivery needs attention. ${error.status?error.message:'Synchronization failed.'}`);
    }
  }
  function flush(){if(!configured)return Promise.resolve();if(running)return running;running=(async()=>{const rows=sqlite.prepare("SELECT d.* FROM customer_deliveries d JOIN orders o ON o.id=d.order_id LEFT JOIN orders fee ON fee.id=d.delivery_invoice_id WHERE d.sync_state<>'local' AND (d.desired_status<>'draft' OR d.remote_id<>'' OR o.status IN ('Voided','Refunded') OR fee.status IN ('Voided','Refunded')) AND (d.sync_state<>'synced' OR d.remote_status NOT IN ('delivered','cancelled')) AND d.next_attempt<=? ORDER BY d.next_attempt,d.created_at LIMIT 20").all(stamp());for(const row of rows)await process(row);})().finally(()=>running=null);return running;}
  if(configured&&start){timer=setInterval(()=>flush().catch(()=>{}),5000);timer.unref();}
  return {configured,config,saveConfig,options,read:sale=>unpack(get(root(sale).id)),write,flush,close:async()=>{clearInterval(timer);if(running)await running;}};
}
