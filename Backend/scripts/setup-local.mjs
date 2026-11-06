import {existsSync,writeFileSync} from 'node:fs';
import {randomBytes} from 'node:crypto';
const file=new URL('../.dev.vars',import.meta.url);
if(existsSync(file)){console.log('Local config exists; left unchanged.');process.exit(0);}
const random=()=>randomBytes(32).toString('hex');
writeFileSync(file,`SUPABASE_URL=http://127.0.0.1:54321
SUPABASE_ANON_KEY=SET_LOCAL_SUPABASE_ANON_KEY
SUPABASE_SERVICE_ROLE_KEY=SET_LOCAL_SUPABASE_SERVICE_ROLE_JWT
R2_ACCOUNT_ID=local
R2_ACCESS_KEY_ID=local
R2_SECRET_ACCESS_KEY=local
R2_BUCKET_NAME=notchi-private-files-local
PASSWORD_PEPPER=${random()}
ABUSE_HASH_KEY=${random()}
DOWNLOAD_SIGNING_KEY=${random()}
LOCAL_SIGNING_KEY=${random()}
`,{mode:0o600});
console.log('Created private local config. Add Supabase local keys before signing in.');
