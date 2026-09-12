import {createClient} from '@supabase/supabase-js';
import {timingSafeEqual} from 'node:crypto';

export const runtime='nodejs';

function sameSecret(input:string,expected:string){
 const a=Buffer.from(input),b=Buffer.from(expected);
 return a.length===b.length&&timingSafeEqual(a,b);
}

export async function POST(request:Request){
 try{
  const token=request.headers.get('authorization')?.replace(/^Bearer\s+/i,'');
  const url=process.env.NEXT_PUBLIC_SUPABASE_URL,anon=process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY,serviceKey=process.env.SUPABASE_SERVICE_ROLE_KEY;
  const expected=process.env.ADMIN_ACTION_SECRET;
  if(!token||!url||!anon)return Response.json({error:'กรุณาเข้าสู่ระบบใหม่'},{status:401});
  if(!serviceKey||!expected)return Response.json({error:'ยังไม่ได้ตั้งรหัสยืนยันสำหรับ Admin บน Vercel'},{status:503});
  const body=await request.json().catch(()=>null) as {shopId?:string;secret?:string}|null;
  if(!body?.shopId||!body.secret)return Response.json({error:'กรุณาระบุร้านและรหัสยืนยัน'},{status:400});
  const userClient=createClient(url,anon,{auth:{persistSession:false,autoRefreshToken:false},global:{headers:{Authorization:`Bearer ${token}`}}});
  const{data:{user},error:userError}=await userClient.auth.getUser(token);
  if(userError||!user)return Response.json({error:'เซสชันหมดอายุ กรุณาเข้าสู่ระบบใหม่'},{status:401});
  const{data:isAdmin,error:adminError}=await userClient.rpc('makeit_is_admin');
  if(adminError||!isAdmin)return Response.json({error:'บัญชีนี้ไม่มีสิทธิ์ Admin'},{status:403});
  if(!sameSecret(body.secret,expected))return Response.json({error:'รหัสยืนยันไม่ถูกต้อง'},{status:403});
  const service=createClient(url,serviceKey,{auth:{persistSession:false,autoRefreshToken:false}}),paths:string[]=[];
  for(let offset=0;;offset+=1000){
   const{data:files,error:listError}=await service.storage.from('makeit-private').list(body.shopId,{limit:1000,offset});
   if(listError)return Response.json({error:'ตรวจไฟล์ของร้านไม่สำเร็จ'},{status:500});
   paths.push(...(files??[]).map(file=>`${body.shopId}/${file.name}`));
   if((files?.length??0)<1000)break;
  }
  const{error:deleteError}=await service.rpc('makeit_admin_delete_shop',{p_shop:body.shopId,p_actor:user.id});
  if(deleteError)return Response.json({error:deleteError.message},{status:400});
  for(let i=0;i<paths.length;i+=100){const{error}=await service.storage.from('makeit-private').remove(paths.slice(i,i+100));if(error)return Response.json({ok:true,warning:'ลบร้านแล้ว แต่มีไฟล์บางส่วนรอการทำความสะอาด'});}
  return Response.json({ok:true});
 }catch{return Response.json({error:'ลบร้านไม่สำเร็จ กรุณาลองใหม่'},{status:500})}
}
