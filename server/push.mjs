import webpush from 'web-push';
import {existsSync,readFileSync,writeFileSync} from 'node:fs';
import path from 'node:path';

export function createPush(sqlite,directory,{enabled=true,sender,publicUrl}={}) {
  if(!enabled)return {publicKey:'',flush:async()=>{},close:async()=>{}};
  const keyFile=path.join(directory,'web-push.json');
  let keys;
  if(process.env.VAPID_PUBLIC_KEY||process.env.VAPID_PRIVATE_KEY){
    if(!process.env.VAPID_PUBLIC_KEY||!process.env.VAPID_PRIVATE_KEY)throw new Error('Set both VAPID_PUBLIC_KEY and VAPID_PRIVATE_KEY.');
    keys={publicKey:process.env.VAPID_PUBLIC_KEY,privateKey:process.env.VAPID_PRIVATE_KEY};
  }else if(existsSync(keyFile))keys=JSON.parse(readFileSync(keyFile,'utf8'));
  else {keys=webpush.generateVAPIDKeys();writeFileSync(keyFile,JSON.stringify(keys),{flag:'wx',mode:0o600});}
  const vapidDetails={...keys,subject:process.env.VAPID_SUBJECT||(publicUrl&&!new URL(publicUrl).hostname.endsWith('localhost')?publicUrl:'https://github.com/tailorexpresskw/TE-POS')};
  webpush.generateRequestDetails({endpoint:'https://fcm.googleapis.com/validation'},undefined,{vapidDetails});
  const send=sender??((subscription,payload)=>webpush.sendNotification(subscription,payload,{vapidDetails,TTL:86400,timeout:10000}));
  let timer,running=null;
  async function deliver(row){
    const id=row.notification_id+':'+row.subscription_id;
    try{
      // Lock-screen messages contain no customer, invoice, price or garment details.
      await send(JSON.parse(row.subscription),JSON.stringify({notificationId:row.notification_id,title:'Tailor Express',body:'You have a new work notification. Open the POS to view it.'}));
      sqlite.prepare('INSERT INTO push_deliveries(id,notification_id,subscription_id,attempts,next_attempt,sent_at) SELECT ?,?,?,1,\'\',? WHERE EXISTS(SELECT 1 FROM push_subscriptions WHERE id=?) ON CONFLICT(id) DO UPDATE SET attempts=attempts+1,sent_at=excluded.sent_at').run(id,row.notification_id,row.subscription_id,new Date().toISOString(),row.subscription_id);
    }catch(error){
      if(error.statusCode===404||error.statusCode===410){
        sqlite.prepare('DELETE FROM push_deliveries WHERE subscription_id=?').run(row.subscription_id);
        sqlite.prepare('DELETE FROM push_subscriptions WHERE id=?').run(row.subscription_id);
      }else{
        const next=new Date(Date.now()+Math.min(6*60*60*1000,30000*2**(row.attempts??0))).toISOString();
        sqlite.prepare("INSERT INTO push_deliveries(id,notification_id,subscription_id,attempts,next_attempt,sent_at) SELECT ?,?,?,1,?,'' WHERE EXISTS(SELECT 1 FROM push_subscriptions WHERE id=?) ON CONFLICT(id) DO UPDATE SET attempts=attempts+1,next_attempt=excluded.next_attempt").run(id,row.notification_id,row.subscription_id,next,row.subscription_id);
      }
    }
  }
  function flush(){
    if(running)return running;
    running=(async()=>{
      const time=new Date().toISOString(),cutoff=new Date(Date.now()-86400000).toISOString();
      const rows=sqlite.prepare(`SELECT n.id notification_id,p.id subscription_id,p.subscription,COALESCE(d.attempts,0) attempts
        FROM notifications n JOIN orders o ON o.id=n.order_id JOIN members m ON m.id=n.member_id
        JOIN push_subscriptions p ON p.member_id=n.member_id
        LEFT JOIN push_deliveries d ON d.notification_id=n.id AND d.subscription_id=p.id
        WHERE m.active=1 AND n.read_at='' AND n.created_at>=? AND p.created_at<=n.created_at
        AND EXISTS(SELECT 1 FROM branches b WHERE b.id=n.branch AND b.active=1)
        AND o.status NOT IN ('Voided','Refunded') AND (m.role='admin' OR EXISTS(SELECT 1 FROM json_each(m.branches) WHERE value=n.branch))
        AND (m.role<>'tailor' OR (n.type='assigned' AND o.tailor_id=m.id))
        AND COALESCE(d.sent_at,'')='' AND COALESCE(d.attempts,0)<5 AND COALESCE(d.next_attempt,'')<=?
        ORDER BY n.created_at LIMIT 10`).all(cutoff,time);
      await Promise.all(rows.map(deliver));
    })().catch(()=>{console.error('Push delivery will retry; the in-app notification inbox remains available.');}).finally(()=>{running=null;});
    return running;
  }
  timer=setInterval(flush,15000);timer.unref();
  return {publicKey:keys.publicKey,flush,close:async()=>{clearInterval(timer);if(running)await running;}};
}
