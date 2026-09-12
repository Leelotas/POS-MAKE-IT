import {createClient} from '@supabase/supabase-js';
import {parseSlipTime} from '@/lib/slip-time';

export const runtime='nodejs';
const MAX_OCR_BYTES=5*1024*1024;
const OCR_PROMPT=`Extract all text from this Thai bank transfer slip. Return only clean Markdown. Include every visible date and time exactly as printed. Do not explain or guess missing text.`;

export async function POST(request:Request){
 try{
  const token=request.headers.get('authorization')?.replace(/^Bearer\s+/i,'');
  const url=process.env.NEXT_PUBLIC_SUPABASE_URL,key=process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;
  if(!token||!url||!key)return Response.json({error:'กรุณาเข้าสู่ระบบใหม่'},{status:401});
  const sb=createClient(url,key,{auth:{persistSession:false,autoRefreshToken:false}});
  const{data:{user},error:userError}=await sb.auth.getUser(token);
  if(userError||!user)return Response.json({error:'เซสชันหมดอายุ กรุณาเข้าสู่ระบบใหม่'},{status:401});
  const apiKey=process.env.TYPHOON_OCR_API_KEY;
  if(!apiKey)return Response.json({error:'ยังไม่ได้ตั้งค่า OpenTyphoon API Key'},{status:503});
  const form=await request.formData(),image=form.get('image');
  if(!(image instanceof File))return Response.json({error:'กรุณาแนบรูปสลิป'},{status:400});
  if(!['image/jpeg','image/png'].includes(image.type))return Response.json({error:'OCR รองรับรูป JPG หรือ PNG เท่านั้น'},{status:400});
  if(image.size<=0||image.size>MAX_OCR_BYTES)return Response.json({error:'รูปสำหรับ OCR ต้องมีขนาดไม่เกิน 5 MB'},{status:400});
  const base64=Buffer.from(await image.arrayBuffer()).toString('base64');
  const response=await fetch('https://api.opentyphoon.ai/v1/chat/completions',{method:'POST',headers:{Authorization:`Bearer ${apiKey}`,'Content-Type':'application/json'},body:JSON.stringify({model:'typhoon-ocr',messages:[{role:'user',content:[{type:'text',text:OCR_PROMPT},{type:'image_url',image_url:{url:`data:${image.type};base64,${base64}`}}]}],max_tokens:4096,temperature:0.1,top_p:0.6,repetition_penalty:1.1})});
  const payload=await response.json().catch(()=>null) as {choices?:{message?:{content?:string}}[];error?:{message?:string}}|null;
  if(!response.ok)return Response.json({error:response.status===429?'OpenTyphoon ถูกเรียกใช้งานถี่เกินไป กรุณารอสักครู่':payload?.error?.message??'OpenTyphoon อ่านสลิปไม่สำเร็จ'},{status:response.status===429?429:502});
  const text=payload?.choices?.[0]?.message?.content?.trim();
  if(!text)return Response.json({error:'OpenTyphoon ไม่ส่งข้อความจากสลิปกลับมา'},{status:502});
  const detected=parseSlipTime(text);
  if(!detected)return Response.json({error:'อ่านรูปได้ แต่ไม่พบวันและเวลาที่ชัดเจน กรุณาระบุเวลาเอง',text},{status:422});
  return Response.json({detected,text});
 }catch{return Response.json({error:'อ่านสลิปไม่สำเร็จ กรุณาลองใหม่หรือระบุเวลาเอง'},{status:500})}
}
