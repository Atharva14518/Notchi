import {afterEach,describe,it,expect,vi} from 'vitest';
import {authenticate,authToken} from '../src/auth';
import {createApp} from '../src/index';
import type {Env} from '../src/types';
const owner='11111111-1111-4111-8111-111111111111';
const limiter={limit:async()=>({success:true})};
const env={PUBLIC_BASE_URL:'https://links.example.test',SUPABASE_URL:'https://auth.example.test',SUPABASE_ANON_KEY:'public-test',API_LIMITER:limiter,AUTH_LIMITER:limiter,PUBLIC_LIMITER:limiter,ABUSE_HASH_KEY:'a'.repeat(64)} as unknown as Env;
afterEach(()=>vi.unstubAllGlobals());
describe('Supabase auth boundary',()=>{
 it('requires server-verified identity and rejects expired/invalid tokens',async()=>{
  vi.stubGlobal('fetch',vi.fn(async()=>new Response(JSON.stringify({id:owner}),{status:200})));
  expect(await authenticate(new Request('https://links.example.test',{headers:{Authorization:'Bearer test-token'}}),env)).toBe(owner);
  vi.stubGlobal('fetch',vi.fn(async()=>new Response('{}',{status:401})));
  await expect(authenticate(new Request('https://links.example.test',{headers:{Authorization:'Bearer expired'}}),env)).rejects.toThrow('sign_in_required');
 });
 it('passes magic-link redirect as the actual GoTrue query parameter with PKCE',async()=>{
  let endpoint:URL|undefined,payload:Record<string,unknown>|undefined;
  vi.stubGlobal('fetch',vi.fn(async(input:URL|string,init:RequestInit)=>{endpoint=new URL(input);payload=JSON.parse(String(init.body));return new Response('{}',{status:200});}));
  const app=createApp();
  const response=await app.fetch(new Request('https://links.example.test/v1/auth/email',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({state:'s'.repeat(43),challenge:'c'.repeat(43),email:'person@example.test'})}),env);
  expect(response.status).toBe(200);expect(endpoint?.pathname).toBe('/auth/v1/otp');
  expect(new URL(endpoint!.searchParams.get('redirect_to')!).pathname).toBe('/auth/callback');
  expect(payload?.code_challenge).toBe('c'.repeat(43));expect(payload?.email_redirect_to).toBeUndefined();
 });
 it('returns rotated credentials and verifies the returned user UUID',async()=>{
  vi.stubGlobal('fetch',vi.fn(async()=>new Response(JSON.stringify({access_token:'short-access',refresh_token:'rotated-refresh',expires_in:900,user:{id:owner}}),{status:200})));
  const reply=await authToken(env,'refresh_token',{refresh_token:'old-refresh'});expect(reply.refreshToken).toBe('rotated-refresh');expect(reply.expiresIn).toBe(900);expect(reply.userId).toBe(owner);
 });
 it('never forwards auth callbacks to an arbitrary client-provided redirect',async()=>{
  const app=createApp();const response=await app.fetch(new Request(`https://links.example.test/auth/callback?state=${'s'.repeat(43)}&code=code&redirect=https://evil.test`),env);
  const location=new URL(response.headers.get('Location')!);expect(location.protocol).toBe('notchi:');expect(location.host).toBe('auth');
 });
});
