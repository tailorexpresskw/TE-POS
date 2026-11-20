import {check,text,integer,METHODS,CANCELLATION_REASONS,canOperate,lineValues,netTotal} from './domain.ts';
import {createWorkflow,MANAGEMENT_ROLES} from './workflow.ts';
import type {WorkflowDeps} from './workflow.ts';
import type {Row} from './storage.ts';

export function createAdjustments(deps:WorkflowDeps){
  const {all,first}=deps,{mutation}=createWorkflow(deps);
  async function options(sale:Row){
    const previous=await all("SELECT lines FROM orders WHERE parent_order_id=? AND document_type IN ('refund','cancellation')",sale.id),quantities=new Map<number,number>();
    for(const doc of previous)for(const l of JSON.parse(doc.lines))if(Number.isInteger(l.original_line_index))quantities.set(l.original_line_index,(quantities.get(l.original_line_index)??0)+l.qty);
    const values=lineValues(sale);
    return JSON.parse(sale.lines).map((l:Row,index:number)=>({...l,index,refunded_qty:quantities.get(index)??0,remaining_qty:l.qty-(quantities.get(index)??0),net_value:values[index]}));
  }
  async function write(member:Row,sale:Row,body:Row){
    const action=text(body.action,30),isCharge=action==='charge',isCancel=['void','cancel'].includes(action);
    if(!isCharge)check(canOperate(member as any,isCancel?'cancel':'refund'),'Admin must grant you permission for this action.',403);
    if(isCancel&&sale.paid>0)check(canOperate(member as any,'refund'),'A paid cancellation also requires Admin-granted refund permission.',403);
    const id=text(body.id,100)||crypto.randomUUID();check(/^[a-zA-Z0-9-]{16,100}$/.test(id),'Missing document identifier.');
    const previous=await first('SELECT * FROM orders WHERE id=?',id),type=isCharge?'charge':isCancel?'cancellation':'refund';
    if(previous){check(previous.parent_order_id===sale.id&&previous.document_type===type,'Document identifier conflict.',409);return {document:previous,order:sale};}
    check(sale.kind==='sale'&&!['Voided','Refunded'].includes(sale.status),'This invoice is already reversed.');await deps.branchAccess(member,sale.branch);
    const reason=text(body.reason,2000),reasonCode=text(body.reasonCode,80),chargeKind=isCharge?text(body.chargeKind??'extra',20):'';
    if(isCharge)check(['delivery','extra'].includes(chargeKind),'Choose the charge type.');
    if(!isCharge){check(reason.length>=3,'Enter the reason.');if(isCancel)check(CANCELLATION_REASONS.includes(reasonCode),'Choose a cancellation reason.');}
    let lines:Row[],amount=0,cash=0;const method=text(body.method,40),choices=await options(sale);
    if(isCharge){
      check(!sale.parent_order_id,'Add extra charges to the original invoice.');
      const name=text(body.name,120)||'Delivery fee',price=integer(body.amount,'Charge',1);
      lines=[{id:'supplement',name,category:'Additional charges',qty:1,price,amount:price,note:text(body.note,1000)}];amount=price;
      cash=integer(body.paid??0,'Amount received',0,amount);if(cash)check(METHODS.includes(method),'Choose the payment method.');
    }else{
      const full=isCancel||body.full===true||body.lines===undefined;
      const selection=full?choices.filter((l:Row)=>l.remaining_qty>0).map((l:Row)=>({index:l.index,qty:l.remaining_qty})):body.lines;
      check(Array.isArray(selection)&&(selection.length>0||full)&&selection.length<=200&&selection.every(l=>l&&typeof l==='object'&&!Array.isArray(l))&&new Set(selection.map(l=>l.index)).size===selection.length,'Select services and quantities to refund.');
      lines=selection.map((selected:Row)=>{
        const index=integer(selected.index,'Service index',0,choices.length-1),line=choices[index],qty=integer(selected.qty,'Refund quantity',1,line.remaining_qty);
        const value=Math.floor(line.net_value*(line.refunded_qty+qty)/line.qty)-Math.floor(line.net_value*line.refunded_qty/line.qty);
        return {id:line.id,name:line.name,category:line.category,qty,price:line.price,amount:value,note:line.note,original_line_index:index};
      });
      amount=lines.reduce((n,l)=>n+l.amount,0);
      if(full){const remainder=netTotal(sale)-amount;check(remainder>=0,'Refund value exceeds the invoice balance.');if(remainder)lines.push({id:'extra-credit',name:'Remaining extra charges',category:'Adjustment',qty:1,price:remainder,amount:remainder,note:''});amount=netTotal(sale);}
      check(amount>0&&amount<=netTotal(sale),'There is no remaining value to refund.');
      cash=integer(body.cashRefund??Math.min(amount,sale.paid),'Cash returned',0,Math.min(amount,sale.paid));
      check(cash>=Math.max(0,sale.paid-(netTotal(sale)-amount)),'Return the collected amount that exceeds the invoice’s new total.');
      if(cash)check(METHODS.includes(method),'Choose the refund method.');
      if(isCancel)check(cash===sale.paid,'Return the remaining payment when cancelling a paid invoice.');
    }
    const prefix=isCharge?'ADD':isCancel?'CAN':'RF',bill=`${sale.bill}-${prefix}-${id.slice(-8).toUpperCase()}`;
    const m=mutation(member,sale,body.version,'invoice.'+type,{documentId:id,bill,type,amount,cashReturned:isCharge?0:cash,reasonCode,note:reason});
    const document={id,branch:sale.branch,bill,kind:isCharge?'sale':type,parent_order_id:sale.id,document_type:type,
      customer_id:sale.customer_id,customer_name:sale.customer_name,phone:sale.phone,address:sale.address,
      lines:JSON.stringify(lines),subtotal:amount,discount:0,extra:0,total:amount,paid:isCharge?cash:0,refunded_total:0,
      notes:isCharge?text(body.note,1000):'',reason,reason_code:reasonCode,charge_kind:chargeKind,cashier:member.name,cashier_id:member.id,
      status:isCharge?(cash===amount?'Closed':'Ongoing'):'Issued',created_at:m.time,updated_at:m.time,version:0};
    const operations=[m.insert('orders',document)];
    if(isCharge){
      if(cash)operations.push(m.insert('payments',{id:crypto.randomUUID(),order_id:id,branch:sale.branch,amount:cash,method,reference:'Additional charge '+bill,actor:member.id,created_at:m.time}));
    }else{
      operations.push(m.update('orders','refunded_total=refunded_total+?,paid=paid-?,status=CASE WHEN ? THEN ? ELSE status END',[amount,cash,isCancel||sale.refunded_total+amount===sale.total?1:0,isCancel?'Voided':'Refunded'],'id=?',sale.id));
      if(cash)operations.push(m.insert('payments',{id:crypto.randomUUID(),order_id:sale.id,branch:sale.branch,amount:-cash,method,reference:bill+' · '+reason,actor:member.id,created_at:m.time}));
      for(const l of lines)if(Number.isInteger(l.original_line_index)){
        const remaining=choices[l.original_line_index].remaining_qty-l.qty;
        const affected=await all("SELECT id FROM work_items WHERE order_id=? AND line_index=? AND status NOT IN ('Completed','Cancelled') AND tailor_id IS NOT NULL",sale.id,l.original_line_index);
        operations.push(m.update('work_items',"quantity=MIN(quantity,?),status=CASE WHEN ?=0 THEN 'Cancelled' ELSE status END,version=version+1,updated_at=?",[remaining,remaining,m.time],"order_id=? AND line_index=? AND status NOT IN ('Completed','Cancelled')",sale.id,l.original_line_index));
        operations.push(...affected.map(task=>m.assigned(task.id,remaining===0?'work_cancelled':'work_changed')));
      }
      operations.push(m.notify(type,isCancel?'Invoice cancelled':'Refund recorded',`Invoice ${sale.bill} has a linked ${type} document.`,MANAGEMENT_ROLES),m.sync());
    }
    await m.save(operations);return {document:(await first('SELECT * FROM orders WHERE id=?',id))!,order:(await first('SELECT * FROM orders WHERE id=?',sale.id))!};
  }
  return {options,write};
}
