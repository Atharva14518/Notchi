import { AwsClient } from 'aws4fetch';
import { base64url, equal, hmac } from './crypto';
import { blockedMagic, Problem, UPLOAD_TTL_SECONDS } from './domain';
import type { Env, Share, Storage, Upload } from './types';
export function localMode(env: Env): boolean {
  if (env.LOCAL_DEVELOPMENT !== 'true') return false;
  const url = new URL(env.PUBLIC_BASE_URL);
  if (!['localhost','127.0.0.1','[::1]'].includes(url.hostname)) throw new Problem('unsafe_local_configuration',503);
  return true;
}
export class R2Storage implements Storage {
  constructor(private env: Env) {}
  private async signed(key: string, method: 'PUT'|'GET', ttl: number, size = 0): Promise<string> {
    if (localMode(this.env)) {
      const path = `/local/objects/${base64url(new TextEncoder().encode(key))}`;
      const expiry = Math.floor(Date.now()/1000)+ttl;
      const signature = await hmac(this.env.LOCAL_SIGNING_KEY ?? '',`${method}:${path}:${expiry}:${size}`);
      return `${this.env.PUBLIC_BASE_URL}${path}?expires=${expiry}&size=${size}&signature=${signature}`;
    }
    const url = new URL(`https://${this.env.R2_ACCOUNT_ID}.r2.cloudflarestorage.com/${this.env.R2_BUCKET_NAME}/${key}`);
    url.searchParams.set('X-Amz-Expires',String(ttl));
    const signer = new AwsClient({accessKeyId:this.env.R2_ACCESS_KEY_ID,secretAccessKey:this.env.R2_SECRET_ACCESS_KEY,service:'s3',region:'auto'});
    const headers: Record<string,string> = {};
    if (method === 'PUT') { headers['Content-Type']='application/octet-stream'; headers['Content-Length']=String(size); }
    const signed = await signer.sign(url,{method,headers,aws:{signQuery:true,allHeaders:true}});
    return signed.url;
  }
  async uploadURL(upload: Upload) {
    return {url:await this.signed(upload.staging_key,'PUT',UPLOAD_TTL_SECONDS,upload.size),headers:{'Content-Type':'application/octet-stream','Content-Length':String(upload.size)}};
  }
  async validateAndPromote(upload: Upload): Promise<void> {
    const head = await this.env.FILES.head(upload.staging_key);
    if (!head || head.size !== upload.size) throw new Problem('upload_size_mismatch');
    const prefix = await this.env.FILES.get(upload.staging_key,{range:{offset:0,length:Math.min(512,head.size)},onlyIf:{etagMatches:head.etag}});
    if (!prefix || !('body' in prefix) || blockedMagic(new Uint8Array(await prefix.arrayBuffer()))) throw new Problem('blocked_type');
    const source = await this.env.FILES.get(upload.staging_key,{onlyIf:{etagMatches:head.etag}});
    if (!source || !('body' in source) || source.size !== upload.size) throw new Problem('upload_changed');
    // The client can reuse its PUT capability until it expires. Publish an
    // immutable server-only key so that reuse cannot replace the shared file.
    await this.env.FILES.put(upload.object_key,source.body,{httpMetadata:{contentType:'application/octet-stream',contentDisposition:`attachment; filename*=UTF-8''${encodeURIComponent(upload.filename)}`}});
  }
  async openDownload(share: Share): Promise<Response> {
    const object = await this.env.FILES.get(share.object_key);
    if (!object) throw new Problem('link_unavailable',410);
    return new Response(object.body,{headers:{'Content-Type':'application/octet-stream','Content-Disposition':`attachment; filename*=UTF-8''${encodeURIComponent(share.filename).replace(/['()*]/g,c=>'%'+c.charCodeAt(0).toString(16))}`,'Cache-Control':'no-store','X-Content-Type-Options':'nosniff','Content-Length':String(object.size)}});
  }
  downloadURL(share: Share, ttl: number) { return this.signed(share.object_key,'GET',ttl); }
  async delete(keys: string[]) { await this.env.FILES.delete(keys); }
  async sweepStaging() {
    // Pending reservations expire in 30 minutes; 45 minutes leaves a safety gap.
    for (const [prefix,age] of [['staging/',45*60*1000],['files/',8*86400*1000]] as const) {
      let cursor: string|undefined;
      do {
        const page = await this.env.FILES.list({prefix,limit:500,cursor});
        const keys = page.objects.filter(x=>x.uploaded.getTime()<Date.now()-age).map(x=>x.key);
        if (keys.length) await this.env.FILES.delete(keys);
        cursor = page.truncated ? page.cursor : undefined;
      } while (cursor);
    }
  }
}
export async function localObject(request: Request, env: Env, encoded: string): Promise<Response> {
  if (!localMode(env)) return new Response(null,{status:404});
  const url = new URL(request.url), expiry = Number(url.searchParams.get('expires')), size = Number(url.searchParams.get('size'));
  if (!Number.isSafeInteger(expiry) || expiry <= Date.now()/1000 || !Number.isSafeInteger(size) || size<0 || size>Number(env.PAID_MAX_BYTES)) throw new Problem('expired_upload',403);
  const expected = await hmac(env.LOCAL_SIGNING_KEY ?? '',`${request.method}:${url.pathname}:${expiry}:${size}`);
  if (!equal(expected,url.searchParams.get('signature') ?? '')) throw new Problem('invalid_signature',403);
  let key: string;
  try { key = atob(encoded.replace(/-/g,'+').replace(/_/g,'/')); } catch { throw new Problem('invalid_signature',403); }
  if (!/^(?:staging|files)\/[\da-f-]+\/[\da-f-]+$/.test(key)) throw new Problem('invalid_signature',403);
  if (request.method === 'PUT') {
    if (!key.startsWith('staging/') || Number(request.headers.get('Content-Length')) !== size) throw new Problem('upload_size_mismatch');
    await env.FILES.put(key,request.body);
    return new Response(null,{status:200});
  }
  const object = await env.FILES.get(key);
  if (!object) return new Response(null,{status:404});
  const headers = new Headers({'Content-Type':'application/octet-stream','Cache-Control':'no-store','X-Content-Type-Options':'nosniff'});
  object.writeHttpMetadata(headers);
  return new Response(object.body,{headers});
}
