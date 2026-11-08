import {JOB_STATUSES,canonicalRole,isManagerRole,canAccess,check,text,integer,kuwaitDay} from './domain.ts';
import type {Database, Statement, Row} from './storage.ts';
import type {createNotifications} from './notifications.ts';
export function createTracking(deps:{all:(sql:string,...args:any[])=>Promise<Row[]>;first:(sql:string,...args:any[])=>Promise<Row|null>;stmt:(sql:string,...args:any[])=>Statement;db:()=>Database;log:(branch:string,actor:Row,action:string,id:string,detail?:string,conditional?:boolean)=>Statement;notifications:ReturnType<typeof createNotifications>;branchList:()=>Promise<Row[]>;branchAccess:(member:Row,branch:string,historical?:boolean)=>Promise<Row>}){
  const {all,first,stmt,db,log}=deps;
  const office=(member:Row)=>check(['admin','manager','supervisor','reception'].includes(canonicalRole(member.role)),'Reception or administrator access required.',403);
  async function scope(member:Row,url:URL){
    const multi=member.role==='admin'||member.role==='supervisor';
    const branch=text(url.searchParams.get('branch')??(multi?'all':member.branches[0]),100);
    if(branch==='all')check(multi,'Only an administrator or supervisor can view multiple branches.',403);
    else await deps.branchAccess(member,branch,true);
    const available=await deps.branchList();
    return available.filter(b=>(branch==='all'||b.id===branch)&&canAccess(member as any,b.id,available)&&(b.active===1||member.role==='admin'));
  }
  async function validateTailor(branch:string,id:string){
    if(!id)return null;
    const target=await first('SELECT * FROM members WHERE id=? AND active=1',id);
    check(target&&canonicalRole(target.role)==='tailor'&&canAccess({...target,branches:JSON.parse(target.branches)} as any,branch,[{id:branch}]),'Select an active tailor assigned to this invoice’s branch.',400);
    return target;
  }
  function publicJob(row:Row){return {
    id:row.id,bill:row.bill,branch:row.branch,customer_name:row.customer_name,
    lines:JSON.parse(row.lines).map((l:Row)=>({id:l.id,name:l.name,category:l.category,qty:l.qty,note:l.note})),
    notes:row.notes,due_date:row.due_date,tailor_id:row.tailor_id,tailor_name:row.tailor_name??'',tailor_active:row.tailor_active??null,
    job_status:row.job_status,assigned_at:row.assigned_at,job_updated_at:row.job_updated_at,created_at:row.created_at,version:row.version,
  };}
  async function job(member:Row,id:string){
    const row=await first("SELECT o.*,m.name tailor_name,m.active tailor_active FROM orders o LEFT JOIN members m ON m.id=o.tailor_id WHERE o.id=? AND o.kind='sale' AND o.status NOT IN ('Voided','Refunded')",id);
    check(row,'Job not found.',404);await deps.branchAccess(member,row.branch,true);
    if(member.role==='tailor')check(row.tailor_id===member.id,'This job is not assigned to you.',403);
    return row;
  }
  async function read(member:Row,id:string|undefined,url:URL){
    if(id){const row=await job(member,id);return {job:publicJob(row),events:await all('SELECT actor_name,action,detail,created_at FROM job_events WHERE order_id=? ORDER BY created_at DESC,id DESC LIMIT 100',id),attachments:await all('SELECT id,name,type FROM attachments WHERE order_id=?',id)};}
    const branches=await scope(member,url),args:any[]=branches.map(b=>b.id);
    let where=`o.kind='sale' AND o.status NOT IN ('Voided','Refunded') AND o.branch IN (${args.map(()=>'?').join(',')||'NULL'})`;
    if(member.role==='tailor'){where+=' AND o.tailor_id=?';args.push(member.id);}
    const counts=await first(`SELECT COUNT(*) total,COALESCE(SUM(o.tailor_id IS NULL),0) unassigned,COALESCE(SUM(o.job_status='Pending'),0) pending,COALESCE(SUM(o.job_status='In Progress'),0) in_progress,COALESCE(SUM(o.job_status='On Hold'),0) on_hold,COALESCE(SUM(o.job_status='Completed'),0) completed,COALESCE(SUM(o.job_status!='Completed' AND o.due_date!='' AND o.due_date<?),0) overdue FROM orders o WHERE ${where}`,kuwaitDay(),...args);
    const status=text(url.searchParams.get('status'),30);
    if(status==='Unassigned')where+=' AND o.tailor_id IS NULL';else if(status){check(JOB_STATUSES.includes(status),'Invalid job status.');where+=' AND o.job_status=?';args.push(status);}
    const query=text(url.searchParams.get('q'),100);
    if(query){where+=" AND instr(lower(o.bill||' '||o.customer_name),lower(?))>0";args.push(query);}
    const matched=await first(`SELECT COUNT(*) count FROM orders o WHERE ${where}`,...args);
    const offset=integer(Number(url.searchParams.get('offset')??0),'Offset',0,1_000_000);
    const rows=await all(`SELECT o.*,m.name tailor_name,m.active tailor_active FROM orders o LEFT JOIN members m ON m.id=o.tailor_id WHERE ${where} ORDER BY (o.job_status='Completed'),(o.due_date=''),o.due_date,o.created_at LIMIT 500 OFFSET ?`,...args,offset);
    return {jobs:rows.map(publicJob),summary:counts,limit:500,offset,matched:matched?.count??0};
  }
  function event(member:Row,sale:Row,action:string,detail:string,conditional=false,eventId=crypto.randomUUID() as string){return stmt('INSERT INTO job_events (id,order_id,branch,actor,actor_name,action,detail,created_at) SELECT ?,?,?,?,?,?,?,?'+(conditional?' WHERE changes()=1':''),eventId,sale.id,sale.branch,member.id,member.name,action,detail,new Date().toISOString());}
  async function assign(member:Row,sale:Row,body:Row){
    office(member);await deps.branchAccess(member,sale.branch);
    check(sale.kind==='sale'&&!['Voided','Refunded'].includes(sale.status),'This invoice cannot be assigned.');
    const id=text(body.tailorId,100),reason=text(body.reason,1000);await validateTailor(sale.branch,id);
    if((sale.tailor_id??'')===id)return;
    check(!sale.tailor_id||sale.job_status==='Pending'||reason.length>=3,'Enter a reason when reassigning work that has already started.');
    const detail=JSON.stringify({from:sale.tailor_id??'',to:id,previousStatus:sale.job_status,note:reason}),time=new Date().toISOString();
    const result=await db().batch([
      stmt("UPDATE orders SET tailor_id=?,assigned_at=?,job_status='Pending',job_updated_at=?,updated_at=?,version=version+1 WHERE id=? AND branch=? AND version=? RETURNING id",id||null,id?time:'',time,time,sale.id,sale.branch,integer(body.version,'Version')),
      event(member,sale,'assigned',detail,true,`assigned:${sale.id}:${body.version+1}`),log(sale.branch,member,'job.assigned',sale.id,detail,true),
      deps.notifications.assigned(sale.id,body.version+1,member.id),
    ]);check(result[0].results.length,'This invoice changed. Refresh and try again.',409);
  }
  async function progress(member:Row,id:string,body:Row){
    check(member.role==='tailor'||isManagerRole(member.role),'Only the assigned tailor or a manager can update work progress.',403);
    const sale=await job(member,id);check(sale.tailor_id,'Assign a tailor before updating work.');
    const version=integer(body.version,'Version'),action=text(body.action,30),note=text(body.note,2000);
    check(version===sale.version,'This job was updated or reassigned. Refresh and try again.',409);
    check(['progress','note'].includes(action),'Invalid tracking action.');
    const status=action==='note'?sale.job_status:text(body.status,30);check(JOB_STATUSES.includes(status),'Invalid job status.');
    if(action==='note')check(note.length>0,'Enter a progress note.');
    else{
      const transitions:Record<string,string[]>={'Pending':['In Progress','On Hold'],'In Progress':['On Hold','Completed'],'On Hold':['In Progress'],'Completed':[]};
      check(transitions[sale.job_status]?.includes(status)||(isManagerRole(member.role)&&note.length>=3),'Use the next work status, or add a manager’s reason for a correction.');
    }
    const detail=JSON.stringify({from:sale.job_status,to:status,note}),time=new Date().toISOString();
    const result=await db().batch([
      stmt('UPDATE orders SET job_status=?,job_updated_at=?,updated_at=?,version=version+1 WHERE id=? AND version=? AND tailor_id=? RETURNING id',status,time,time,sale.id,version,sale.tailor_id),
      event(member,sale,action,detail,true,`${action}:${sale.id}:${version+1}`),log(sale.branch,member,`job.${action}`,sale.id,detail,true),
      ...(['Completed','On Hold'].includes(status)&&action==='progress'?[deps.notifications.progress(sale.id,version+1,status,member.id)]:[]),
    ]);check(result[0].results.length,'This job was updated or reassigned. Refresh and try again.',409);
    return publicJob((await job(member,id))!);
  }
  async function dashboard(member:Row,url:URL,start:string,end:string){
    office(member);const branches=await scope(member,url),args=branches.map(b=>b.id),filter=` AND branch IN (${args.map(()=>'?').join(',')||'NULL'})`;
    const invoices=await all(`SELECT branch,COUNT(*) invoices,COALESCE(SUM(total),0) total,COALESCE(SUM(paid),0) paid,COALESCE(SUM(total-paid),0) due FROM orders WHERE kind='sale' AND status NOT IN ('Voided','Refunded') AND created_at BETWEEN ? AND ?${filter} GROUP BY branch`,start,end,...args);
    const received=await all(`SELECT branch,SUM(amount) received FROM payments WHERE created_at BETWEEN ? AND ?${filter} GROUP BY branch`,start,end,...args);
    const expenses=await all(`SELECT branch,SUM(amount) expenses FROM expenses WHERE created_at BETWEEN ? AND ?${filter} GROUP BY branch`,start,end,...args);
    const jobs=await all(`SELECT branch,SUM(tailor_id IS NULL) unassigned,SUM(job_status!='Completed') open_jobs,SUM(job_status='Completed') completed FROM orders WHERE kind='sale' AND status NOT IN ('Voided','Refunded')${filter} GROUP BY branch`,...args);
    const rows=branches.map(b=>({id:b.id,name:b.name,active:b.active,invoices:0,total:0,paid:0,due:0,received:0,expenses:0,unassigned:0,open_jobs:0,completed:0,...invoices.find(r=>r.branch===b.id),...received.find(r=>r.branch===b.id),...expenses.find(r=>r.branch===b.id),...jobs.find(r=>r.branch===b.id)})).filter(b=>b.active===1||b.invoices||b.received||b.expenses||b.open_jobs||b.completed);
    const totals=Object.fromEntries(['invoices','total','paid','due','received','expenses','unassigned','open_jobs','completed'].map(k=>[k,rows.reduce((n,r)=>n+Number((r as Row)[k]??0),0)]));
    return {branches:rows,totals};
  }
  return {office,validateTailor,read,job,publicJob,event,assign,progress,dashboard};
}
