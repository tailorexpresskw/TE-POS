import {api,document} from '../../../lib/service';
export const dynamic='force-dynamic';
async function handle(request:Request,{params}:{params:Promise<{path:string[]}>}) {
  const {path}=await params;
  return path[0]==='documents'?document(request,path[1]??''):api(request,path);
}
export const GET=handle;
export const POST=handle;
