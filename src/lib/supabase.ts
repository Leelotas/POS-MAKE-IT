import { createClient, type SupabaseClient } from '@supabase/supabase-js';
let client:SupabaseClient|undefined;
export function supabase(){
 const url=process.env.NEXT_PUBLIC_SUPABASE_URL;
 const key=process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;
 if(!url||!key) throw new Error('ยังไม่ได้ตั้งค่าการเชื่อมต่อร้าน กรุณาติดต่อผู้ดูแลระบบ');
 return client??=createClient(url,key,{auth:{persistSession:true,autoRefreshToken:true,detectSessionInUrl:true}});
}
export async function rpc<T=unknown>(name:string,args:Record<string,unknown>={}){
 const {data,error}=await supabase().rpc(name,args);
 if(error)throw new Error(error.message);
 return data as T;
}
export async function upload(shopId:string,file:File){
 if(!['image/jpeg','image/png','image/webp'].includes(file.type))throw new Error('ใช้ภาพ JPG, PNG หรือ WebP เท่านั้น');
 if(file.size>10*1024*1024)throw new Error('ภาพต้องมีขนาดไม่เกิน 10 MB');
 const ext=file.type.split('/')[1]; const path=`${shopId}/${crypto.randomUUID()}.${ext}`;
 const {error}=await supabase().storage.from('makeit-private').upload(path,file,{contentType:file.type,upsert:false});
 if(error)throw new Error('อัปโหลดภาพไม่สำเร็จ กรุณาลองอีกครั้ง');
 return path;
}
export async function signedImage(path:string){
 const {data,error}=await supabase().storage.from('makeit-private').createSignedUrl(path,300);
 if(error)throw error;return data.signedUrl;
}
