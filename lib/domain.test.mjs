import { test } from 'node:test';
import assert from 'node:assert/strict';
import {calculate,canAccess,kuwaitDay,integer} from './domain.ts';
const catalogue=[{id:'1001',name:'Hem',category:'Skirt',price:2000},{id:'extra',name:'Additional service',price:0}];
const input=(extra={})=>({lines:[{id:'1001',qty:3,price:2000}],...extra});
test('prices and coupon rounding stay in integer fils',()=>{
  assert.equal(calculate(input({coupon:'dar-usha'}),catalogue,false).total,5100);
  assert.equal(calculate({lines:[{id:'extra',qty:1,price:1001}],coupon:'dar-usha'},catalogue,false).discount,150);
});
test('cashier cannot forge a fixed price or manual discount',()=>{
  assert.throws(()=>calculate({lines:[{id:'1001',qty:1,price:1}]},catalogue,false),/manager/);
  assert.throws(()=>calculate(input({discount:1}),catalogue,false),/manager/);
  assert.throws(()=>calculate(input({extra:1}),catalogue,false),/manager/);
});
test('custom-priced services allowed and manager overrides supported',()=>{
  assert.equal(calculate({lines:[{id:'extra',qty:2,price:1250}]},catalogue,false).total,2500);
  assert.equal(calculate({lines:[{id:'1001',qty:1,price:1500}]},catalogue,true).total,1500);
});
test('invalid money and quantity cannot enter financial records',()=>{
  for(const qty of [0,-1,1.5,NaN,Infinity,1000]) assert.throws(()=>calculate({lines:[{id:'1001',qty,price:2000}]},catalogue,true));
  for(const price of [-1,1.5,NaN,Infinity,'2000']) assert.throws(()=>integer(price,'Price'));
  assert.throws(()=>calculate(input({discount:6001}),catalogue,true),/exceeds/);
  assert.throws(()=>calculate(input({coupon:'forged'}),catalogue,true),/coupon/);
});
test('unavailable items and empty sales rejected',()=>{
  assert.throws(()=>calculate({lines:[]},catalogue,true));
  assert.throws(()=>calculate(input(),[{...catalogue[0],active:0}],true),/available/);
});
test('branch access requires assignment and active membership',()=>{
  assert.equal(canAccess({role:'cashier',branches:['zahra']},'zahra'),true);
  assert.equal(canAccess({role:'cashier',branches:['zahra']},'avenues'),false);
  assert.equal(canAccess({role:'admin',branches:[]},'avenues'),true);
  assert.equal(canAccess({role:'admin',branches:[],active:0},'avenues'),false);
  assert.equal(canAccess({role:'admin',branches:[]},'made-up'),false);
});
test('business dates use Kuwait timezone across UTC midnight',()=>{
  assert.equal(kuwaitDay(new Date('2026-10-29T21:01:00Z')),'2026-10-30');
  assert.equal(kuwaitDay(new Date('2026-10-29T20:59:00Z')),'2026-10-29');
});
