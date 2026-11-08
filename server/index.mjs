import http from 'node:http';
import {existsSync,statSync,createReadStream} from 'node:fs';
import path from 'node:path';
import {fileURLToPath,pathToFileURL} from 'node:url';
import {createService} from '../lib/service.ts';
import {openStorage} from './storage.mjs';
import {createAuth} from './auth.mjs';
import {createPush} from './push.mjs';
const root=fileURLToPath(new URL('..',import.meta.url));
const types={'.html':'text/html; charset=utf-8','.js':'application/javascript; charset=utf-8','.json':'application/json; charset=utf-8','.wasm':'application/wasm','.svg':'image/svg+xml','.png':'image/png','.jpg':'image/jpeg','.ttf':'font/ttf','.otf':'font/otf','.css':'text/css; charset=utf-8','.txt':'text/plain; charset=utf-8'};
function loopback(address){return ['127.0.0.1','::1','::ffff:127.0.0.1'].includes(address);}
export async function createApp(options={}) {
  const production=options.production??process.env.NODE_ENV==='production';
  const publicUrl=options.publicUrl??process.env.PUBLIC_URL;
  if(production&&(!publicUrl||!publicUrl.startsWith('https://')))throw new Error('Set PUBLIC_URL to the HTTPS address of your deployment.');
  const dataDirectory=path.resolve(options.dataDirectory??process.env.DATA_DIR??path.join(root,'data'));
  const storage=openStorage(dataDirectory,root),auth=createAuth(storage.sqlite,{secure:production||publicUrl?.startsWith('https://')});
  if(auth.needsSetup()&&(process.env.ADMIN_USERNAME||process.env.ADMIN_EMAIL)&&process.env.ADMIN_PASSWORD)await auth.createOwner({name:process.env.ADMIN_NAME||'Administrator',username:process.env.ADMIN_USERNAME,email:process.env.ADMIN_EMAIL,password:process.env.ADMIN_PASSWORD});
  const push=createPush(storage.sqlite,dataDirectory,{enabled:options.push!==false&&process.env.DISABLE_WEB_PUSH!=='1',sender:options.pushSender,publicUrl});
  const service=createService({database:storage.database,bucket:storage.bucket,authenticate:auth.authenticate,setPassword:auth.setPassword,pushPublicKey:push.publicKey});
  const server=http.createServer(async(incoming,outgoing)=>{
    const security={'X-Content-Type-Options':'nosniff','X-Frame-Options':'DENY','Referrer-Policy':'same-origin'};
    try{
      const base=publicUrl??`http://${incoming.headers.host||'localhost'}`;
      const url=new URL(incoming.url,base);
      if(publicUrl&&incoming.headers.host!==new URL(publicUrl).host&&!loopback(incoming.socket.remoteAddress)){outgoing.writeHead(421,security);outgoing.end('Unrecognized host');return;}
      if(url.pathname.startsWith('/api/')){
        const limit=url.pathname.startsWith('/api/documents')?5*1024*1024:150000;
        if(Number(incoming.headers['content-length']??0)>limit)throw Object.assign(new Error('Request too large.'),{status:413});
        const chunks=[];let size=0;for await(const chunk of incoming){size+=chunk.length;if(size>limit)throw Object.assign(new Error('Request too large.'),{status:413});chunks.push(chunk);}
        const headers=new Headers();for(const [key,value]of Object.entries(incoming.headers)){if(value!==undefined)headers.set(key,Array.isArray(value)?value.join(', '):value);}
        const request=new Request(url,{method:incoming.method,headers,...(!['GET','HEAD'].includes(incoming.method)?{body:Buffer.concat(chunks)}:{})});
        const route=url.pathname.slice(5).split('/');let response;
        if(route[0]==='auth')response=await auth.handle(request,route[1],{ip:incoming.socket.remoteAddress});
        else {
          response=route[0]==='documents'?await service.document(request,route[1]??''):await service.api(request,route);
        }
        outgoing.writeHead(response.status,{...security,...Object.fromEntries(response.headers)});outgoing.end(Buffer.from(await response.arrayBuffer()));return;
      }
      if(incoming.method!=='GET'&&incoming.method!=='HEAD'){outgoing.writeHead(405,security);outgoing.end();return;}
      if(url.pathname==='/'){outgoing.writeHead(302,{...security,Location:'/pos/'});outgoing.end();return;}
      const decoded=decodeURIComponent(url.pathname);const asset=path.resolve(root,'public','.'+decoded+(decoded.endsWith('/')?'index.html':''));const publicRoot=path.join(root,'public');
      if(!asset.startsWith(publicRoot+path.sep)||!existsSync(asset)||!statSync(asset).isFile()){outgoing.writeHead(404,security);outgoing.end('Not found');return;}
      outgoing.writeHead(200,{...security,'Content-Type':types[path.extname(asset)]??'application/octet-stream','Cache-Control':'no-cache','Content-Length':statSync(asset).size});
      if(incoming.method==='HEAD')outgoing.end();else createReadStream(asset).pipe(outgoing);
    }catch(error){outgoing.writeHead(error.status??500,{...security,'Content-Type':'application/json','Cache-Control':'no-store'});outgoing.end(JSON.stringify({error:error.status?error.message:'The request could not be completed.'}));if(!error.status)console.error(error);}
  });
  return {server,auth,storage,push,close:async()=>{if(server.listening)await new Promise(resolve=>server.close(resolve));await push.close();storage.sqlite.close();}};
}
if(process.argv[1]&&import.meta.url===pathToFileURL(path.resolve(process.argv[1])).href){
  const app=await createApp();
  const host=process.env.HOST||(process.env.NODE_ENV==='production'?'0.0.0.0':'127.0.0.1'),port=Number(process.env.PORT||3000);
  app.server.listen(port,host,()=>{console.log(`Tailor Express POS: http://${host==='0.0.0.0'?'localhost':host}:${port}/`);console.log(app.auth.needsSetup()?'Run Setup-Admin.cmd once to provision the initial administrator.':'Sign in using your Tailor Express account.');});
  for(const signal of ['SIGINT','SIGTERM'])process.on(signal,()=>app.close().then(()=>process.exit(0)));
}
