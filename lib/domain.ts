export const BRANCHES = [
  {id:'aventura',name:'Aventura',code:'AV'}, {id:'avenues',name:'Avenues',code:'AN'},
  {id:'dasma',name:'Dasma',code:'DA'}, {id:'hessa',name:'Hessa Al Mubarak',code:'HM'},
  {id:'home',name:'Home Service',code:'HS'}, {id:'mishref',name:'Mishref',code:'MI'},
  {id:'promenade',name:'Promenade Mall',code:'PM'}, {id:'qurtoba',name:'Qurtoba',code:'QU'},
  {id:'yarmouk',name:'Yarmouk',code:'YA'}, {id:'zahra',name:'Zahra Complex',code:'ZC'},
];
export const METHODS = ['Cash', 'K-NET', 'Visa / Mastercard', 'Bank transfer'];
export const STATUSES = ['Ongoing','Prepared','Packed','Out for Delivery','Delivered','Closed'];
export const JOB_STATUSES = ['Pending','In Progress','On Hold','Completed'];
export const ROLES = ['admin','manager','reception','tailor'];
export function canonicalRole(role:string) {return role==='cashier'?'reception':role;}
export function isManagerRole(role:string) {return ['admin','manager'].includes(canonicalRole(role));}
export const COUPONS = [{id:'dar-usha',name:'Dar Usha',percent:15}, {id:'family',name:'Family and Friends',percent:20}];
export function check(condition: unknown, message: string, status=400): asserts condition {
  if (!condition) throw Object.assign(new Error(message), {status});
}
export function integer(value: unknown, name: string, min=0, max=100_000_000): number {
  check(typeof value==='number' && Number.isSafeInteger(value) && value>=min && value<=max, `${name} is invalid.`); return value;
}
export function text(value: unknown, max=1000): string {
  check(value===undefined || value===null || typeof value==='string','Invalid text.');
  const result=String(value??'').trim(); check(result.length<=max,`Text exceeds ${max} characters.`); return result;
}
export function canAccess(member: {role:string; branches:string[];active?:number}, branch:string) {
  return member.active!==0 && BRANCHES.some(b=>b.id===branch) && (member.role==='admin' || member.branches.includes(branch));
}
export function calculate(input: any, catalogue: any[], isManager: boolean) {
  check(Array.isArray(input.lines) && input.lines.length>0 && input.lines.length<=200,'Add at least one item (maximum 200 lines).');
  const lines=input.lines.map((line:any)=>{
    const product=catalogue.find(p=>p.id===line.id && p.active!==0); check(product,'An item is no longer available.');
    const qty=integer(line.qty,'Quantity',1,999); const price=integer(line.price,'Price');
    check(price===product.price || product.price===0 || isManager,'Only a manager can change a fixed price.',403);
    return {id:product.id,name:product.name,category:product.category,qty,price,note:text(line.note,1000)};
  });
  const subtotal=lines.reduce((a:number,l:any)=>a+l.qty*l.price,0); integer(subtotal,'Subtotal');
  const coupon=COUPONS.find(c=>c.id===input.coupon); check(!input.coupon || coupon,'Unknown coupon.');
  const discount=coupon ? Math.round(subtotal*coupon.percent/100) : integer(input.discount??0,'Discount');
  check(discount<=subtotal,'Discount exceeds subtotal.');
  check(discount===0 || Boolean(coupon) || isManager,'Only a manager can apply a manual discount.',403);
  const extra=integer(input.extra??0,'Extra charge'); check(extra===0 || isManager,'Only a manager can add an extra charge.',403);
  const total=integer(subtotal-discount+extra,'Total'); return {lines,subtotal,discount,extra,total};
}
export function kuwaitDay(date=new Date()) {return new Intl.DateTimeFormat('en-CA',{timeZone:'Asia/Kuwait',year:'numeric',month:'2-digit',day:'2-digit'}).format(date);}
