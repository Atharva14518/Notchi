import {afterEach,describe,it,expect,vi} from 'vitest';
import {SupabaseDatabase} from '../src/database';
import type {Env} from '../src/types';
const env={SUPABASE_URL:'https://metadata.example.test',SUPABASE_SERVICE_ROLE_KEY:'server-test-only'} as Env;
const owner='11111111-1111-4111-8111-111111111111';
afterEach(()=>vi.unstubAllGlobals());
describe('PostgREST response formats',()=>{
 it('accepts empty 200 and 204 bodies from real void mutations',async()=>{
  for(const status of [200,204]) {
   vi.stubGlobal('fetch',vi.fn(async()=>new Response(null,{status})));
   const db=new SupabaseDatabase(env);
   await expect(db.revoke(owner,owner)).resolves.toBeUndefined();
   await expect(db.cancel(owner,owner)).resolves.toBeUndefined();
   await expect(db.release(owner,owner)).resolves.toBeUndefined();
   await expect(db.removeExpired(owner)).resolves.toBeUndefined();
  }
 });
 it('still parses JSON results and hides unknown database error details',async()=>{
  vi.stubGlobal('fetch',vi.fn(async()=>new Response('{"maxBytes":100000000,"maxActiveLinks":5,"activeLinks":0}')));
  const db=new SupabaseDatabase(env);
  expect((await db.limits(owner,1000000000,50)).maxActiveLinks).toBe(5);
  vi.stubGlobal('fetch',vi.fn(async()=>new Response('{"message":"private SQL details"}',{status:500})));
  await expect(db.revoke(owner,owner)).rejects.toThrow('metadata_unavailable');
 });
});
