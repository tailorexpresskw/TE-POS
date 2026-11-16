import {check,integer} from './domain.ts';
import type {Database,Row,Statement} from './storage.ts';

export type WorkflowDeps={
  all:(sql:string,...args:any[])=>Promise<Row[]>;first:(sql:string,...args:any[])=>Promise<Row|null>;
  stmt:(sql:string,...args:any[])=>Statement;db:()=>Database;
  branchList:()=>Promise<Row[]>;branchAccess:(member:Row,branch:string,historical?:boolean)=>Promise<Row>;
};
export function createWorkflow(deps:WorkflowDeps){
  const {stmt,db}=deps;
  function mutation(member:Row,sale:Row,version:number,action:string,detail:Row={}){
    integer(version,'Version');check(version===sale.version,'This invoice changed. Refresh and try again.',409);
    const id=crypto.randomUUID(),time=new Date().toISOString();
    // Every side effect is tied to this transaction's successful compare-and-swap event.
    const guard=`EXISTS (SELECT 1 FROM job_events WHERE id='${id}')`;
    const insert=(table:string,row:Row)=>stmt(`INSERT INTO ${table} (${Object.keys(row).join(',')}) SELECT ${Object.keys(row).map(()=>'?').join(',')} WHERE ${guard}`,...Object.values(row));
    const update=(table:string,sql:string,args:any[],where:string,...whereArgs:any[])=>stmt(`UPDATE ${table} SET ${sql} WHERE (${where}) AND ${guard}`,...args,...whereArgs);
    const operations:Statement[]=[
      stmt('UPDATE orders SET version=version+1,updated_at=? WHERE id=? AND version=? RETURNING id',time,sale.id,version),
      stmt('INSERT INTO job_events(id,order_id,branch,actor,actor_name,action,detail,created_at) SELECT ?,?,?,?,?,?,?,? WHERE changes()=1',id,sale.id,sale.branch,member.id,member.name,action,JSON.stringify(detail),time),
      insert('audit',{id,branch:sale.branch,actor:member.id,action,entity:sale.id,detail:JSON.stringify(detail),created_at:time}),
      insert('integration_events',{id,order_id:sale.id,branch:sale.branch,type:action,payload:JSON.stringify({orderId:sale.id,bill:sale.bill,branch:sale.branch,...detail}),created_at:time,processed_at:''}),
    ];
    function notify(type:string,title:string,message:string,roles:string[],taskId?:string){
      return stmt(`INSERT INTO notifications(id,member_id,order_id,branch,type,title,message,created_at,read_at,task_id)
        SELECT ?||':'||m.id,m.id,?,?,?,?,?,?,'',? FROM members m
        WHERE m.active=1 AND m.role IN (${roles.map(()=>'?').join(',')})
        AND (m.role='admin' OR EXISTS(SELECT 1 FROM json_each(m.branches) WHERE value=?)) AND ${guard}`,
        id+':'+type,sale.id,sale.branch,type,title,message,time,taskId??null,...roles,sale.branch);
    }
    function assigned(taskId:string,type='assigned'){return stmt(`INSERT INTO notifications(id,member_id,order_id,branch,type,title,message,created_at,read_at,task_id)
      SELECT ?||':'||w.id||':'||m.id,m.id,w.order_id,?,?,?, ?,?,'',w.id
      FROM work_items w JOIN members m ON m.id=w.tailor_id WHERE w.id=? AND m.active=1 AND m.role='tailor'
      AND EXISTS(SELECT 1 FROM json_each(m.branches) WHERE value=?) AND ${guard}`,id,sale.branch,type,type==='work_cancelled'?'Assigned work cancelled':type==='work_changed'?'Assigned quantity updated':'New tailor assignment',type==='assigned'?'Work on invoice '+sale.bill+' has been assigned to you.':'Your assigned work on invoice '+sale.bill+' changed. Open the POS for details.',time,taskId,sale.branch);}
    function sync(){return update('orders',`job_status=CASE
      WHEN NOT EXISTS(SELECT 1 FROM work_items w WHERE w.order_id=orders.id AND w.status<>'Cancelled') THEN 'Pending'
      WHEN NOT EXISTS(SELECT 1 FROM work_items w WHERE w.order_id=orders.id AND w.status NOT IN ('Completed','Cancelled')) THEN 'Completed'
      WHEN EXISTS(SELECT 1 FROM work_items w WHERE w.order_id=orders.id AND w.status='Awaiting Review') THEN 'Awaiting Review'
      WHEN EXISTS(SELECT 1 FROM work_items w WHERE w.order_id=orders.id AND w.status='In Progress') THEN 'In Progress'
      WHEN EXISTS(SELECT 1 FROM work_items w WHERE w.order_id=orders.id AND w.status='On Hold') THEN 'On Hold' ELSE 'Pending' END,
      tailor_id=(SELECT CASE WHEN COUNT(DISTINCT w.tailor_id)=1 AND SUM(w.tailor_id IS NULL)=0 THEN MIN(w.tailor_id) ELSE NULL END FROM work_items w WHERE w.order_id=orders.id AND w.status<>'Cancelled'),job_updated_at=?`,[time],'id=?',sale.id);}
    async function save(extra:Statement[]=[]){const result=await db().batch([...operations,...extra]);check(result[0].results.length,'This invoice changed. Refresh and try again.',409);}
    return {id,time,guard,insert,update,operations,notify,assigned,sync,save};
  }
  return {mutation};
}
export const MANAGEMENT_ROLES=['admin','manager','supervisor'];
export const OFFICE_ROLES=[...MANAGEMENT_ROLES,'reception','cashier'];
