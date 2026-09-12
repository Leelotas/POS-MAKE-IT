import {test} from 'node:test';
import assert from 'node:assert/strict';
import {report,thaiDay} from '../src/lib/reports';
import {emptySnapshot,type Snapshot} from '../src/lib/types';
import {salesTemplateRows} from '../src/lib/exports';
test('Thai midnight, voided bills, weighted costs and cash flow are distinct',()=>{
 assert.equal(thaiDay('2026-09-08T16:59:59Z'),'2026-09-08');
 assert.equal(thaiDay('2026-09-08T17:00:00Z'),'2026-09-09');
 const data={...emptySnapshot,
 products:[{id:'p',name:'สินค้า',price:100,average_cost:60,stock:8}],
 sales:[{id:'s',total:200,cost:120,payment:'cash',created_at:'2026-09-08T17:00:00Z',customer_type:'Student',time_source:'manual',ocr_detected_at:null,voided_at:null},{id:'v',total:100,cost:60,payment:'transfer',created_at:'2026-09-09T03:00:00Z',customer_type:'Office',time_source:'slip_ocr',ocr_detected_at:'2026-09-09T03:00:00Z',voided_at:'2026-09-09T04:00:00Z'}],
 items:[{sale_id:'s',name:'สินค้า',quantity:2,price:100},{sale_id:'v',name:'สินค้า',quantity:1,price:100}],
 entries:[{kind:'income',amount:30,occurred_at:'2026-09-09T04:00:00Z'},{kind:'expense',amount:20,occurred_at:'2026-09-09T04:00:00Z'},{kind:'purchase',amount:600,occurred_at:'2026-09-09T04:00:00Z'}]
 } as Snapshot;
 const r=report(data,'2026-09-09','2026-09-09');
 assert.equal(r.revenue,200);assert.equal(r.gross,80);assert.equal(r.net,90);assert.equal(r.cashIn,230);assert.equal(r.cashOut,620);assert.equal(r.cashNet,-390);assert.equal(r.expected,320);assert.equal(r.stockValue,480);assert.equal(r.bills,1);assert.equal(r.units,2);assert.equal(r.transfer,0);
 assert.deepEqual(salesTemplateRows(data,'2026-09-09','2026-09-09'),[['2026-09-09','00:00','สินค้า',2,100,200,'Student','']]);
});
