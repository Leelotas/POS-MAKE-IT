import {spawn} from 'node:child_process';
process.loadEnvFile('.env.local');
const cli=process.argv[2];
if(!cli)throw new Error('Pass the installed Vercel CLI entrypoint');
for(const key of ['NEXT_PUBLIC_SUPABASE_URL','NEXT_PUBLIC_SUPABASE_ANON_KEY','SUPABASE_SERVICE_ROLE_KEY','CRON_SECRET']){
 const value=process.env[key];if(!value)throw new Error(`Missing ${key}`);
 await new Promise((resolve,reject)=>{
  const child=spawn(process.execPath,[cli,'env','add',key,'production,preview','--yes',key.startsWith('NEXT_PUBLIC_')?'--no-sensitive':'--sensitive','--scope','lee-co'],{stdio:['pipe','pipe','pipe'],windowsHide:true});
  let diagnostic='';child.stdout.on('data',d=>diagnostic+=d);child.stderr.on('data',d=>diagnostic+=d);
  child.on('error',reject);child.on('exit',code=>code===0?resolve():reject(new Error(`Failed to configure ${key}: ${diagnostic.replaceAll(value,'[REDACTED]')}`)));
  child.stdin.end(value);
 });console.log(`Configured ${key} for preview and production.`);
}
