import {createInterface} from 'node:readline/promises';
import {Writable} from 'node:stream';
import {stdin,stdout} from 'node:process';
import {createApp} from './index.mjs';
const app=await createApp();
let silent=false;
const output=new Writable({write(chunk,encoding,done){if(!silent)stdout.write(chunk);done();}});
const prompt=createInterface({input:stdin,output,terminal:Boolean(stdin.isTTY)});
try{
  if(!app.auth.needsSetup()){console.log('An administrator already exists. Create other users from Administration after signing in.');}
  else{
    console.log('Initial Tailor Express administrator setup. Password input is hidden.');
    const name=await prompt.question('Name: '),username=await prompt.question('Username: ');
    stdout.write('Password (at least 12 characters): ');silent=true;
    const password=await prompt.question('');silent=false;stdout.write('\nConfirm password: ');silent=true;
    const confirm=await prompt.question('');silent=false;stdout.write('\n');
    if(password!==confirm)throw new Error('Passwords do not match. No account was created.');
    await app.auth.createOwner({name,username,password});
    console.log('Administrator created. Sign in at http://localhost:3000 with your username and password. Create Manager, Reception and Tailor users from Administration.');
  }
}catch(error){console.error(error.message);process.exitCode=1;}
finally{silent=false;prompt.close();await app.close();}
