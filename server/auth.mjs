import {scrypt as scryptCallback,randomBytes,createHash,timingSafeEqual} from 'node:crypto';
import {promisify} from 'node:util';
const scrypt=promisify(scryptCallback),cookieName='te_pos_session';
const digest=token=>createHash('sha256').update(token).digest('hex');
function check(value,message,status=400){if(!value)throw Object.assign(new Error(message),{status});}
export function validatePassword(password){check(typeof password==='string'&&password.length>=12&&password.length<=256,'Use a password with 12–256 characters.');}
async function passwordHash(password){validatePassword(password);const salt=randomBytes(16).toString('hex');return `scrypt:${salt}:${Buffer.from(await scrypt(password,salt,64)).toString('hex')}`;}
async function matches(password,encoded){if(typeof password!=='string'||password.length>256)return false;const [,salt,hash]=(encoded||'scrypt:dummy:').split(':');const calculated=Buffer.from(await scrypt(password,salt,64));const expected=Buffer.from(hash||'00'.repeat(64),'hex');return calculated.length===expected.length&&timingSafeEqual(calculated,expected);}
const tokenFrom=request=>(request.headers.get('cookie')||'').split(';').map(s=>s.trim()).find(s=>s.startsWith(cookieName+'='))?.slice(cookieName.length+1)??'';
export function createAuth(sqlite,{secure=false}={}) {
  const attempts=new Map();
  const reply=(value,status=200,headers={})=>Response.json(value,{status,headers:{'Cache-Control':'no-store',...headers}});
  const cookie=(token,age=8*60*60)=>`${cookieName}=${token}; Path=/; HttpOnly; SameSite=Strict; Max-Age=${age}${secure?'; Secure':''}`;
  async function setPassword(id,password){const hash=await passwordHash(password);sqlite.exec('BEGIN IMMEDIATE');try{sqlite.prepare('INSERT INTO credentials(member_id,password_hash) VALUES (?,?) ON CONFLICT(member_id) DO UPDATE SET password_hash=excluded.password_hash').run(id,hash);sqlite.prepare('UPDATE members SET user_id=? WHERE id=?').run(id,id);sqlite.prepare('DELETE FROM sessions WHERE member_id=?').run(id);sqlite.exec('COMMIT');}catch(e){sqlite.exec('ROLLBACK');throw e;}}
  const needsSetup=()=>!sqlite.prepare('SELECT id FROM members LIMIT 1').get();
  async function createOwner(body){
    const email=String(body.email??'').trim().toLowerCase(),name=String(body.name??'').trim();
    const username=String(body.username??'').trim().toLowerCase();
    check(!username||/^[a-z0-9][a-z0-9._-]{2,49}$/.test(username),'Use a username with 3–50 letters, numbers, dots, hyphens or underscores.');
    check((username||email)&&(!email||(/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)&&email.length<=200))&&name.length>0&&name.length<=100,'Enter a name and username.');
    const hash=await passwordHash(body.password);check(needsSetup(),'An administrator already exists.',409);
    sqlite.exec('BEGIN IMMEDIATE');try{sqlite.prepare("INSERT INTO members(id,user_id,email,username,name,role,branches,active) VALUES ('owner','owner',?,?,?,'admin','[]',1)").run(email||'owner@users.invalid',username||null,name);sqlite.prepare("INSERT INTO credentials VALUES ('owner',?)").run(hash);sqlite.exec('COMMIT');}catch(e){sqlite.exec('ROLLBACK');throw e;}
  }
  async function authenticate(request){const token=tokenFrom(request);if(!/^[a-f0-9]{64}$/.test(token))return null;const session=sqlite.prepare('SELECT s.member_id FROM sessions s JOIN members m ON m.id=s.member_id WHERE s.token_hash=? AND s.expires_at>? AND m.active=1').get(digest(token),Date.now());return session?{userId:session.member_id}:null;}
  function sessionReply(id,request){
    const previous=tokenFrom(request);if(previous)sqlite.prepare('DELETE FROM sessions WHERE token_hash=?').run(digest(previous));
    sqlite.prepare('DELETE FROM sessions WHERE expires_at<=?').run(Date.now());
    const token=randomBytes(32).toString('hex');sqlite.prepare('INSERT INTO sessions VALUES (?,?,?)').run(digest(token),id,Date.now()+8*60*60*1000);
    return reply({ok:true},200,{'Set-Cookie':cookie(token)});
  }
  async function handle(request,route,{ip='unknown'}={}){
    try{
      if(route==='status'&&request.method==='GET')return reply({needsSetup:needsSetup(),authenticated:Boolean(await authenticate(request)),canSetup:false});
      if(route==='setup')return reply({error:'Only an administrator can create users. The initial administrator must be provisioned on the server.'},403);
      check(request.method==='POST','Method not allowed.',405);
      check((request.headers.get('content-type')??'').includes('application/json'),'JSON required.',415);
      const origin=request.headers.get('origin');check(!origin||origin===new URL(request.url).origin,'Cross-origin write rejected.',403);
      const body=await request.json();check(body&&typeof body==='object'&&!Array.isArray(body),'Invalid request.');
      if(route==='login'){
        const login=String(body.username??body.email??'').trim().toLowerCase();check(login.length<=200,'Invalid login.');
        const key=digest(ip),time=Date.now();let history=attempts.get(key);
        if(!history||history.until<=time){history={count:0,until:time+15*60*1000};attempts.set(key,history);}
        if(attempts.size>10000)for(const [k,v]of attempts)if(v.until<=time)attempts.delete(k);
        check(history.count<10,'Too many sign-in attempts. Try again in 15 minutes.',429);history.count++;
        const member=sqlite.prepare('SELECT m.id,c.password_hash FROM members m JOIN credentials c ON c.member_id=m.id WHERE '+(login.includes('@')?'lower(m.email)=?':'m.username=?')+' AND m.active=1').get(login);
        const valid=await matches(body.password,member?.password_hash);check(member&&valid,'Username or password is incorrect.',401);
        attempts.delete(key);return sessionReply(member.id,request);
      }
      if(route==='logout'){const token=tokenFrom(request);if(token)sqlite.prepare('DELETE FROM sessions WHERE token_hash=?').run(digest(token));return reply({ok:true},200,{'Set-Cookie':cookie('',0)});}
      if(route==='password'){
        const user=await authenticate(request);check(user,'Sign in to continue.',401);const credential=sqlite.prepare('SELECT password_hash FROM credentials WHERE member_id=?').get(user.userId);
        check(await matches(body.currentPassword,credential?.password_hash),'Current password is incorrect.',401);await setPassword(user.userId,body.password);return reply({ok:true},200,{'Set-Cookie':cookie('',0)});
      }
      check(false,'Endpoint not found.',404);
    }catch(error){return reply({error:error.status?error.message:'Account operation failed.'},error.status??500);}
  }
  return {handle,authenticate,setPassword,createOwner,needsSetup};
}
