import { Problem } from './domain';
import type { Database, Env, Share, Upload } from './types';
const known = new Set(['too_large','quota_exceeded','upload_missing','upload_busy','upload_expired','already_complete','invalid_share']);
export class SupabaseDatabase implements Database {
  constructor(private env: Env) {}
  private async rpc<T>(name: string, body: Record<string,unknown>): Promise<T> {
    const response = await fetch(`${this.env.SUPABASE_URL}/rest/v1/rpc/${name}`, {
      method:'POST', headers:{apikey:this.env.SUPABASE_SERVICE_ROLE_KEY,Authorization:`Bearer ${this.env.SUPABASE_SERVICE_ROLE_KEY}`,'Content-Type':'application/json'}, body:JSON.stringify(body)
    });
    if (!response.ok) {
      const error = await response.json().catch(()=>({})) as {message?:string};
      if (error.message && known.has(error.message)) throw new Problem(error.message,error.message === 'quota_exceeded' ? 409 : 400);
      throw new Problem('metadata_unavailable',503); // Never expose SQL errors, URLs or tokens.
    }
    // PostgREST returns an empty successful body for PostgreSQL void RPCs.
    // Revoke/cancel/cleanup must not turn that success into a JSON parse error.
    const bodyText=await response.text();
    return (bodyText ? JSON.parse(bodyText) : undefined) as T;
  }
  reserve(owner:string,id:string,filename:string,size:number,mime:string,pendingUntil:string,paidBytes:number,paidLinks:number) {
    return this.rpc<Upload>('link_reserve_upload',{p_owner:owner,p_id:id,p_filename:filename,p_size:size,p_mime:mime,p_until:pendingUntil,p_paid_bytes:paidBytes,p_paid_links:paidLinks});
  }
  pending(owner:string,id:string) { return this.rpc<Upload|null>('link_pending_upload',{p_owner:owner,p_id:id}); }
  async cancel(owner:string,id:string) { await this.rpc('link_cancel_upload',{p_owner:owner,p_id:id}); }
  claim(owner:string,id:string) { return this.rpc<Upload>('link_claim_upload',{p_owner:owner,p_id:id}); }
  complete(owner:string,id:string,slug:string,expiresAt:string,hash:string|null,limit:number|null) {
    return this.rpc<Share>('link_complete_upload',{p_owner:owner,p_id:id,p_slug:slug,p_expires:expiresAt,p_hash:hash,p_limit:limit});
  }
  async release(owner:string,id:string) { await this.rpc('link_release_upload',{p_owner:owner,p_id:id}); }
  ownedShare(owner:string,id:string) { return this.rpc<Share|null>('link_owned_share',{p_owner:owner,p_upload:id}); }
  getShare(slug:string) { return this.rpc<Share|null>('link_get_share',{p_slug:slug}); }
  issueTicket(slug:string,id:string,expires:string) { return this.rpc<boolean>('link_issue_ticket',{p_slug:slug,p_id:id,p_expires:expires}); }
  consumeTicket(id:string) { return this.rpc<Share|null>('link_consume_ticket',{p_id:id}); }
  download(slug:string) { return this.rpc<Share|null>('link_claim_download',{p_slug:slug}); }
  list(owner:string) { return this.rpc<Share[]>('link_list_shares',{p_owner:owner}); }
  async revoke(owner:string,id:string) { await this.rpc('link_revoke',{p_owner:owner,p_id:id}); }
  async report(slug:string,reporter:string,reason:string) { await this.rpc('link_report',{p_slug:slug,p_reporter:reporter,p_reason:reason}); }
  expired() { return this.rpc<Upload[]>('link_expired_uploads',{}); }
  async removeExpired(id:string) { await this.rpc('link_delete_expired',{p_id:id}); }
  limits(owner:string,paidBytes:number,paidLinks:number) { return this.rpc<{maxBytes:number;maxActiveLinks:number;activeLinks:number}>('link_limits',{p_owner:owner,p_paid_bytes:paidBytes,p_paid_links:paidLinks}); }
}
