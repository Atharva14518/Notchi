import {execFileSync} from 'node:child_process';
import {readFileSync,writeFileSync,chmodSync} from 'node:fs';
import {fileURLToPath} from 'node:url';
const root=fileURLToPath(new URL('../',import.meta.url));
const cli=fileURLToPath(new URL('../node_modules/.bin/supabase',import.meta.url));
try {
const raw=execFileSync(cli,['status','-o','json'],{cwd:root,encoding:'utf8',stdio:['ignore','pipe','pipe']});
const status=JSON.parse(raw),origin=new URL(status.API_URL);
if(!['127.0.0.1','localhost','[::1]'].includes(origin.hostname))throw new Error('Refusing non-local project credentials');
if(!status.ANON_KEY||!status.SERVICE_ROLE_KEY)throw new Error('Local auth keys unavailable');
const file=new URL('../.dev.vars',import.meta.url);
const values={SUPABASE_URL:origin.origin,SUPABASE_ANON_KEY:status.ANON_KEY,SUPABASE_SERVICE_ROLE_KEY:status.SERVICE_ROLE_KEY};
let content=readFileSync(file,'utf8');
for(const [name,value] of Object.entries(values)){
 const regex=new RegExp(`^${name}=.*$`,'m');content=regex.test(content)?content.replace(regex,`${name}=${value}`):content+`\n${name}=${value}\n`;
}
writeFileSync(file,content,{mode:0o600});chmodSync(file,0o600);
console.log('Connected Worker config to the local Supabase project. Credentials hidden.');
} catch {
 // Child-process errors may contain captured credentials. Never print them.
 console.error('Could not connect local credentials. Run setup:local and start local Supabase first.');
 process.exitCode=1;
}
