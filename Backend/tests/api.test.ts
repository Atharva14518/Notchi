import {describe,it,expect,vi} from 'vitest';
import {createApp,cleanup} from '../src/index';
import {Problem} from '../src/domain';
import type {Database,Env,Share,Upload,Storage} from '../src/types';
const owner='11111111-1111-4111-8111-111111111111',other='22222222-2222-4222-8222-222222222222',now=new Date('2026-11-05T10:00:00Z');
function fixture(){
 const uploads=new Map<string,Upload>(),shares=new Map<string,Share>(),tickets=new Map<string,string>();
 const db:Database={
  limits:async user=>({maxBytes:100000000,maxActiveLinks:5,activeLinks:[...uploads.values()].filter(x=>x.owner_id===user).length}),
  reserve:async(user,id,filename,size,mime,until)=>{
   if(size>100000000)throw new Problem('too_large');if(uploads.size>=5)throw new Problem('quota_exceeded',409);
   const u={id,owner_id:user,filename,size,mime,staging_key:`staging/${user}/${id}`,object_key:`files/${user}/${id}`,state:'pending',pending_until:until};uploads.set(id,u);return u;
  },
  pending:async(user,id)=>{const u=uploads.get(id);return u?.owner_id===user?u:null;},
  cancel:async(user,id)=>{if(uploads.get(id)?.owner_id===user)uploads.delete(id);},
  claim:async(user,id)=>{const u=uploads.get(id);if(!u||u.owner_id!==user)throw new Problem('upload_missing');if(u.state!=='pending')throw new Problem('upload_busy');u.state='completing';return u;},
  release:async(user,id)=>{const u=uploads.get(id);if(u?.owner_id===user)u.state='pending';},
  complete:async(user,id,slug,expires,hash,limit)=>{const u=uploads.get(id)!;const s={id:crypto.randomUUID(),upload_id:id,owner_id:user,slug,filename:u.filename,size:u.size,object_key:u.object_key,expires_at:expires,password_hash:hash,download_limit:limit,download_count:0,revoked_at:null,created_at:now.toISOString()};u.state='complete';shares.set(slug,s);return s;},
  ownedShare:async(user,id)=>[...shares.values()].find(s=>s.owner_id===user&&s.upload_id===id)??null,
  getShare:async slug=>shares.get(slug)??null,
  issueTicket:async(slug,id)=>{tickets.set(id,slug);return true;},
  consumeTicket:async id=>{const slug=tickets.get(id);if(!slug)return null;tickets.delete(id);return db.download(slug);},
  download:async slug=>{const s=shares.get(slug);if(!s||s.revoked_at||new Date(s.expires_at)<=now||(s.download_limit!==null&&s.download_count>=s.download_limit))return null;s.download_count++;return s;},
  list:async user=>[...shares.values()].filter(s=>s.owner_id===user),
  revoke:async(user,id)=>{const s=[...shares.values()].find(s=>s.owner_id===user&&s.id===id);if(s)s.revoked_at=now.toISOString();},
  report:async()=>{},expired:async()=>[...uploads.values()],removeExpired:async id=>{uploads.delete(id);}
 };
 const storage:Storage={uploadURL:async()=>({url:'https://account.r2.cloudflarestorage.com/bucket/private?signature=secret',headers:{'Content-Type':'application/octet-stream'}}),validateAndPromote:async()=>{},openDownload:async()=>new Response("file bytes"),downloadURL:async()=> 'https://account.r2.cloudflarestorage.com/bucket/final?signature=secret',delete:async()=>{},sweepStaging:async()=>{}};
 const limiter={limit:async()=>({success:true})},env={PUBLIC_BASE_URL:'https://share.example.test',ABUSE_HASH_KEY:'a'.repeat(64),PASSWORD_PEPPER:'p'.repeat(64),DOWNLOAD_SIGNING_KEY:'d'.repeat(64),API_LIMITER:limiter,AUTH_LIMITER:limiter,PUBLIC_LIMITER:limiter,PAID_MAX_BYTES:'1000000000',PAID_MAX_LINKS:'50'} as unknown as Env;
 const app=createApp({db:()=>db,storage:()=>storage,user:async r=>{if(!r.headers.has('Authorization'))throw new Problem('sign_in_required',401);return r.headers.get('Authorization')==='Bearer other'?other:owner;},now:()=>now});
 const ctx={waitUntil:()=>{},passThroughOnException:()=>{}} as unknown as ExecutionContext;
 const request=(path:string,method='GET',body?:unknown,token=true)=>app.fetch(new Request(`https://share.example.test${path}`,{method,headers:{...(token?{Authorization:'Bearer owner'}:{}),'Content-Type':'application/json'},body:body===undefined?undefined:JSON.stringify(body)}),env,ctx);
 async function ready(options:Record<string,unknown>={}){const init=await(await request('/v1/uploads/init','POST',{filename:'scan.pdf',size:100,mime:'application/pdf'})).json() as {fileId:string};return await(await request('/v1/uploads/complete','POST',{fileId:init.fileId,expiry:'1h',...options})).json() as {id:string;url:string;fileId:string};}
 const download=(slug:string,password='',origin='https://share.example.test',site?:string)=>app.fetch(new Request(`https://share.example.test/s/${slug}/download`,{method:'POST',headers:{Origin:origin,'Content-Type':'application/x-www-form-urlencoded',...(site?{'Sec-Fetch-Site':site}:{})},body:new URLSearchParams({password}).toString()}),env,ctx);
 return{db,storage,env,app,ctx,request,ready,download,uploads};
}
describe('HTTP lifecycle',()=>{
 it('authenticates, enforces caps and reserves no sixth free link',async()=>{
  const f=fixture();expect((await f.request('/v1/uploads/init','POST',{},false)).status).toBe(401);
  expect((await f.request('/v1/uploads/init','POST',{filename:'a.pdf',size:100000001,mime:'application/pdf'})).status).toBe(400);
  for(let i=0;i<5;i++)expect((await f.request('/v1/uploads/init','POST',{filename:'a.pdf',size:1,mime:'application/pdf'})).status).toBe(201);
  expect((await f.request('/v1/uploads/init','POST',{filename:'a.pdf',size:1,mime:'application/pdf'})).status).toBe(409);
 });
 it('publishes idempotently and serves mobile HTML without exposing storage secrets',async()=>{
  const f=fixture(),s=await f.ready(),slug=s.url.split('/').pop()!;
  const page=await f.request(`/s/${slug}`);expect(page.status).toBe(200);expect(await page.text()).toContain('name="viewport"');expect(page.headers.get('Referrer-Policy')).toBe('no-referrer');
  const retry=await f.request('/v1/uploads/complete','POST',{fileId:s.fileId,expiry:'7d'});expect((await retry.json() as {id:string}).id).toBe(s.id);
  const mine=await(await f.request('/v1/links')).text();for(const secret of ['password_hash','object_key','staging/'])expect(mine).not.toContain(secret);
 });
 it('rejects wrong passwords and permits only two concurrent download claims',async()=>{
  const f=fixture(),s=await f.ready({password:'correct password',downloadLimit:2}),slug=s.url.split('/').pop()!;
  expect((await f.download(slug,'wrong')).status).toBe(403);
  const r=await Promise.all([f.download(slug,'correct password'),f.download(slug,'correct password'),f.download(slug,'correct password')]);
  expect(r.filter(x=>x.status===303)).toHaveLength(3);
  const downloads=await Promise.all(r.map(x=>f.request(new URL(x.headers.get('Location')!).pathname+new URL(x.headers.get('Location')!).search)));
  expect(downloads.filter(x=>x.status===200)).toHaveLength(2);expect(downloads.filter(x=>x.status===410)).toHaveLength(1);
  const url=new URL(r[0].headers.get('Location')!);expect((await f.request(url.pathname+url.search)).status).toBe(410);
 });
 it('rejects cross-origin counter exhaustion and revoked links',async()=>{
  const f=fixture(),s=await f.ready(),slug=s.url.split('/').pop()!;
  expect((await f.download(slug,'','https://evil.example')).status).toBe(403);
  await f.request(`/v1/links/${s.id}`,'DELETE');expect((await f.request(`/s/${slug}`)).status).toBe(410);
 });
 it('accepts private same-origin browser forms without allowing foreign null origins',async()=>{
  const f=fixture(),s=await f.ready(),slug=s.url.split('/').pop()!;
  expect((await f.download(slug,'','null','same-origin')).status).toBe(303);
  expect((await f.download(slug,'','null','cross-site')).status).toBe(403);
  expect((await f.download(slug,'','null','same-site')).status).toBe(403);
  expect((await f.download(slug,'','null')).status).toBe(403);
 });
 it('isolates owners',async()=>{
  const f=fixture(),s=await f.ready();expect(await f.db.ownedShare(other,s.fileId)).toBeNull();expect(await f.db.list(other)).toHaveLength(0);
 });
 it('keeps records if R2 cleanup fails',async()=>{
  const f=fixture();await f.ready();f.storage.delete=async()=>{throw new Error('unavailable');};await expect(cleanup(f.env,f.db,f.storage)).rejects.toThrow();expect(f.uploads.size).toBe(1);
 });
 it('sanitizes exceptions and never logs signed URLs or private content',async()=>{
  const f=fixture(),spy=vi.spyOn(console,'error').mockImplementation(()=>{});f.storage.validateAndPromote=async()=>{throw new Error('private contents https://example.test/private?token=secret');};
  const init=await(await f.request('/v1/uploads/init','POST',{filename:'a.pdf',size:1,mime:'application/pdf'})).json() as {fileId:string};
  const r=await f.request('/v1/uploads/complete','POST',{fileId:init.fileId,expiry:'1h'});expect(await r.text()).toBe('{"error":"service_unavailable"}');expect(spy).not.toHaveBeenCalled();spy.mockRestore();
 });
});
