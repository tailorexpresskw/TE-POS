import {createHash} from 'node:crypto';
import {check,text,canonicalRole} from './domain.ts';
import type {Database,Row,Statement} from './storage.ts';

export function createNotifications(db:Database,publicKey='') {
  const stmt=(sql:string,...args:any[])=>db.prepare(sql).bind(...args);
  function visible(member:Row) {
    const args:any[]=[member.id];
    let sql="n.member_id=? AND o.status NOT IN ('Voided','Refunded') AND EXISTS (SELECT 1 FROM branches b WHERE b.id=n.branch AND b.active=1)";
    if(member.role!=='admin') {
      if(!member.branches.length)sql+=' AND 0';
      else {sql+=` AND n.branch IN (${member.branches.map(()=>'?').join(',')})`;args.push(...member.branches);}
    }
    if(canonicalRole(member.role)==='tailor'){sql+=" AND n.type='assigned' AND o.tailor_id=?";args.push(member.id);}
    return {sql,args};
  }
  function assigned(id:string,version:number,actor:string):Statement {
    return stmt(`INSERT OR IGNORE INTO notifications (id,member_id,order_id,branch,type,title,message,created_at,read_at)
      SELECT ?||':'||m.id,m.id,o.id,o.branch,'assigned','New tailor assignment','Invoice '||o.bill||' has been assigned to you.',?,''
      FROM orders o JOIN members m ON m.id=o.tailor_id
      WHERE o.id=? AND o.version=? AND o.kind='sale' AND m.active=1 AND m.role='tailor' AND m.id<>?
      AND EXISTS (SELECT 1 FROM json_each(m.branches) WHERE value=o.branch)
      AND EXISTS (SELECT 1 FROM job_events WHERE id=?)`,
      `assigned:${id}:${version}`,new Date().toISOString(),id,version,actor,`assigned:${id}:${version}`);
  }
  function progress(id:string,version:number,status:string,actor:string):Statement {
    return stmt(`INSERT OR IGNORE INTO notifications (id,member_id,order_id,branch,type,title,message,created_at,read_at)
      SELECT ?||':'||m.id,m.id,o.id,o.branch,?,?, 'Invoice '||o.bill||' is now '||?||'.',?,''
      FROM orders o JOIN members m ON m.active=1 AND m.role IN ('admin','manager','supervisor','reception','cashier')
      WHERE o.id=? AND o.version=? AND o.job_status=? AND m.id<>? AND
      (m.role='admin' OR EXISTS (SELECT 1 FROM json_each(m.branches) WHERE value=o.branch))
      AND EXISTS (SELECT 1 FROM job_events WHERE id=?)`,
      `progress:${id}:${version}`,status==='Completed'?'completed':'on_hold',status==='Completed'?'Job completed':'Job put on hold',status.toLowerCase(),new Date().toISOString(),id,version,status,actor,`progress:${id}:${version}`);
  }
  async function read(member:Row,path:string[]) {
    if(path[1]==='config')return {publicKey,enabled:Boolean(publicKey)};
    check(!path[1],'Endpoint not found.',404);
    const scope=visible(member),join=' FROM notifications n JOIN orders o ON o.id=n.order_id WHERE '+scope.sql;
    const items=(await stmt('SELECT n.*,o.bill'+join+' ORDER BY n.created_at DESC,n.id DESC LIMIT 100',...scope.args).all()).results;
    const counts=await stmt("SELECT COUNT(*) count"+join+" AND n.read_at=''",...scope.args).first();
    return {items,unread:counts?.count??0};
  }
  async function write(member:Row,path:string[],body:Row) {
    if(path[1]==='subscriptions') {
      const action=text(body.action,30);
      const endpoint=text(body.endpoint??body.subscription?.endpoint,4096);
      const id=createHash('sha256').update(endpoint).digest('hex');
      if(action==='unsubscribe') {
        await db.batch([stmt('DELETE FROM push_deliveries WHERE subscription_id IN (SELECT id FROM push_subscriptions WHERE id=? AND member_id=?)',id,member.id),stmt('DELETE FROM push_subscriptions WHERE id=? AND member_id=?',id,member.id)]);
        return {ok:true};
      }
      check(action==='subscribe'&&publicKey,'Push notifications are not configured.',503);
      let url:URL;try{url=new URL(endpoint);}catch{check(false,'Invalid push endpoint.');}
      const host=url!.hostname;
      check(url!.protocol==='https:'&&!url!.username&&!url!.password&&(!url!.port||url!.port==='443')&&(
        host==='fcm.googleapis.com'||host==='updates.push.services.mozilla.com'||host==='push.services.mozilla.com'||host.endsWith('.push.apple.com')||host.endsWith('.notify.windows.com')
      ),'Use a supported browser push subscription.');
      const keys=body.subscription?.keys;
      check(keys&&typeof keys.auth==='string'&&typeof keys.p256dh==='string'&&/^[A-Za-z0-9_-]+$/.test(keys.auth)&&/^[A-Za-z0-9_-]+$/.test(keys.p256dh)&&Buffer.from(keys.auth,'base64url').length===16&&Buffer.from(keys.p256dh,'base64url').length===65,'Invalid push encryption keys.');
      const subscription=JSON.stringify({endpoint,keys:{auth:keys.auth,p256dh:keys.p256dh}});
      // A browser device belongs to its currently signed-in user. Clear delivery state on a rebind.
      const previous=await stmt('SELECT member_id FROM push_subscriptions WHERE id=?',id).first();
      await db.batch([
        ...(previous&&previous.member_id!==member.id?[stmt('DELETE FROM push_deliveries WHERE subscription_id=?',id)]:[]),
        stmt('INSERT INTO push_subscriptions(id,member_id,subscription,created_at) VALUES (?,?,?,?) ON CONFLICT(id) DO UPDATE SET created_at=CASE WHEN member_id<>excluded.member_id THEN excluded.created_at ELSE created_at END,member_id=excluded.member_id,subscription=excluded.subscription',id,member.id,subscription,new Date().toISOString()),
      ]);
      return {ok:true};
    }
    check(!path[1]&&body.action==='read','Invalid notification action.');
    const scope=visible(member),id=text(body.id,300);
    if(id!=='all') {scope.sql+=' AND n.id=?';scope.args.push(id);}
    await stmt("UPDATE notifications SET read_at=? WHERE read_at='' AND id IN (SELECT n.id FROM notifications n JOIN orders o ON o.id=n.order_id WHERE "+scope.sql+')',new Date().toISOString(),...scope.args).run();
    return {ok:true};
  }
  return {read,write,assigned,progress};
}
