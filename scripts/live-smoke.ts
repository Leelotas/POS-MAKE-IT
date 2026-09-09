import {createClient} from '@supabase/supabase-js';
import {readFile,writeFile} from 'node:fs/promises';
import assert from 'node:assert/strict';
import {randomUUID,randomBytes} from 'node:crypto';
process.loadEnvFile('.env.local');
const url=process.env.NEXT_PUBLIC_SUPABASE_URL!,key=process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!;
const admin=createClient(url,process.env.SUPABASE_SERVICE_ROLE_KEY!,{auth:{persistSession:false}});
const credentials=[];
for(let i=0;i<2;i++){
 const email=`makeit-qa-${randomUUID()}@example.invalid`,password=randomBytes(24).toString('base64url');
 const {data,error}=await admin.auth.admin.createUser({email,password,email_confirm:true,user_metadata:{makeit_disposable_qa:true}});
 if(error)throw error;
 credentials.push({email,password,id:data.user.id});
}
await writeFile('.env.qa',JSON.stringify(credentials));
const clients=await Promise.all(credentials.map(async(c)=>{const sb=createClient(url,key,{auth:{persistSession:false}});const{error}=await sb.auth.signInWithPassword(c);if(error)throw error;return sb}));
async function call(i:number,name:string,args:Record<string,unknown>={}){const{data,error}=await clients[i].rpc(name,args);if(error)throw error;return data;}
const shop=await call(0,'makeit_setup_shop',{p_name:'ร้านทดสอบ MAKE IT'});
await call(1,'makeit_setup_shop',{p_name:'ร้านทดสอบการแยกข้อมูล'});
const products=[['กาแฟลาเต้','เครื่องดื่ม',65,28,24],['อเมริกาโน่','เครื่องดื่ม',55,20,18],['ชาไทย','เครื่องดื่ม',50,18,12],['ครัวซองต์เนยสด','เบเกอรี่',75,35,8],['คุกกี้ช็อกโกแลต','เบเกอรี่',45,20,4],['น้ำดื่ม','เครื่องดื่ม',15,7,30]];
const ids:string[]=[];
for(const[name,category,price,cost,stock]of products){const id=randomUUID();ids.push(id);await call(0,'makeit_save_product',{p_id:id,p_name:name,p_category:category,p_price:price,p_cost:cost,p_stock:stock,p_active:true,p_image:null})}
assert.equal((await call(1,'makeit_snapshot')).products.length,0);
const denied=await clients[1].rpc('makeit_checkout',{p_request:randomUUID(),p_items:[{id:ids[0],quantity:1}],p_payment:'cash',p_slip:null});assert.ok(denied.error);
const path=`${shop}/${randomUUID()}.png`;
const {error:uploadError}=await clients[0].storage.from('makeit-private').upload(path,await readFile('public/logo.png'),{contentType:'image/png'});if(uploadError)throw uploadError;
const privateRead=await clients[1].storage.from('makeit-private').createSignedUrl(path,60);assert.ok(privateRead.error,'other tenant cannot open slip');
const request=randomUUID();const args={p_request:request,p_items:[{id:ids[0],quantity:2},{id:ids[3],quantity:1}],p_payment:'transfer',p_slip:path};
await Promise.all([call(0,'makeit_checkout',args),call(0,'makeit_checkout',args)]);
let data=await call(0,'makeit_snapshot');assert.equal(data.sales.length,1);assert.equal(data.products.find((p:any)=>p.id===ids[0]).stock,22);assert.equal(Number(data.sales[0].total),205);
await call(0,'makeit_checkout',{p_request:randomUUID(),p_items:[{id:ids[1],quantity:3}],p_payment:'cash',p_slip:null});
const last=randomUUID();await call(0,'makeit_save_product',{p_id:last,p_name:'ทดสอบสินค้าชิ้นสุดท้าย',p_category:'ทดสอบ',p_price:10,p_cost:5,p_stock:1,p_active:true,p_image:null});
const race=await Promise.allSettled([0,1].map(()=>call(0,'makeit_checkout',{p_request:randomUUID(),p_items:[{id:last,quantity:1}],p_payment:'cash',p_slip:null})));
assert.equal(race.filter(x=>x.status==='fulfilled').length,1,'concurrent last item cannot oversell');
data=await call(0,'makeit_snapshot');const raceSale=data.items.find((i:any)=>i.product_id===last).sale_id;await call(0,'makeit_void',{p_sale:raceSale,p_reason:'ยกเลิกข้อมูลทดสอบการขายพร้อมกัน'});
await call(0,'makeit_save_product',{p_id:last,p_name:'ทดสอบสินค้าชิ้นสุดท้าย',p_category:'ทดสอบ',p_price:10,p_cost:5,p_stock:0,p_active:false,p_image:null});
await call(0,'makeit_stock',{p_request:randomUUID(),p_product:ids[2],p_kind:'purchase',p_quantity:10,p_cost:20,p_paid:true,p_reason:'เติมสินค้าเพื่อทดสอบต้นทุนเฉลี่ย'});
await call(0,'makeit_cash',{p_id:randomUUID(),p_kind:'expense',p_category:'ค่าขนส่ง',p_amount:30,p_note:'ข้อมูลทดสอบ',p_occurred:new Date().toISOString(),p_evidence:null});
await call(0,'makeit_cash',{p_id:randomUUID(),p_kind:'income',p_category:'รายได้บริการ',p_amount:50,p_note:'ข้อมูลทดสอบ',p_occurred:new Date().toISOString(),p_evidence:null});
console.log('LIVE PASS: 2 isolated shops; private slip upload/access; atomic checkout; concurrent duplicate retries; concurrent last-stock sale; void restoration; restock and cash ledger. Temporary QA accounts saved locally for browser tests.');
