import {JOB_STATUSES,canonicalRole,isManagerRole,canAccess,canReview,check,text,integer,kuwaitDay,lineValues} from './domain.ts';
import {createWorkflow,MANAGEMENT_ROLES,OFFICE_ROLES} from './workflow.ts';
import type {WorkflowDeps} from './workflow.ts';
import type {Row} from './storage.ts';

export function createTracking(deps:WorkflowDeps){
  const {all,first,stmt}=deps,{mutation}=createWorkflow(deps);
  const office=(member:Row)=>check(OFFICE_ROLES.includes(canonicalRole(member.role)),'Reception or administrator access required.',403);
  async function scope(member:Row,url:URL){
    const multi=['admin','supervisor'].includes(member.role);
    const branch=text(url.searchParams.get('branch')??(multi?'all':member.branches[0]),100);
    if(branch==='all')check(multi,'Only an administrator or supervisor can view multiple branches.',403);
    else await deps.branchAccess(member,branch,true);
    const available=await deps.branchList();
    return available.filter(b=>(branch==='all'||b.id===branch)&&canAccess(member as any,b.id,available)&&(b.active===1||member.role==='admin'));
  }
  async function validateTailor(branch:string,id:string){
    if(!id)return null;
    const target=await first('SELECT * FROM members WHERE id=? AND active=1',id);
    check(target&&target.role==='tailor'&&canAccess({...target,branches:JSON.parse(target.branches)} as any,branch,[{id:branch}]),'Select an active tailor assigned to this invoice’s branch.');return target;
  }
  async function job(member:Row,id:string){
    const row=await first("SELECT * FROM orders WHERE id=? AND kind='sale' AND status NOT IN ('Voided','Refunded')",id);
    check(row,'Job not found.',404);await deps.branchAccess(member,row.branch,true);
    if(member.role==='tailor')check(await first('SELECT id FROM work_items WHERE order_id=? AND tailor_id=?',id,member.id),'This work is not assigned to you.',403);
    return row;
  }
  async function tasks(sale:Row,member?:Row):Promise<Row[]>{
    const lines=JSON.parse(sale.lines);
    const rows=await all('SELECT w.*,m.name tailor_name,m.active tailor_active,a.name approved_name FROM work_items w LEFT JOIN members m ON m.id=w.tailor_id LEFT JOIN members a ON a.id=w.approved_by WHERE w.order_id=? ORDER BY w.line_index,w.created_at,w.id',sale.id);
    return rows.filter(w=>member?.role!=='tailor'||w.tailor_id===member.id).map(w=>({
      ...w,name:lines[w.line_index]?.name??'Service',note:lines[w.line_index]?.note??'',
      is_latest:!rows.some(other=>other.line_index===w.line_index&&other.status==='Completed'&&
        (other.approved_at>w.approved_at||(other.approved_at===w.approved_at&&other.created_at>w.created_at))),
    }));
  }
  function aggregate(rows:Row[]){
    const active=rows.filter(t=>t.status!=='Cancelled');
    if(!active.length)return 'Pending';if(active.every(t=>t.status==='Completed'))return 'Completed';
    for(const status of ['Awaiting Review','In Progress','On Hold'])if(active.some(t=>t.status===status))return status;return 'Pending';
  }
  async function publicJob(row:Row,member?:Row){
    const work=await tasks(row,member),indices=new Set(work.map(w=>w.line_index)),lines=JSON.parse(row.lines);
    const names=[...new Set(work.filter(w=>w.status!=='Cancelled').map(w=>w.tailor_name).filter(Boolean))];
    return {id:row.id,bill:row.bill,branch:row.branch,customer_name:row.customer_name,
      lines:lines.map((l:Row,i:number)=>({id:l.id,name:l.name,category:l.category,qty:l.qty,note:l.note,line_index:i})).filter((l:Row)=>!member||member.role!=='tailor'||indices.has(l.line_index)),
      tasks:work,notes:row.notes,due_date:row.due_date,tailor_id:row.tailor_id,tailor_name:names.join(', '),
      unassigned_count:work.filter(w=>!w.tailor_id&&w.status!=='Cancelled').length,
      review_count:work.filter(w=>w.status==='Awaiting Review').length,
      job_status:member?.role==='tailor'?aggregate(work):row.job_status,assigned_at:row.assigned_at,job_updated_at:row.job_updated_at,created_at:row.created_at,version:row.version};
  }
  async function read(member:Row,id:string|undefined,url:URL){
    if(id){
      const row=await job(member,id),result=await publicJob(row,member),own=new Set(result.tasks.map(w=>w.id));
      const events=(await all('SELECT actor_name,action,detail,created_at FROM job_events WHERE order_id=? ORDER BY created_at DESC,id DESC LIMIT 200',id)).filter(e=>{
        if(member.role!=='tailor')return true;const detail=JSON.parse(e.detail);return e.action.startsWith('work.')&&Array.isArray(detail.taskIds)&&detail.taskIds.some((task:string)=>own.has(task));
      });
      return {job:result,events,attachments:await all('SELECT id,name,type FROM attachments WHERE order_id=?',id)};
    }
    const branches=await scope(member,url),args:any[]=branches.map(b=>b.id);
    let where=`o.kind='sale' AND o.status NOT IN ('Voided','Refunded') AND o.branch IN (${args.map(()=>'?').join(',')||'NULL'}) AND EXISTS(SELECT 1 FROM work_items w WHERE w.order_id=o.id AND w.status<>'Cancelled')`;
    const own=member.role==='tailor'?' AND w.tailor_id=?':'';
    if(own){where+=" AND EXISTS(SELECT 1 FROM work_items w WHERE w.order_id=o.id AND w.tailor_id=? AND w.status<>'Cancelled')";args.push(member.id);}
    const summary=await first(`SELECT COUNT(*) total,COALESCE(SUM(w.tailor_id IS NULL AND w.status<>'Cancelled'),0) unassigned,COALESCE(SUM(w.status='Pending'),0) pending,COALESCE(SUM(w.status='In Progress'),0) in_progress,COALESCE(SUM(w.status='On Hold'),0) on_hold,COALESCE(SUM(w.status='Awaiting Review'),0) awaiting_review,COALESCE(SUM(w.status='Completed'),0) completed,COALESCE(SUM(w.kind='backjob' AND w.status NOT IN ('Completed','Cancelled')),0) backjobs,COALESCE(SUM(w.status NOT IN ('Completed','Cancelled') AND o.due_date<>'' AND o.due_date<?),0) overdue FROM work_items w JOIN orders o ON o.id=w.order_id WHERE ${where}${own}`,kuwaitDay(),...args,...(own?[member.id]:[]));
    const status=text(url.searchParams.get('status'),30);
    if(status){check(['Unassigned','Backjobs',...JOB_STATUSES].includes(status),'Invalid job status.');where+=` AND EXISTS(SELECT 1 FROM work_items w WHERE w.order_id=o.id${own} AND ${status==='Unassigned'?"w.tailor_id IS NULL AND w.status<>'Cancelled'":status==='Backjobs'?"w.kind='backjob' AND w.status<>'Cancelled'":'w.status=?'})`;if(own)args.push(member.id);if(!['Unassigned','Backjobs'].includes(status))args.push(status);}
    const query=text(url.searchParams.get('q'),100);if(query){where+=" AND instr(lower(o.bill||' '||o.customer_name),lower(?))>0";args.push(query);}
    const matched=await first(`SELECT COUNT(*) count FROM orders o WHERE ${where}`,...args),offset=integer(Number(url.searchParams.get('offset')??0),'Offset',0,1_000_000);
    const rows=await all(`SELECT o.* FROM orders o WHERE ${where} ORDER BY (o.job_status='Completed'),(o.due_date=''),o.due_date,o.created_at LIMIT 500 OFFSET ?`,...args,offset);
    return {jobs:await Promise.all(rows.map(row=>publicJob(row,member))),summary,limit:500,offset,matched:matched?.count??0};
  }
  function initialTasks(id:string,branch:string,lines:Row[],tailorId:string,time:string){return lines.map((l,i)=>stmt('INSERT INTO work_items(id,order_id,line_index,quantity,tailor_id,status,kind,created_at,updated_at) VALUES (?,?,?,?,?,\'Pending\',\'original\',?,?)',`${id}:line:${i}`,id,i,l.qty,tailorId||null,time,time));}
  // Legacy event helper remains for initial invoice assignment; mutations below use guarded transactions.
  function event(member:Row,sale:Row,action:string,detail:string,conditional=false,eventId=crypto.randomUUID() as string){return stmt('INSERT INTO job_events(id,order_id,branch,actor,actor_name,action,detail,created_at) SELECT ?,?,?,?,?,?,?,?'+(conditional?' WHERE changes()=1':''),eventId,sale.id,sale.branch,member.id,member.name,action,detail,new Date().toISOString());}
  async function selectedTasks(sale:Row,member:Row,body:Row,defaultFilter:(w:Row)=>boolean){
    const rows=await tasks(sale),ids=body.taskIds;
    check(ids===undefined||(Array.isArray(ids)&&ids.length>0&&ids.length<=200&&new Set(ids).size===ids.length),'Select services.');
    const chosen=ids?rows.filter(w=>ids.includes(w.id)):rows.filter(defaultFilter);
    check(chosen.length>0&&(!ids||chosen.length===ids.length),'Selected services are unavailable.');
    if(member.role==='tailor')check(chosen.every(w=>w.tailor_id===member.id),'Only your assigned services can be updated.',403);
    return chosen;
  }
  async function assign(member:Row,sale:Row,body:Row){
    office(member);await deps.branchAccess(member,sale.branch);check(!['Voided','Refunded'].includes(sale.status),'This invoice cannot be assigned.');
    const chosen=await selectedTasks(sale,member,body,w=>!['Completed','Cancelled'].includes(w.status));
    check(chosen.every(w=>!['Completed','Cancelled'].includes(w.status)),'Approved work is retained. Create a backjob for rework.');
    const tailorId=text(body.tailorId,100),reason=text(body.reason,2000);await validateTailor(sale.branch,tailorId);
    if(chosen.every(w=>(w.tailor_id??'')===tailorId))return;
    check(!chosen.some(w=>w.tailor_id&&w.status!=='Pending')||reason.length>=3,'Enter a reason when reassigning work that has started.');
    const m=mutation(member,sale,body.version,'work.assigned',{taskIds:chosen.map(w=>w.id),to:tailorId,note:reason});
    const changes=chosen.map(w=>m.update('work_items',"tailor_id=?,status='Pending',approved_by=NULL,approved_at='',version=version+1,updated_at=?",[tailorId||null,m.time],'id=?',w.id));
    await m.save([...changes,m.update('orders','assigned_at=?',[tailorId?m.time:''],'id=?',sale.id),...(tailorId?chosen.map(w=>m.assigned(w.id)):[]),m.sync()]);
  }
  async function progress(member:Row,id:string,body:Row){
    const sale=await job(member,id),action=text(body.action,30),note=text(body.note,2000);
    await deps.branchAccess(member,sale.branch);
    if(action==='backjob'){
      check(['admin','reception','cashier'].includes(member.role),'Reception creates backjob orders.',403);
      const parent=(await tasks(sale)).find(w=>w.id===body.parentTaskId);
      check(parent&&parent.status==='Completed'&&parent.tailor_id&&parent.is_latest,'Select the latest approved work for this service.');
      check(!await first("SELECT id FROM work_items WHERE order_id=? AND line_index=? AND kind='backjob' AND status NOT IN ('Completed','Cancelled')",id,parent.line_index),'This service already has an open backjob.');
      const refunded=await first("SELECT COALESCE(SUM(json_extract(j.value,'$.qty')),0) quantity FROM orders d,json_each(d.lines) j WHERE d.parent_order_id=? AND d.document_type IN ('refund','cancellation') AND json_extract(j.value,'$.original_line_index')=?",id,parent.line_index);
      const available=JSON.parse(sale.lines)[parent.line_index].qty-(refunded?.quantity??0),maximum=Math.min(parent.quantity,available);
      check(maximum>0,'This service was fully refunded.');
      const quantity=integer(body.quantity??maximum,'Backjob quantity',1,maximum),fault=text(body.fault,20),tailorId=text(body.tailorId,100);
      check(['tailor','no_fault'].includes(fault),'Select whether the previous tailor was at fault.');check(note.length>=3,'Enter the backjob reason.');check(tailorId,'Choose the fixing tailor.');await validateTailor(sale.branch,tailorId);
      const taskId=crypto.randomUUID(),m=mutation(member,sale,body.version,'work.backjob',{taskIds:[taskId],parentTaskId:parent.id,fault,note,previousDeliveryStatus:sale.status});
      await m.save([m.insert('work_items',{id:taskId,order_id:id,line_index:parent.line_index,quantity,tailor_id:tailorId,status:'Pending',kind:'backjob',parent_task_id:parent.id,fault,fault_tailor_id:fault==='tailor'?parent.tailor_id:null,reason:note,approved_by:null,approved_at:'',created_at:m.time,updated_at:m.time,version:0}),m.update('orders',"status='Ongoing'",[],'id=?',id),m.assigned(taskId),m.notify('backjob','Backjob created','A backjob was opened for invoice '+sale.bill+'.',MANAGEMENT_ROLES),m.sync()]);
      return publicJob((await job(member,id))!,member);
    }
    check(['progress','note','review'].includes(action),'Invalid tracking action.');
    if(action==='review')check(canReview(member as any),'Reception must check the finished services.',403);
    else check(member.role==='tailor'||isManagerRole(member.role),'Only the assigned tailor or a manager can update work progress.',403);
    const chosen=await selectedTasks(sale,member,body,w=>w.tailor_id&&w.status!=='Cancelled'&&(member.role!=='tailor'||w.tailor_id===member.id)&&(action!=='review'||w.status==='Awaiting Review'));
    check((await first('SELECT version FROM orders WHERE id=?',id))?.version===body.version,'This invoice changed. Refresh and try again.',409);
    check(chosen.every(w=>w.tailor_id&&w.status!=='Cancelled'),'Assign the selected services to a tailor first.');
    let status=action==='review'?(body.approved===false?'In Progress':'Completed'):text(body.status,30);
    if(action==='note')check(note.length>0,'Enter a progress note.');
    else if(action==='review'){check(chosen.every(w=>w.status==='Awaiting Review'),'This work was already checked or changed. Refresh and try again.',409);if(body.approved===false)check(note.length>=3,'Explain what needs correcting.');}
    else{
      check(JOB_STATUSES.includes(status)&&status!=='Completed','Submit finished work for reception review before completion.',403);
      const transitions:Record<string,string[]>={'Pending':['In Progress','On Hold'],'In Progress':['On Hold','Awaiting Review'],'On Hold':['In Progress'],'Awaiting Review':[],'Completed':[]};
      check(chosen.every(w=>transitions[w.status]?.includes(status)),'Use the next work status. Approved work requires a backjob.');
    }
    const m=mutation(member,sale,body.version,'work.'+action,{taskIds:chosen.map(w=>w.id),to:action==='note'?'':status,note});
    const operations=[];
    if(action!=='note')for(const w of chosen){
      operations.push(m.update('work_items','status=?,approved_by=?,approved_at=?,version=version+1,updated_at=?',[status,status==='Completed'?member.id:null,status==='Completed'?m.time:'',m.time],'id=? AND version=?',w.id,w.version));
      if(status==='Completed'){
        const line=JSON.parse(sale.lines)[w.line_index],amount=Math.floor(lineValues(sale)[w.line_index]*w.quantity/line.qty);
        if(w.kind==='backjob'&&w.fault==='tailor'){
          const credit=await first('SELECT COALESCE(SUM(quantity),0) quantity,COALESCE(SUM(amount),0) amount FROM work_credits WHERE order_id=? AND line_index=? AND tailor_id=?',id,w.line_index,w.fault_tailor_id);
          if(credit&&credit.quantity>0){const revoked=Math.min(credit.quantity,w.quantity);operations.push(m.insert('work_credits',{id:crypto.randomUUID(),task_id:w.id,order_id:id,line_index:w.line_index,tailor_id:w.fault_tailor_id,quantity:-revoked,amount:-Math.floor(credit.amount*revoked/credit.quantity),reason:'fault_reversal',created_at:m.time}));}
        }
        operations.push(m.insert('work_credits',{id:crypto.randomUUID(),task_id:w.id,order_id:id,line_index:w.line_index,tailor_id:w.tailor_id,quantity:w.quantity,amount,reason:w.kind==='backjob'?'backjob':'approved',created_at:m.time}));
      }
    }
    if(status==='Awaiting Review'&&action==='progress')operations.push(m.notify('review','Reception check needed','Finished services on invoice '+sale.bill+' need reception approval.',OFFICE_ROLES));
    if(status==='Completed')operations.push(m.notify('completed','Work approved','Reception approved services on invoice '+sale.bill+'.',MANAGEMENT_ROLES));
    if(status==='On Hold')operations.push(m.notify('on_hold','Job put on hold','Work on invoice '+sale.bill+' was put on hold.',OFFICE_ROLES));
    if(action==='review'&&body.approved===false)operations.push(...chosen.map(w=>m.assigned(w.id)));
    await m.save([...operations,m.sync()]);return publicJob((await job(member,id))!,member);
  }
  async function dashboard(member:Row,url:URL,start:string,end:string){
    office(member);const branches=await scope(member,url),args=branches.map(b=>b.id),filter=` AND branch IN (${args.map(()=>'?').join(',')||'NULL'})`;
    const invoices=await all(`SELECT branch,COUNT(*) invoices,COALESCE(SUM(total-refunded_total),0) total,COALESCE(SUM(paid),0) paid,COALESCE(SUM(total-refunded_total-paid),0) due FROM orders WHERE kind='sale' AND status NOT IN ('Voided','Refunded') AND created_at BETWEEN ? AND ?${filter} GROUP BY branch`,start,end,...args);
    const received=await all(`SELECT branch,SUM(amount) received FROM payments WHERE created_at BETWEEN ? AND ?${filter} GROUP BY branch`,start,end,...args);
    const expenses=await all(`SELECT branch,SUM(amount) expenses FROM expenses WHERE created_at BETWEEN ? AND ?${filter} GROUP BY branch`,start,end,...args);
    const jobs=await all(`SELECT branch,SUM(EXISTS(SELECT 1 FROM work_items w WHERE w.order_id=o.id AND w.tailor_id IS NULL AND w.status<>'Cancelled')) unassigned,SUM(job_status!='Completed') open_jobs,SUM(job_status='Completed') completed FROM orders o WHERE kind='sale' AND document_type='invoice' AND status NOT IN ('Voided','Refunded')${filter} GROUP BY branch`,...args);
    const rows=branches.map(b=>({id:b.id,name:b.name,active:b.active,invoices:0,total:0,paid:0,due:0,received:0,expenses:0,unassigned:0,open_jobs:0,completed:0,...invoices.find(r=>r.branch===b.id),...received.find(r=>r.branch===b.id),...expenses.find(r=>r.branch===b.id),...jobs.find(r=>r.branch===b.id)})).filter(b=>b.active===1||b.invoices||b.received||b.expenses||b.open_jobs||b.completed);
    const totals=Object.fromEntries(['invoices','total','paid','due','received','expenses','unassigned','open_jobs','completed'].map(k=>[k,rows.reduce((n,r)=>n+Number((r as Row)[k]??0),0)]));
    const ops=await first(`SELECT SUM(document_type='refund') refunds,SUM(document_type='cancellation') cancellations,COALESCE(SUM(CASE WHEN document_type='refund' THEN total ELSE 0 END),0) refund_value FROM orders WHERE created_at BETWEEN ? AND ?${filter}`,start,end,...args);
    const work=await first(`SELECT SUM(w.status='Awaiting Review') awaiting_review,SUM(w.kind='backjob' AND w.status NOT IN ('Completed','Cancelled')) open_backjobs,SUM(w.kind='backjob' AND w.created_at BETWEEN ? AND ?) backjobs FROM work_items w JOIN orders o ON o.id=w.order_id WHERE o.status NOT IN ('Voided','Refunded')${filter}`,start,end,...args);
    const credits=await all(`SELECT m.id,m.name,SUM(c.quantity) quantity,SUM(c.amount) amount,SUM(CASE WHEN c.reason='backjob' THEN c.quantity ELSE 0 END) backjob_quantity FROM work_credits c JOIN orders o ON o.id=c.order_id JOIN members m ON m.id=c.tailor_id WHERE c.created_at BETWEEN ? AND ?${filter} GROUP BY m.id ORDER BY amount DESC`,start,end,...args);
    return {branches:rows,totals,operations:{...ops,...work},tailorPerformance:credits};
  }
  async function exceptions(member:Row,url:URL,start:string,end:string){
    office(member);const type=text(url.searchParams.get('type'),30);check(['refund','cancellation'].includes(type),'Choose refunds or cancellations.');
    const branches=await scope(member,url),ids=branches.map(b=>b.id);
    return {items:await all(`SELECT d.id,d.bill,d.branch,d.total,d.reason,d.reason_code,d.created_at,d.document_type,p.bill parent_bill FROM orders d JOIN orders p ON p.id=d.parent_order_id WHERE d.document_type=? AND d.created_at BETWEEN ? AND ? AND d.branch IN (${ids.map(()=>'?').join(',')||'NULL'}) ORDER BY d.created_at DESC LIMIT 500`,type,start,end,...ids)};
  }
  return {office,validateTailor,read,job,publicJob,event,assign,progress,dashboard,exceptions,initialTasks,tasks};
}
