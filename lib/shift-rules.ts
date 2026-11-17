import {check,integer,text} from './domain.ts';
import type {Row} from './storage.ts';

const DAY=86400000,WEEK=7*1440;
export function shiftDate(value:unknown){const date=text(value,10),parsed=Date.parse(date+'T12:00:00Z');check(/^\d{4}-\d{2}-\d{2}$/.test(date)&&Number.isFinite(parsed)&&new Date(parsed).toISOString().slice(0,10)===date,'Use a valid date.');return date;}
export function minute(value:unknown,end=false){const time=text(value,5);check(/^([01]\d|2[0-3]):[0-5]\d$/.test(time)||(end&&time==='24:00'),'Use a time in HH:MM format.');return Number(time.slice(0,2))*60+Number(time.slice(3));}
export function normalizeShiftPolicy(input:Row,branches:string[]){
  check(typeof input.enabled==='boolean','Choose whether shift restrictions are enabled.');
  check(Array.isArray(input.weekly)&&input.weekly.length<=35,'Use at most 35 weekly periods.');
  check(Array.isArray(input.exceptions)&&input.exceptions.length<=120,'Use at most 120 dated exceptions.');
  function period(row:Row){check(row&&typeof row==='object'&&!Array.isArray(row),'Invalid shift period.');const start=text(row.start,5),end=text(row.end,5),branch=text(row.branch,100);check(minute(start)!==minute(end,true),'A shift must have a start and end time. Use 24:00 for midnight at the end of a day.');check(!branch||branches.includes(branch),'A shift branch must be assigned to this staff account.');return {start,end,branch};}
  const weekly=input.weekly.map((row:Row)=>({...period(row),day:integer(row.day,'Day',0,6)}));
  const intervals=weekly.map((row:Row)=>{const start=row.day*1440+minute(row.start);let end=row.day*1440+minute(row.end,true);if(end<=start)end+=1440;return {start,end};});
  for(let i=0;i<intervals.length;i++)for(let j=i+1;j<intervals.length;j++)for(const offset of [-WEEK,0,WEEK])check(!(intervals[i].start<intervals[j].end+offset&&intervals[j].start+offset<intervals[i].end),'Weekly shift periods overlap.');
  const exceptions=input.exceptions.map((row:Row)=>{
    check(row&&typeof row==='object'&&!Array.isArray(row)&&typeof row.off==='boolean','Invalid dated exception.');
    const date=shiftDate(row.date);check(Array.isArray(row.periods)&&row.periods.length<=5,'Use at most five periods for an exception.');
    const periods=row.off?[]:row.periods.map(period);check(row.off||periods.length>0,'A working-day exception needs at least one period.');
    const intervals=periods.map((p:Row)=>{const start=minute(p.start);let end=minute(p.end,true);if(end<=start)end+=1440;return {start,end};});
    for(let i=0;i<intervals.length;i++)for(let j=i+1;j<intervals.length;j++)check(!(intervals[i].start<intervals[j].end&&intervals[j].start<intervals[i].end),'Exception shift periods overlap.');
    return {date,off:row.off,periods};
  });
  check(new Set(exceptions.map((e:Row)=>e.date)).size===exceptions.length,'Use one exception per date.');
  const move=(date:string,days:number)=>new Date(Date.parse(date+'T12:00:00Z')+days*DAY).toISOString().slice(0,10);
  function datedIntervals(date:string){
    const exception=exceptions.find((e:Row)=>e.date===date),day=new Date(date+'T12:00:00Z').getUTCDay(),midnight=Date.parse(date+'T00:00:00+03:00');
    const rows=exception?(exception.off?[]:exception.periods):weekly.filter((p:Row)=>p.day===day);
    return rows.map((p:Row)=>{const start=midnight+minute(p.start)*60000;let end=midnight+minute(p.end,true)*60000;if(end<=start)end+=DAY;if(exceptions.some((e:Row)=>e.date===move(date,1)))end=Math.min(end,midnight+DAY);return {start,end};});
  }
  for(const exception of exceptions){
    const windows=[move(exception.date,-1),exception.date,move(exception.date,1)].flatMap(datedIntervals);
    for(let i=0;i<windows.length;i++)for(let j=i+1;j<windows.length;j++)check(!(windows[i].start<windows[j].end&&windows[j].start<windows[i].end),'A dated exception overlaps an adjacent overnight shift.');
  }
  return {enabled:input.enabled,weekly,exceptions};
}
export function shiftAccess(member:Row,policy:Row|null,now=new Date()){
  const serverTime=now.toISOString(),assigned=typeof member.branches==='string'?JSON.parse(member.branches):member.branches;
  if(member.role==='admin'||!policy?.enabled)return {enabled:false,allowed:true,allowedBranches:assigned??[],endsAt:null,serverTime,reason:'',revision:policy?.revision??0};
  const weekly=typeof policy.weekly==='string'?JSON.parse(policy.weekly):policy.weekly;
  const exceptions=typeof policy.exceptions==='string'?JSON.parse(policy.exceptions):policy.exceptions;
  const local=new Intl.DateTimeFormat('en-CA',{timeZone:'Asia/Kuwait',year:'numeric',month:'2-digit',day:'2-digit'}).format(now);
  const previous=new Date(new Date(local+'T12:00:00Z').getTime()-DAY).toISOString().slice(0,10);
  const todayException=exceptions.find((e:Row)=>e.date===local);
  if(todayException?.off)return {enabled:true,allowed:false,allowedBranches:[],endsAt:null,serverTime,reason:'Scheduled day off',revision:policy.revision??0};
  const windows:Row[]=[];
  for(const date of [previous,local]){
    if(date===previous&&todayException)continue;
    const exception=exceptions.find((e:Row)=>e.date===date);if(exception?.off)continue;
    const day=new Date(date+'T12:00:00Z').getUTCDay();
    const rows=exception?exception.periods:weekly.filter((p:Row)=>p.day===day);
    const midnight=new Date(date+'T00:00:00+03:00').getTime();
    const next=new Date(new Date(date+'T12:00:00Z').getTime()+DAY).toISOString().slice(0,10);
    for(const row of rows){
      const start=midnight+minute(row.start)*60000;let end=midnight+minute(row.end,true)*60000;if(end<=start)end+=DAY;
      if(exceptions.some((e:Row)=>e.date===next))end=Math.min(end,midnight+DAY);
      const allowed=row.branch?[row.branch].filter((b:string)=>assigned.includes(b)):assigned;
      if(start<=now.getTime()&&now.getTime()<end&&allowed.length)windows.push({end,branches:allowed});
    }
  }
  const allowedBranches=[...new Set(windows.flatMap(w=>w.branches))];
  return {enabled:true,allowed:windows.length>0,allowedBranches,endsAt:windows.length?new Date(Math.min(...windows.map(w=>w.end))).toISOString():null,serverTime,reason:windows.length?'':'Outside scheduled shift',revision:policy.revision??0};
}
