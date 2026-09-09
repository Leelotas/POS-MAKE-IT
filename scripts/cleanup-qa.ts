import {createClient} from '@supabase/supabase-js';
import {readFile,unlink} from 'node:fs/promises';
process.loadEnvFile('.env.local');
const admin=createClient(process.env.NEXT_PUBLIC_SUPABASE_URL!,process.env.SUPABASE_SERVICE_ROLE_KEY!,{auth:{persistSession:false}});
const accounts=JSON.parse(await readFile('.env.qa','utf8')) as {id:string;email:string}[];
for(const account of accounts){
 const {data:{user},error}=await admin.auth.admin.getUserById(account.id);if(error)throw error;
 if(!user?.user_metadata.makeit_disposable_qa||user.email!==account.email||!user.email.endsWith('@example.invalid'))throw new Error('Refusing to remove a non-QA user');
 const {data:shop,error:shopError}=await admin.from('makeit_shops').select('id').eq('owner_id',account.id).maybeSingle();if(shopError)throw shopError;
 if(shop){
  const{data:files,error}=await admin.storage.from('makeit-private').list(shop.id,{limit:1000});if(error)throw error;
  if(files?.length){const{error}=await admin.storage.from('makeit-private').remove(files.map(f=>`${shop.id}/${f.name}`));if(error)throw error;}
  for(const table of ['makeit_admin_audit','makeit_cash_entries','makeit_movements','makeit_sale_items','makeit_sales','makeit_products']){const{error}=await admin.from(table).delete().eq('shop_id',shop.id);if(error)throw error;}
  const{error:removeShopError}=await admin.from('makeit_shops').delete().eq('id',shop.id).eq('owner_id',account.id);if(removeShopError)throw removeShopError;
 }
 await admin.from('makeit_admin_audit').delete().eq('actor_id',account.id);
 await admin.from('makeit_admins').delete().eq('user_id',account.id);
 const {error:deleteError}=await admin.auth.admin.deleteUser(account.id);if(deleteError)throw deleteError;
 console.log('Removed one verified disposable QA account and its shop data.');
}
await unlink('.env.qa');
