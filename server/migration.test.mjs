import {test} from 'node:test';
import assert from 'node:assert/strict';
import {DatabaseSync} from 'node:sqlite';
import {mkdirSync,readFileSync} from 'node:fs';
import path from 'node:path';
import {randomUUID} from 'node:crypto';
import {createApp} from './index.mjs';
import {readdirSync} from 'node:fs';

test('tracking migration preserves existing users, prices and payment balances',async()=>{
  const directory=path.resolve('outputs','migration-'+randomUUID());mkdirSync(directory,{recursive:true});
  const old=new DatabaseSync(path.join(directory,'pos.sqlite'));
  old.exec('CREATE TABLE _local_migrations (name TEXT PRIMARY KEY)');
  for(const name of ['0000_glamorous_nightcrawler.sql','0001_illegal_proudstar.sql']){old.exec(readFileSync(path.join('drizzle',name),'utf8'));old.prepare('INSERT INTO _local_migrations VALUES (?)').run(name);}
  old.prepare("INSERT INTO members(id,user_id,email,name,role,branches,active) VALUES ('existing','existing','staff@migration.test','Existing Staff','cashier','[\"zahra\"]',1)").run();
  old.prepare('INSERT INTO orders(id,branch,bill,kind,customer_name,lines,subtotal,discount,extra,total,paid,cashier,cashier_id,created_at,updated_at) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)').run('old-invoice','aventura','OLD-1','sale','Existing Customer','[]',2000,0,0,2000,500,'Existing Staff','existing','2026-10-30T10:00:00Z','2026-10-30T10:00:00Z');
  old.prepare('INSERT INTO prices VALUES (?,?,?)').run('1001',2500,1);old.close();
  const app=await createApp({dataDirectory:directory,production:false});
  try{
    const invoice=app.storage.sqlite.prepare("SELECT * FROM orders WHERE id='old-invoice'").get();
    assert.equal(invoice.total,2000);assert.equal(invoice.paid,500);assert.equal(invoice.customer_name,'Existing Customer');assert.equal(invoice.tailor_id,null);assert.equal(invoice.job_status,'Pending');
    assert.equal(invoice.branch,'aventura');
    assert.equal(app.storage.sqlite.prepare('SELECT count(*) n FROM members').get().n,1);
    assert.equal(app.storage.sqlite.prepare("SELECT price FROM prices WHERE id='1001'").get().price,2500);
    assert.equal(app.storage.sqlite.prepare('SELECT count(*) n FROM job_events').get().n,0);
    assert.equal(app.storage.sqlite.prepare("SELECT username FROM members WHERE id='existing'").get().username,null);
    assert.equal(app.storage.sqlite.prepare('SELECT count(*) n FROM notifications').get().n,0);
    assert.equal(app.storage.sqlite.prepare('SELECT count(*) n FROM _local_migrations').get().n,7);
    assert.equal(app.storage.sqlite.prepare("SELECT active FROM branches WHERE id='aventura'").get().active,0);
    assert.equal(app.storage.sqlite.prepare('SELECT count(*) n FROM branches WHERE active=1').get().n,9);
  }finally{await app.close();}
});

test('service migration preserves historical completion and creates the correct discounted work credit',async()=>{
  const directory=path.resolve('outputs','migration-services-'+randomUUID());mkdirSync(directory,{recursive:true});
  const old=new DatabaseSync(path.join(directory,'pos.sqlite'));old.exec('CREATE TABLE _local_migrations(name TEXT PRIMARY KEY)');
  for(const name of readdirSync('drizzle').filter(name=>name.endsWith('.sql')&&name<'0006').sort()){old.exec(readFileSync(path.join('drizzle',name),'utf8'));old.prepare('INSERT INTO _local_migrations VALUES (?)').run(name);}
  old.prepare("INSERT INTO members(id,user_id,email,name,role,branches,active) VALUES ('tailor','tailor','tailor@old.test','Legacy Tailor','tailor','[\"zahra\"]',1)").run();
  old.prepare('INSERT INTO orders(id,branch,bill,kind,customer_name,lines,subtotal,discount,extra,total,paid,cashier,cashier_id,created_at,updated_at,tailor_id,job_status) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)').run('approved-old','zahra','OLD-APPROVED','sale','Customer',JSON.stringify([{id:'1001',name:'Hem',price:2000,qty:2,note:'90 cm'}]),4000,333,0,3667,3667,'Reception','legacy','2026-11-01T10:00:00Z','2026-11-01T11:00:00Z','tailor','Completed');
  old.close();const app=await createApp({dataDirectory:directory,production:false,push:false});
  try{
    const sale=app.storage.sqlite.prepare("SELECT * FROM orders WHERE id='approved-old'").get();assert.equal(sale.total,3667);assert.equal(sale.paid,3667);assert.equal(sale.job_status,'Completed');
    const task=app.storage.sqlite.prepare('SELECT * FROM work_items').get();assert.equal(task.status,'Completed');assert.equal(task.approved_by,null);assert.equal(task.quantity,2);
    const credit=app.storage.sqlite.prepare('SELECT * FROM work_credits').get();assert.equal(credit.amount,3667);assert.equal(credit.quantity,2);assert.equal(credit.reason,'legacy_approved');
  }finally{await app.close();}
});
