import Decimal from 'decimal.js';
import type {Snapshot} from './types';
export const money=(n:Decimal.Value)=>new Intl.NumberFormat('th-TH',{minimumFractionDigits:2,maximumFractionDigits:2}).format(Number(n));
export const baht=(n:Decimal.Value)=>`฿${money(n)}`;
export function thaiDay(value: string|Date = new Date()){
 const parts=new Intl.DateTimeFormat('en-CA',{timeZone:'Asia/Bangkok',year:'numeric',month:'2-digit',day:'2-digit'}).formatToParts(new Date(value));
 return ['year','month','day'].map(k=>parts.find(p=>p.type===k)!.value).join('-');
}
export const thaiTime=(value:string)=>new Intl.DateTimeFormat('th-TH',{timeZone:'Asia/Bangkok',hour:'2-digit',minute:'2-digit'}).format(new Date(value));
export const thaiDate=(value:string)=>new Intl.DateTimeFormat('th-TH',{timeZone:'Asia/Bangkok',dateStyle:'medium',timeStyle:'short'}).format(new Date(value));
export function report(data:Snapshot,from:string,to:string){
 const inRange=(time:string)=>{const day=thaiDay(time);return day>=from&&day<=to};
 const sales=data.sales.filter(s=>inRange(s.created_at));
 const valid=sales.filter(s=>!s.voided_at);const ids=new Set(valid.map(s=>s.id));
 const items=data.items.filter(i=>ids.has(i.sale_id));
 const entries=data.entries.filter(e=>inRange(e.occurred_at));
 const sum=(xs:Decimal.Value[])=>xs.reduce<Decimal>((a,v)=>a.plus(v),new Decimal(0));
 const revenue=sum(valid.map(s=>s.total));const cost=sum(valid.map(s=>s.cost));
 const income=sum(entries.filter(e=>e.kind==='income').map(e=>e.amount));
 const expense=sum(entries.filter(e=>e.kind==='expense').map(e=>e.amount));
 const purchases=sum(entries.filter(e=>e.kind==='purchase').map(e=>e.amount));
 const gross=revenue.minus(cost),net=gross.plus(income).minus(expense);
 const cashIn=revenue.plus(income),cashOut=expense.plus(purchases);
 const expected=sum(data.products.map(p=>new Decimal(p.price).minus(p.average_cost).times(p.stock)));
 const stockValue=sum(data.products.map(p=>new Decimal(p.average_cost).times(p.stock)));
 return {sales,items,entries,from,to,revenue:revenue.toNumber(),cost:cost.toNumber(),income:income.toNumber(),expense:expense.toNumber(),purchases:purchases.toNumber(),gross:gross.toNumber(),net:net.toNumber(),cashIn:cashIn.toNumber(),cashOut:cashOut.toNumber(),cashNet:cashIn.minus(cashOut).toNumber(),expected:expected.toNumber(),stockValue:stockValue.toNumber(),bills:valid.length,units:items.reduce((a,i)=>a+i.quantity,0),cash:sum(valid.filter(s=>s.payment==='cash').map(s=>s.total)).toNumber(),transfer:sum(valid.filter(s=>s.payment==='transfer').map(s=>s.total)).toNumber()};
}
export const summaryRows=(r:ReturnType<typeof report>):[string,number][]=>[
 ['ยอดขายสุทธิ',r.revenue],['จำนวนบิล',r.bills],['จำนวนชิ้น',r.units],['ยอดขายเงินสด',r.cash],['ยอดขายเงินโอน',r.transfer],['ต้นทุนขาย',r.cost],['กำไรขั้นต้น',r.gross],['รายรับอื่น',r.income],['ค่าใช้จ่ายดำเนินงาน',r.expense],['กำไรสุทธิ',r.net],['ค่าซื้อสินค้าที่จ่ายแล้ว',r.purchases],['เงินเข้ารวม',r.cashIn],['เงินออกรวม',r.cashOut],['เงินสุทธิ',r.cashNet],['มูลค่าสต็อกปัจจุบัน',r.stockValue],['กำไรคาดการณ์จากสต็อกปัจจุบัน',r.expected]
];
