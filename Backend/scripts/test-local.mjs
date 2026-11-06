import { readFileSync } from 'node:fs';
import { randomBytes, randomUUID } from 'node:crypto';

// Integration test for this named local development environment only. Secrets,
// signed addresses and test contents stay in memory; output is stable labels.
const env=Object.fromEntries(readFileSync(new URL('../.dev.vars',import.meta.url),'utf8')
 .split('\n').filter(x=>x && !x.startsWith('#')).map(x=>[x.slice(0,x.indexOf('=')),x.slice(x.indexOf('=')+1)]));
const worker='http://127.0.0.1:8787';
let user,token,stage='local configuration';
const uploads=[];
function check(value) { if (!value) throw new Error('assertion'); }
async function request(url,options={},status=200) {
 const response=await fetch(url,{...options,redirect:'manual'});
 if(response.status!==status) {
  console.error(`Unexpected HTTP status: ${response.status}; expected ${status}.`);
  const diagnostic=await response.json().catch(()=>null);
  if(typeof diagnostic?.error==='string' && /^[a-z_]{1,60}$/.test(diagnostic.error)) console.error(`Service code: ${diagnostic.error}`);
  throw new Error('status');
 }
 return response;
}
async function admin(path,options={}) {
 return request(`${env.SUPABASE_URL}/auth/v1/admin/${path}`,{
  ...options,headers:{apikey:env.SUPABASE_SERVICE_ROLE_KEY,Authorization:`Bearer ${env.SUPABASE_SERVICE_ROLE_KEY}`,'Content-Type':'application/json'}
 });
}
async function api(path,body,method=body===undefined?'GET':'POST',status=200) {
 return request(worker+path,{method,headers:{Authorization:`Bearer ${token}`,'Content-Type':'application/json'},body:body===undefined?undefined:JSON.stringify(body)},status);
}
try {
 const origin=new URL(env.SUPABASE_URL);
 check(['127.0.0.1','localhost','[::1]'].includes(origin.hostname));
 check(readFileSync(new URL('../wrangler.local.jsonc',import.meta.url),'utf8').includes('"LOCAL_DEVELOPMENT": "true"'));
 await request(worker+'/health');
 stage='local test identity';
 const email=`notchi-integration-${randomUUID()}@example.test`,password=randomBytes(32).toString('base64url');
 user=(await (await admin('users',{method:'POST',body:JSON.stringify({email,password,email_confirm:true})})).json()).id;
 const auth=await request(`${origin.origin}/auth/v1/token?grant_type=password`,{method:'POST',headers:{apikey:env.SUPABASE_ANON_KEY,'Content-Type':'application/json'},body:JSON.stringify({email,password})});
 token=(await auth.json()).access_token;
 stage='JWT verification and tier limits';
 const profile=await (await api('/v1/me')).json();
 check(profile.userId===user);
 check(profile.maxBytes===100_000_000 && profile.maxActiveLinks===5);
 console.log('PASS verified authentication and free limits');
 const contents=Buffer.from('Notchi disposable local integration fixture.\n'.repeat(1200));
 async function upload(limit) {
  const init=await (await api('/v1/uploads/init',{filename:'local-check.txt',size:contents.length,mime:'text/plain'},'POST',201)).json();
  uploads.push(init.fileId);
  await request(init.uploadURL,{method:'PUT',headers:init.headers,body:contents});
  const options={fileId:init.fileId,expiry:'1h',password:'local-test-only',downloadLimit:limit};
  const share=await (await api('/v1/uploads/complete',options,'POST',201)).json();
  const replay=await (await api('/v1/uploads/complete',options)).json();
  check(replay.id===share.id && replay.url===share.url);
  return {init,share};
 }
 stage='signed upload and immutable completion';
 const {init,share}=await upload(1);
 check(share.size===contents.length && share.passwordProtected && share.downloadLimit===1);
 check(new Date(share.expiresAt)-Date.now()>3590_000);
 const html=await (await request(share.url)).text();
 check(html.includes('local-check.txt') && html.includes('Download'));
 // A still-valid PUT can never mutate the already published object.
 await request(init.uploadURL,{method:'PUT',headers:init.headers,body:Buffer.alloc(contents.length,90)});
 console.log('PASS signed upload, immutable publication and idempotent completion');
 stage='password, bytes and one-use download';
 await request(share.url+'/download',{method:'POST',headers:{'Content-Type':'application/x-www-form-urlencoded'},body:'password=wrong'},403);
 const ticket=await request(share.url+'/download',{method:'POST',headers:{'Content-Type':'application/x-www-form-urlencoded','Origin':'null','Sec-Fetch-Site':'same-origin'},body:'password=local-test-only'},303);
 const address=ticket.headers.get('location');
 const bytes=Buffer.from(await (await request(address)).arrayBuffer());
 check(bytes.equals(contents));
 await request(address,{},410);
 await request(share.url,{},410);
 console.log('PASS password protection, byte equality, ticket replay and download cap');
 stage='revoke and owner list';
 const second=await upload(null);
 await api('/v1/links/'+second.share.id,undefined,'DELETE');
 await request(second.share.url,{},410);
 const list=await (await api('/v1/links')).json();
 check(list.links.some(x=>x.id===second.share.id && x.revoked));
 console.log('PASS owner listing and immediate revocation');
} catch {
 console.error(`FAIL ${stage}. No credentials or addresses printed.`);
 process.exitCode=1;
} finally {
 let cleaned=true;
 for(const id of uploads) { try { await api('/v1/uploads/'+id,undefined,'DELETE'); } catch { cleaned=false; } }
 if(user) { try { await admin('users/'+user,{method:'DELETE'}); } catch { cleaned=false; } }
 if (!cleaned) { console.error('Local test cleanup needs a retry.'); process.exitCode=1; }
}
