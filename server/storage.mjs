import {DatabaseSync} from 'node:sqlite';
import {mkdirSync,readFileSync,readdirSync,writeFileSync,unlinkSync} from 'node:fs';
import path from 'node:path';

export function openStorage(directory,root) {
  mkdirSync(directory,{recursive:true});
  const sqlite=new DatabaseSync(path.join(directory,'pos.sqlite'));
  sqlite.exec('PRAGMA journal_mode=WAL; PRAGMA foreign_keys=ON; PRAGMA busy_timeout=10000;');
  sqlite.exec('CREATE TABLE IF NOT EXISTS _local_migrations (name TEXT PRIMARY KEY)');
  for(const name of readdirSync(path.join(root,'drizzle')).filter(f=>f.endsWith('.sql')).sort()) {
    if(sqlite.prepare('SELECT name FROM _local_migrations WHERE name=?').get(name))continue;
    sqlite.exec('BEGIN IMMEDIATE');
    try {sqlite.exec(readFileSync(path.join(root,'drizzle',name),'utf8'));sqlite.prepare('INSERT INTO _local_migrations VALUES (?)').run(name);sqlite.exec('COMMIT');}
    catch(error){sqlite.exec('ROLLBACK');throw error;}
  }
  sqlite.exec(`CREATE TABLE IF NOT EXISTS credentials (member_id TEXT PRIMARY KEY REFERENCES members(id), password_hash TEXT NOT NULL);
    CREATE TABLE IF NOT EXISTS sessions (token_hash TEXT PRIMARY KEY, member_id TEXT NOT NULL REFERENCES members(id), expires_at INTEGER NOT NULL);
    CREATE INDEX IF NOT EXISTS sessions_member ON sessions(member_id);
    CREATE INDEX IF NOT EXISTS orders_branch_created ON orders(branch,created_at);
    CREATE INDEX IF NOT EXISTS payments_branch_created ON payments(branch,created_at);
    CREATE INDEX IF NOT EXISTS expenses_branch_created ON expenses(branch,created_at);`);
  const statement=(sql,args=[])=>({
    bind(...values){return statement(sql,values);},
    _execute(){const results=sqlite.prepare(sql).all(...args);return {success:true,results,meta:{changes:sqlite.prepare('SELECT changes() AS n').get().n}};},
    async all(){return this._execute();},
    async run(){return this._execute();},
    async first(){return sqlite.prepare(sql).get(...args)??null;},
  });
  const database={prepare:statement,async batch(statements){
    sqlite.exec('BEGIN IMMEDIATE');
    try{const results=statements.map(s=>s._execute());sqlite.exec('COMMIT');return results;}
    catch(error){sqlite.exec('ROLLBACK');throw error;}
  }};
  const folder=path.join(directory,'documents');mkdirSync(folder,{recursive:true});
  function objectPath(key){if(!/^[a-zA-Z0-9/_-]+$/.test(key)||key.includes('..'))throw new Error('Invalid object key');return path.join(folder,...key.split('/'));}
  const bucket={
    async put(key,data){const file=objectPath(key);mkdirSync(path.dirname(file),{recursive:true});writeFileSync(file,new Uint8Array(data));},
    async get(key){try{return {body:new Uint8Array(readFileSync(objectPath(key)))};}catch(e){if(e.code==='ENOENT')return null;throw e;}},
    async delete(key){try{unlinkSync(objectPath(key));}catch(e){if(e.code!=='ENOENT')throw e;}},
  };
  return {sqlite,database,bucket};
}
