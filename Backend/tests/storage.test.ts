import {describe,it,expect} from 'vitest';
import {R2Storage,localMode} from '../src/storage';
import type {Env,Upload} from '../src/types';
const u:Upload={id:'33333333-3333-4333-8333-333333333333',owner_id:'11111111-1111-4111-8111-111111111111',filename:'scan.pdf',size:4,mime:'application/pdf',staging_key:'staging/owner/id',object_key:'files/owner/id',state:'completing',pending_until:'2099-01-01T00:00:00Z'};
describe('R2 capabilities',()=>{
 it('signs content length and type and grants only a short-lived object PUT',async()=>{
  const env={R2_ACCOUNT_ID:'account',R2_BUCKET_NAME:'private',R2_ACCESS_KEY_ID:'example-access',R2_SECRET_ACCESS_KEY:'example-secret'} as Env;
  const signed=await new R2Storage(env).uploadURL(u),url=new URL(signed.url);
  expect(url.searchParams.get('X-Amz-SignedHeaders')).toContain('content-length');
  expect(url.searchParams.get('X-Amz-SignedHeaders')).toContain('content-type');
  expect(url.searchParams.get('X-Amz-Expires')).toBe('900');
  expect(signed.headers['Content-Length']).toBe('4');
 });
 it('publishes a distinct immutable key with attachment metadata',async()=>{
  let body=new Uint8Array([1,2,3,4]),final:Uint8Array|undefined,etag='original',disposition='';
  const bucket={head:async()=>({size:4,etag}),get:async(_key:string,options:{onlyIf:{etagMatches:string}})=>{
   if(options.onlyIf.etagMatches!==etag)return null;
   const snapshot=body.slice();return{size:4,body:new ReadableStream({start(c){c.enqueue(snapshot);c.close();}}),arrayBuffer:async()=>snapshot.buffer};
  },put:async(key:string,stream:ReadableStream,options:{httpMetadata:{contentDisposition:string}})=>{
   expect(key).toBe(u.object_key);const reader=stream.getReader();final=(await reader.read()).value;disposition=options.httpMetadata.contentDisposition;
  }};
  await new R2Storage({FILES:bucket} as unknown as Env).validateAndPromote(u);
  body=new Uint8Array([9,9,9,9]);etag='changed';
  expect(final).toEqual(new Uint8Array([1,2,3,4]));expect(disposition).toContain('attachment');
 });
 it('refuses accidentally deploying the local signing mode on a public host',()=>{
  expect(()=>localMode({LOCAL_DEVELOPMENT:'true',PUBLIC_BASE_URL:'https://public.example'} as Env)).toThrow();
 });
});
