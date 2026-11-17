import {test} from 'node:test';
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import path from 'node:path';
import {createApp} from './index.mjs';

test('monthly branch views include more than 1000 imported sales and preserve Kuwait dates and branch isolation',async()=>{
  const app=await createApp({dataDirectory:path.resolve('outputs','import-view-'+randomUUID()),production:false,push:false});
  await new Promise(resolve=>app.server.listen(0,'127.0.0.1',resolve));
  const base='http://127.0.0.1:'+app.server.address().port,password='Test-'+randomUUID();
  try{
    await app.auth.createOwner({name:'Admin',username:'admin',password});
    const login=await fetch(base+'/api/auth/login',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({username:'admin',password})});
    const cookie=login.headers.get('set-cookie').split(';')[0];
    const db=app.storage.sqlite,insert=db.prepare("INSERT INTO orders(id,external_id,bill,branch,kind,customer_name,lines,subtotal,discount,extra,total,paid,cashier,cashier_id,created_at,updated_at) VALUES (?,?,?,'zahra','sale','Test Customer','[]',2000,0,0,2000,0,'Legacy','legacy-import',?,?)");
    db.exec('BEGIN');
    for(let i=0;i<1001;i++)insert.run('import-'+i,'legacy-report:test:'+i,'LEGACY-ZC-'+i,'2026-05-31T21:20:39.000Z','2026-05-31T21:20:39.000Z');
    insert.run('outside-month','legacy-report:outside','LEGACY-ZC-OUT','2026-05-31T20:59:59.000Z','2026-05-31T20:59:59.000Z');
    db.exec('COMMIT');
    const rows=await fetch(base+'/api/data?branch=zahra&from=2026-06-01&to=2026-06-30',{headers:{Cookie:cookie}});
    assert.equal(rows.status,200);const data=await rows.json();assert.equal(data.orders.length,1001);
    assert.equal(data.orders.reduce((n,o)=>n+o.total,0),2002000);assert.ok(!data.orders.some(o=>o.id==='outside-month'));
    const other=await fetch(base+'/api/data?branch=avenues&from=2026-06-01&to=2026-06-30',{headers:{Cookie:cookie}});assert.equal((await other.json()).orders.length,0);
  }finally{await app.close();}
});
