import {createRequire} from 'node:module';
import {readFileSync,existsSync,cpSync,mkdirSync} from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
const root=fileURLToPath(new URL('..',import.meta.url));
const stage=path.resolve(process.argv[2]??'');
const output=path.join(root,'outputs')+path.sep;
if(!stage.startsWith(output)||!stage.endsWith(path.sep+'TailorExpress-POS'))throw new Error('Package target must be the POS stage inside outputs.');
const visited=new Set();
function copy(name,from){
  const require=createRequire(path.join(from,'package.json'));
  let folder=path.dirname(require.resolve(name));
  while(!existsSync(path.join(folder,'package.json'))||JSON.parse(readFileSync(path.join(folder,'package.json'),'utf8')).name!==name){
    const parent=path.dirname(folder);if(parent===folder)throw new Error('Cannot locate runtime dependency '+name);folder=parent;
  }
  if(visited.has(folder))return;visited.add(folder);
  const relative=path.relative(root,folder);
  if(!relative.startsWith('node_modules'+path.sep))throw new Error('Runtime dependency is outside this project.');
  const destination=path.join(stage,relative);mkdirSync(path.dirname(destination),{recursive:true});cpSync(folder,destination,{recursive:true});
  const pkg=JSON.parse(readFileSync(path.join(folder,'package.json'),'utf8'));
  for(const dependency of Object.keys(pkg.dependencies??{}))copy(dependency,folder);
}
const pkg=JSON.parse(readFileSync(path.join(root,'package.json'),'utf8'));
for(const name of Object.keys(pkg.dependencies??{}))copy(name,root);
console.log(`Packaged ${visited.size} runtime dependencies; development tools excluded.`);
