import {test} from 'node:test';
import assert from 'node:assert/strict';
import {normalizeShiftPolicy,shiftAccess,shiftDate} from './shift-rules.ts';
const staff={id:'one',role:'reception',branches:['zahra','avenues']};
const policy=(weekly,exceptions=[])=>({...normalizeShiftPolicy({enabled:true,weekly,exceptions},staff.branches),revision:1});
const access=(p,date)=>shiftAccess(staff,p,new Date(date));
test('Kuwait shifts have exact boundaries, split breaks and assigned branches',()=>{
  const p=policy([{day:1,start:'09:00',end:'12:00',branch:'zahra'},{day:1,start:'13:00',end:'17:00',branch:'avenues'}]);
  assert.equal(access(p,'2026-11-16T05:59:59.999Z').allowed,false);
  assert.deepEqual(access(p,'2026-11-16T06:00:00Z').allowedBranches,['zahra']);
  assert.equal(access(p,'2026-11-16T09:30:00Z').allowed,false);
  assert.deepEqual(access(p,'2026-11-16T10:00:00Z').allowedBranches,['avenues']);
  assert.equal(access(p,'2026-11-16T14:00:00Z').allowed,false);
});
test('overnight and week-wrap shifts end correctly; a dated day off overrides carry-in hours',()=>{
  const shift={day:6,start:'22:00',end:'06:00',branch:''};
  assert.equal(access(policy([shift]),'2026-11-15T02:00:00Z').allowed,true);
  assert.equal(access(policy([shift]),'2026-11-15T03:00:00Z').allowed,false);
  const p=policy([shift],[{date:'2026-11-15',off:true,periods:[]}]);
  assert.equal(access(p,'2026-11-14T20:00:00Z').endsAt,'2026-11-14T21:00:00.000Z');
  assert.equal(access(p,'2026-11-15T02:00:00Z').allowed,false);
});
test('temporary working-day exceptions replace weekly hours and expire with their date',()=>{
  const p=policy([],[{date:'2026-11-18',off:false,periods:[{start:'10:00',end:'12:00',branch:'zahra'}]}]);
  assert.equal(access(p,'2026-11-18T08:00:00Z').allowed,true);
  assert.equal(access(p,'2026-11-19T08:00:00Z').allowed,false);
  assert.equal(shiftAccess({...staff,role:'admin'},policy([]),new Date('2026-11-18')).allowed,true);
  assert.equal(shiftAccess(staff,null).allowed,true);
  assert.equal(shiftAccess(staff,{enabled:false}).allowed,true);
  assert.equal(access(policy([]),'2026-11-18T08:00:00Z').allowed,false);
});
test('invalid times, dates, branches and overlapping windows cannot become a policy',()=>{
  for(const value of ['2026-99-99','2026-02-30','not-a-date'])assert.throws(()=>shiftDate(value));
  for(const start of ['25:00','09:60','24:00','nine'])assert.throws(()=>policy([{day:1,start,end:'17:00',branch:''}]));
  assert.throws(()=>policy([{day:1,start:'09:00',end:'17:00',branch:'unknown'}]));
  assert.throws(()=>policy([{day:6,start:'23:00',end:'03:00',branch:''},{day:0,start:'02:00',end:'06:00',branch:''}]));
  assert.throws(()=>policy([{day:2,start:'04:00',end:'12:00',branch:''}],[{date:'2026-11-16',off:false,periods:[{start:'23:00',end:'06:00',branch:''}]}]));
  assert.equal(access(policy([{day:1,start:'00:00',end:'24:00',branch:''}]),'2026-11-16T20:59:00Z').allowed,true);
});
