import {createClient} from '@supabase/supabase-js';
export async function GET(request:Request){
 const secret=process.env.CRON_SECRET;
 if(!secret||request.headers.get('authorization')!==`Bearer ${secret}`)return Response.json({error:'Unauthorized'},{status:401});
 const url=process.env.NEXT_PUBLIC_SUPABASE_URL,key=process.env.SUPABASE_SERVICE_ROLE_KEY;
 if(!url||!key)return Response.json({error:'Cleanup configuration missing'},{status:503});
 const sb=createClient(url,key,{auth:{persistSession:false}});
 const {data:paths,error}=await sb.rpc('makeit_cleanup_candidates');
 if(error)return Response.json({error:'Candidate lookup failed'},{status:500});
 let removed=0;
 for(let i=0;i<(paths??[]).length;i+=100){const batch=(paths as string[]).slice(i,i+100);const{error}=await sb.storage.from('makeit-private').remove(batch);if(error)return Response.json({error:'Storage cleanup failed',removed},{status:500});removed+=batch.length;}
 return Response.json({removed});
}
