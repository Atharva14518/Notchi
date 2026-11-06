import { Hono } from 'hono';
import { bodyLimit } from 'hono/body-limit';
import type { ContentfulStatusCode } from 'hono/utils/http-status';
import { authenticate, authRedirect, authRequest, authToken } from './auth';
import { anonymousKey, equal, hashPassword, hmac, randomToken, verifyPassword } from './crypto';
import { downloadTTL, expiryAt, isExpired, PENDING_TTL_SECONDS, Problem, uuid, validSlug, validateFile, validateLimit, validatePassword } from './domain';
import { SupabaseDatabase } from './database';
import { gonePage, page, reportPage, sharePage } from './pages';
import { localMode, localObject, R2Storage } from './storage';
import type { Database, Env, Share, Storage } from './types';
interface Dependencies { db(env:Env):Database; storage(env:Env):Storage; user(request:Request,env:Env):Promise<string>; now():Date; }
const defaults: Dependencies = {db:env=>new SupabaseDatabase(env),storage:env=>new R2Storage(env),user:authenticate,now:()=>new Date()};
function caps(env:Env) {
  const n=(value:string,fallback:number,max:number)=>Number.isSafeInteger(Number(value))&&Number(value)>0 ? Math.min(max,Number(value)) : fallback;
  return {bytes:n(env.PAID_MAX_BYTES,1_000_000_000,5_000_000_000),links:n(env.PAID_MAX_LINKS,50,1000)};
}
function active(s:Share|null,now:Date):s is Share { return !!s && !s.revoked_at && !isExpired(s.expires_at,now) && (s.download_limit===null || s.download_count<s.download_limit); }
function dto(s:Share,env:Env) {
 return {id:s.id,fileId:s.upload_id,filename:s.filename,size:s.size,url:`${env.PUBLIC_BASE_URL}/s/${s.slug}`,expiresAt:s.expires_at,
   createdAt:s.created_at,passwordProtected:!!s.password_hash,downloadLimit:s.download_limit,downloadCount:s.download_count,revoked:!!s.revoked_at};
}
function sameOrigin(request:Request,env:Env) {
  const origin=request.headers.get('Origin'),site=request.headers.get('Sec-Fetch-Site');
  // Fetch serializes a no-referrer HTML form's Origin as "null". Preserve
  // private share paths while accepting only browser-attested same-origin
  // submissions in that case. Sandboxed/cross-site null origins stay blocked.
  // https://fetch.spec.whatwg.org/#append-a-request-origin-header
  const privateForm=origin==='null' && site==='same-origin';
  if (origin && origin!==new URL(env.PUBLIC_BASE_URL).origin && !privateForm) throw new Problem('invalid_origin',403);
  if (site && site!=='same-origin' && site!=='none') throw new Problem('invalid_origin',403);
}
export function createApp(overrides:Partial<Dependencies>={}) {
 const d={...defaults,...overrides};
 const app=new Hono<{Bindings:Env;Variables:{user:string;ipHash:string}}>();
 app.use('*',async(c,next)=>{
   c.header('Cache-Control','no-store'); c.header('Referrer-Policy','no-referrer'); c.header('X-Content-Type-Options','nosniff');
   c.header('Content-Security-Policy',"default-src 'none'; style-src 'unsafe-inline'; form-action 'self'; frame-ancestors 'none'; base-uri 'none'");
   if (!c.req.path.startsWith('/local/objects/')) {
     const key=await anonymousKey(c.req.header('CF-Connecting-IP') ?? 'local',c.env.ABUSE_HASH_KEY);
     c.set('ipHash',key);
     const limiter=c.req.path.startsWith('/v1/auth/')?c.env.AUTH_LIMITER:c.req.path.startsWith('/v1/')?c.env.API_LIMITER:c.env.PUBLIC_LIMITER;
     if (!(await limiter.limit({key})).success) throw new Problem('rate_limited',429);
   }
   await next();
 });
 app.use('/v1/*',bodyLimit({maxSize:16_384,onError:c=>c.json({error:'request_too_large'},413)}));
 app.use('/s/*',bodyLimit({maxSize:4096,onError:c=>c.html(gonePage(),413)}));
 app.use('/v1/*',async(c,next)=>{
   if (!c.req.path.startsWith('/v1/auth/')) {
     const user=await d.user(c.req.raw,c.env); c.set('user',user);
     if (!(await c.env.API_LIMITER.limit({key:`user:${user}`})).success) throw new Problem('rate_limited',429);
   }
   await next();
 });
 app.get('/health',c=>c.json({ok:true}));
 app.get('/local/preview',c=>{
   if (!localMode(c.env)) return c.html(gonePage(),404);
   const sample:Share={id:crypto.randomUUID(),upload_id:crypto.randomUUID(),owner_id:crypto.randomUUID(),slug:'p'.repeat(24),filename:'Notchi quick guide.pdf',size:4200000,object_key:'preview-only',expires_at:new Date(Date.now()+86400000).toISOString(),revoked_at:null,password_hash:null,download_limit:5,download_count:0,created_at:new Date().toISOString()};
   return c.html(sharePage(sample));
 });
 app.post('/v1/auth/apple',async c=>{
   const {state,challenge}=authRequest(await c.req.json());
   const url=new URL(`${c.env.SUPABASE_URL}/auth/v1/authorize`);
   url.searchParams.set('provider','apple'); url.searchParams.set('redirect_to',authRedirect(c.env,state));
   url.searchParams.set('code_challenge',challenge); url.searchParams.set('code_challenge_method','s256');
   return c.json({authorizationURL:url.toString()});
 });
 app.post('/v1/auth/email',async c=>{
   const value=await c.req.json(),{state,challenge}=authRequest(value),email=value.email;
   if (typeof email!=='string' || email.length>254 || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) throw new Problem('invalid_email');
   const emailKey=await anonymousKey(email.trim().toLowerCase(),c.env.ABUSE_HASH_KEY);
   if (!(await c.env.AUTH_LIMITER.limit({key:`email:${emailKey}`})).success) throw new Problem('rate_limited',429);
   const endpoint=new URL(`${c.env.SUPABASE_URL}/auth/v1/otp`); endpoint.searchParams.set('redirect_to',authRedirect(c.env,state));
   const response=await fetch(endpoint,{method:'POST',headers:{apikey:c.env.SUPABASE_ANON_KEY,'Content-Type':'application/json'},body:JSON.stringify({email:email.trim(),create_user:true,code_challenge:challenge,code_challenge_method:'s256'})});
   if (!response.ok) throw new Problem('email_unavailable',503);
   return c.json({ok:true});
 });
 app.get('/auth/callback',c=>{
   const state=c.req.query('state'),code=c.req.query('code');
   if (!state || !/^[\w-]{43,128}$/.test(state) || !code || !/^[\w-]{1,512}$/.test(code)) return c.html(page('Sign-in failed','<h1>Try signing in again.</h1><p>Return to Notchi to start a fresh sign-in.</p>'),400);
   const redirect=new URL('notchi://auth/callback'); redirect.searchParams.set('state',state); redirect.searchParams.set('code',code);
   return c.redirect(redirect.toString(),302);
 });
 app.post('/v1/auth/exchange',async c=>{
   const b=await c.req.json();
   if (typeof b.code!=='string' || !/^[\w-]{1,512}$/.test(b.code) || typeof b.verifier!=='string' || !/^[\w-]{43,128}$/.test(b.verifier)) throw new Problem('invalid_auth_request');
   return c.json(await authToken(c.env,'pkce',{auth_code:b.code,code_verifier:b.verifier}));
 });
 app.post('/v1/auth/refresh',async c=>{
   const b=await c.req.json(); if (typeof b.refreshToken!=='string' || b.refreshToken.length>8192) throw new Problem('invalid_auth_request');
   return c.json(await authToken(c.env,'refresh_token',{refresh_token:b.refreshToken}));
 });
 app.post('/v1/auth/logout',async c=>{
   const auth=c.req.header('Authorization'); if (!auth || auth.length>8192) throw new Problem('sign_in_required',401);
   await fetch(`${c.env.SUPABASE_URL}/auth/v1/logout?scope=local`,{method:'POST',headers:{apikey:c.env.SUPABASE_ANON_KEY,Authorization:auth}});
   return c.json({ok:true});
 });
 app.get('/v1/me',async c=>{
   const cap=caps(c.env); return c.json({userId:c.get('user'),...await d.db(c.env).limits(c.get('user'),cap.bytes,cap.links)});
 });
 app.post('/v1/uploads/init',async c=>{
   const b=await c.req.json(),file=validateFile(b.filename,b.size,b.mime),id=crypto.randomUUID(),cap=caps(c.env);
   const upload=await d.db(c.env).reserve(c.get('user'),id,file.name,file.size,file.mime,new Date(d.now().getTime()+PENDING_TTL_SECONDS*1000).toISOString(),cap.bytes,cap.links);
   const signed=await d.storage(c.env).uploadURL(upload);
   return c.json({fileId:id,uploadURL:signed.url,headers:signed.headers,uploadExpiresAt:new Date(d.now().getTime()+900_000).toISOString()},201);
 });
 app.get('/v1/uploads/:id',async c=>{
   const upload=await d.db(c.env).pending(c.get('user'),uuid(c.req.param('id'))); if (!upload) throw new Problem('upload_expired',410);
   const signed=await d.storage(c.env).uploadURL(upload);
   return c.json({fileId:upload.id,uploadURL:signed.url,headers:signed.headers,uploadExpiresAt:new Date(Math.min(d.now().getTime()+900_000,new Date(upload.pending_until).getTime())).toISOString()});
 });
 app.delete('/v1/uploads/:id',async c=>{ await d.db(c.env).cancel(c.get('user'),uuid(c.req.param('id'))); return c.json({ok:true}); });
 app.post('/v1/uploads/complete',async c=>{
   const b=await c.req.json(),id=uuid(b.fileId),expires=expiryAt(b.expiry,d.now()),limit=validateLimit(b.downloadLimit),password=validatePassword(b.password);
   const db=d.db(c.env),storage=d.storage(c.env),owner=c.get('user');
   const existing=await db.ownedShare(owner,id);
   if (existing) { if (!active(existing,d.now())) throw new Problem('link_unavailable',410); return c.json(dto(existing,c.env)); }
   const upload=await db.claim(owner,id);
   try {
     await storage.validateAndPromote(upload);
     const hash=await hashPassword(password,c.env.PASSWORD_PEPPER);
     const share=await db.complete(owner,id,randomToken(),expires.toISOString(),hash,limit);
     // Cleanup is retryable via the staging sweep. Publication has committed.
     c.executionCtx.waitUntil(storage.delete([upload.staging_key]).catch(()=>{}));
     return c.json(dto(share,c.env),201);
   } catch(error) { await db.release(owner,id).catch(()=>{}); throw error; }
 });
 app.get('/v1/links',async c=>c.json({links:(await d.db(c.env).list(c.get('user'))).map(s=>dto(s,c.env))}));
 app.delete('/v1/links/:id',async c=>{ await d.db(c.env).revoke(c.get('user'),uuid(c.req.param('id'))); return c.json({ok:true}); });
 app.get('/s/:slug',async c=>{
   if (!validSlug(c.req.param('slug'))) return c.html(gonePage(),404);
   const share=await d.db(c.env).getShare(c.req.param('slug'));
   return active(share,d.now())?c.html(sharePage(share)):c.html(gonePage(),410);
 });
 app.post('/s/:slug/download',async c=>{
   sameOrigin(c.req.raw,c.env);
   const slug=c.req.param('slug'); if (!validSlug(slug)) return c.html(gonePage(),404);
   const db=d.db(c.env),share=await db.getShare(slug);
   if (!active(share,d.now())) return c.html(gonePage(),410);
   if (share.password_hash) {
     if (!(await c.env.AUTH_LIMITER.limit({key:`password:${c.get('ipHash')}`})).success) throw new Problem('rate_limited',429);
     const body=await c.req.parseBody(),password=body.password;
     if (typeof password!=='string' || password.length>128 || !(await verifyPassword(password,share.password_hash,c.env.PASSWORD_PEPPER))) return c.html(sharePage(share,true),403);
   }
   const ttl=downloadTTL(share.expires_at,d.now()); if (ttl<1) return c.html(gonePage(),410);
   const id=crypto.randomUUID(),expires=Math.floor(d.now().getTime()/1000)+ttl;
   const signature=await hmac(c.env.DOWNLOAD_SIGNING_KEY,`${id}:${expires}`);
   if (!(await db.issueTicket(slug,id,new Date(expires*1000).toISOString()))) return c.html(gonePage(),410);
   return c.redirect(`${c.env.PUBLIC_BASE_URL}/d/${id}?expires=${expires}&signature=${signature}`,303);
 });
 app.get('/d/:id',async c=>{
   const id=uuid(c.req.param('id')),expires=Number(c.req.query('expires'));
   if (!Number.isSafeInteger(expires) || expires<=d.now().getTime()/1000 || expires>d.now().getTime()/1000+31) return c.html(gonePage(),410);
   const signature=await hmac(c.env.DOWNLOAD_SIGNING_KEY,`${id}:${expires}`);
   if (!equal(signature,c.req.query('signature')??'')) return c.html(gonePage(),403);
   const share=await d.db(c.env).consumeTicket(id);
   if (!share) return c.html(gonePage(),410);
   // Stream directly from private R2. No buffering file bytes in Worker memory.
   return d.storage(c.env).openDownload(share);
 });
 app.get('/s/:slug/report',c=>validSlug(c.req.param('slug'))?c.html(reportPage(c.req.param('slug'))):c.html(gonePage(),404));
 app.post('/s/:slug/report',async c=>{
   sameOrigin(c.req.raw,c.env); const slug=c.req.param('slug'),body=await c.req.parseBody();
   if (!validSlug(slug) || !['malware','phishing','copyright','other'].includes(String(body.reason))) throw new Problem('invalid_report');
   await d.db(c.env).report(slug,c.get('ipHash'),String(body.reason)); return c.html(reportPage(slug,true));
 });
 app.on(['PUT','GET'],'/local/objects/:key',c=>localObject(c.req.raw,c.env,c.req.param('key')));
 app.notFound(c=>c.json({error:'not_found'},404));
 app.onError((error,c)=>{
   const known=error instanceof Problem;
   const code=known?error.code:'service_unavailable',status=known?error.status:503;
   // Deliberately no console/logger middleware: exceptions can contain request
   // URLs, signed URLs, credentials and filenames. Surface only stable codes.
   return c.json({error:code},status as ContentfulStatusCode);
 });
 return app;
}
export async function cleanup(env:Env,db:Database=new SupabaseDatabase(env),storage:Storage=new R2Storage(env)) {
 for (const upload of await db.expired()) {
   // Never delete the DB row before both R2 objects are gone: failures retry.
   await storage.delete([upload.staging_key,upload.object_key]); await db.removeExpired(upload.id);
 }
 await storage.sweepStaging();
}
const app=createApp();
export default {fetch:app.fetch,scheduled:(_event:ScheduledController,env:Env,ctx:ExecutionContext)=>ctx.waitUntil(cleanup(env))};
