import {createHash,randomUUID} from 'node:crypto';
import {normalizeShiftPolicy,shiftAccess,shiftDate} from '../lib/shift-rules.ts';
import {check,text,integer} from '../lib/domain.ts';

export function createShifts(sqlite,{clock=Date.now}={}){
  const now=()=>new Date(clock()),time=()=>now().toISOString();
  const policy=id=>sqlite.prepare('SELECT * FROM staff_shift_policies WHERE member_id=?').get(id)??null;
  function member(id){const row=sqlite.prepare('SELECT * FROM members WHERE id=?').get(id);check(row,'Staff account not found.',404);return row;}
  function access(staff){return shiftAccess(staff,policy(staff.id),now());}
  function record(staff,{source='request',reason='Outside scheduled shift',branch='',request}={}){
    const id=createHash('sha256').update(staff.id+'|'+source+'|'+reason+'|'+branch+'|'+Math.floor(clock()/900000)).digest('hex');
    const existing=sqlite.prepare('SELECT last_at FROM security_alerts WHERE id=?').get(id);
    const stamp=new Date(Math.max(clock(),existing?Date.parse(existing.last_at)+1:0)).toISOString();
    const path=request?new URL(request.url).pathname.slice(0,200):'',agent=(request?.headers.get('user-agent')??'').slice(0,300);
    sqlite.exec('BEGIN IMMEDIATE');
    try{
      sqlite.prepare(`INSERT INTO security_alerts(id,member_id,staff_name,username,source,reason,attempted_branch,first_at,last_at,attempts,path,user_agent)
        VALUES (?,?,?,?,?,?,?,?,?,1,?,?) ON CONFLICT(id) DO UPDATE SET last_at=excluded.last_at,attempts=attempts+1,path=excluded.path,user_agent=excluded.user_agent`)
        .run(id,staff.id,staff.name,staff.username??staff.email,source,reason,branch,stamp,stamp,path,agent);
      sqlite.prepare("INSERT OR IGNORE INTO audit(id,branch,actor,action,entity,detail,created_at) VALUES (?,'',?,'security.off_shift',?,?,?)").run('security:'+id,staff.id,staff.id,JSON.stringify({source,reason,attemptedBranch:branch}),stamp);
      sqlite.exec('COMMIT');
    }catch(error){sqlite.exec('ROLLBACK');throw error;}
  }
  function deny(staff,request,{source='request',reason='Outside scheduled shift',branch='',silent=false}={}){
    if(!silent)record(staff,{source,reason,branch,request});
    sqlite.prepare('DELETE FROM sessions WHERE member_id=?').run(staff.id);
    throw Object.assign(new Error('Access is locked outside your scheduled shift. Ask Admin to check your schedule or authorize an exception.'),{status:403,code:'SHIFT_BLOCKED'});
  }
  function enforce(staff,request,{source='request',silent=false}={}){
    const result=access(staff);if(!result.allowed)deny(staff,request,{source,reason:result.reason,silent});return result;
  }
  function branch(staff,branchId,request){
    if(staff.role==='admin')return;
    const result=access(staff);
    if(result.enabled&&!result.allowedBranches.includes(branchId))deny(staff,request,{source:'branch',reason:'Outside scheduled branch',branch:branchId});
  }
  function read(actor,id){
    check(actor.role==='admin','Administrator access required.',403);const staff=member(text(id,100)),row=policy(staff.id);
    return {staff:{id:staff.id,name:staff.name,role:staff.role,branches:JSON.parse(staff.branches)},policy:row?{enabled:row.enabled===1,weekly:JSON.parse(row.weekly),exceptions:JSON.parse(row.exceptions),revision:row.revision}:{enabled:false,weekly:[],exceptions:[],revision:0},access:access(staff),timezone:'Asia/Kuwait'};
  }
  function write(actor,id,body){
    check(actor.role==='admin','Administrator access required.',403);const staff=member(text(id,100));check(staff.role!=='admin','Admin access remains available for schedule administration.');
    const assigned=JSON.parse(staff.branches),active=sqlite.prepare('SELECT id FROM branches WHERE active=1').all().map(b=>b.id);
    const clean=normalizeShiftPolicy(body,assigned.filter(id=>active.includes(id))),revision=integer(body.revision,'Schedule revision');
    sqlite.exec('BEGIN IMMEDIATE');
    try{
      check((policy(id)?.revision??0)===revision,'This schedule changed. Refresh and try again.',409);
      sqlite.prepare(`INSERT INTO staff_shift_policies(member_id,enabled,weekly,exceptions,revision,updated_by,updated_at) VALUES (?,?,?,?,?,?,?)
        ON CONFLICT(member_id) DO UPDATE SET enabled=excluded.enabled,weekly=excluded.weekly,exceptions=excluded.exceptions,revision=excluded.revision,updated_by=excluded.updated_by,updated_at=excluded.updated_at`)
        .run(id,clean.enabled?1:0,JSON.stringify(clean.weekly),JSON.stringify(clean.exceptions),revision+1,actor.id,time());
      sqlite.prepare("INSERT INTO audit(id,branch,actor,action,entity,detail,created_at) VALUES (?,'',?,'staff.shift_updated',?,?,?)").run(randomUUID(),actor.id,id,JSON.stringify(clean),time());
      sqlite.exec('COMMIT');
    }catch(error){sqlite.exec('ROLLBACK');throw error;}
    return read(actor,id);
  }
  function alertRange(url){
    const today=new Intl.DateTimeFormat('en-CA',{timeZone:'Asia/Kuwait',year:'numeric',month:'2-digit',day:'2-digit'}).format(now());
    const from=shiftDate(url?.searchParams.get('from')??today),to=shiftDate(url?.searchParams.get('to')??from);check(from<=to,'Choose a valid date range.');
    return [new Date(from+'T00:00:00+03:00').toISOString(),new Date(to+'T23:59:59.999+03:00').toISOString()];
  }
  function alerts(actor,url){
    check(actor.role==='admin','Administrator access required.',403);const [start,end]=alertRange(url);
    return {items:sqlite.prepare('SELECT * FROM security_alerts WHERE first_at BETWEEN ? AND ? ORDER BY last_at DESC LIMIT 200').all(start,end),
      summary:sqlite.prepare("SELECT COUNT(*) events,COUNT(DISTINCT member_id) staff,COALESCE(SUM(attempts),0) attempts,COALESCE(SUM(CASE WHEN source='login' THEN attempts ELSE 0 END),0) login_attempts FROM security_alerts WHERE first_at BETWEEN ? AND ?").get(start,end)};
  }
  function inbox(actor){
    if(actor.role!=='admin')return {items:[],unread:0};
    const items=sqlite.prepare(`SELECT a.*,CASE WHEN r.read_at>=a.last_at THEN r.read_at ELSE '' END read_at FROM security_alerts a
      LEFT JOIN security_alert_receipts r ON r.alert_id=a.id AND r.member_id=? ORDER BY a.last_at DESC LIMIT 100`).all(actor.id).map(row=>({
        id:'security:'+row.id,type:'off_shift',title:'Off-shift access blocked',message:`${row.staff_name}: ${row.source==='login'?'sign-in with valid credentials':row.source==='branch'?'access to an unscheduled branch':'request from an existing session'} blocked. ${row.attempts} attempt(s).`,
        created_at:row.last_at,read_at:row.read_at,branch:'',order_id:null,alert_id:row.id,
      }));
    const unread=sqlite.prepare('SELECT COUNT(*) count FROM security_alerts a LEFT JOIN security_alert_receipts r ON r.alert_id=a.id AND r.member_id=? WHERE r.read_at IS NULL OR r.read_at<a.last_at').get(actor.id).count;
    return {items,unread};
  }
  function mark(actor,id){
    check(actor.role==='admin','Administrator access required.',403);
    const filter=id==='all'?' WHERE 1=1':' WHERE id=?',args=id==='all'?[]:[id.replace(/^security:/,'')];
    sqlite.prepare(`INSERT INTO security_alert_receipts(id,alert_id,member_id,read_at)
      SELECT id||':'||?,id,?,CASE WHEN last_at>? THEN last_at ELSE ? END FROM security_alerts${filter}
      ON CONFLICT(id) DO UPDATE SET read_at=excluded.read_at`).run(actor.id,actor.id,time(),time(),...args);
    return {ok:true};
  }
  return {access,enforce,branch,read,write,alerts,inbox,mark};
}
