export interface Env {
  FILES: R2Bucket;
  API_LIMITER: RateLimit; AUTH_LIMITER: RateLimit; PUBLIC_LIMITER: RateLimit;
  PUBLIC_BASE_URL: string; SUPABASE_URL: string; SUPABASE_ANON_KEY: string; SUPABASE_SERVICE_ROLE_KEY: string;
  R2_ACCOUNT_ID: string; R2_ACCESS_KEY_ID: string; R2_SECRET_ACCESS_KEY: string; R2_BUCKET_NAME: string;
  PASSWORD_PEPPER: string; ABUSE_HASH_KEY: string; DOWNLOAD_SIGNING_KEY: string;
  PAID_MAX_BYTES: string; PAID_MAX_LINKS: string;
  LOCAL_DEVELOPMENT?: string; LOCAL_SIGNING_KEY?: string;
}
export interface Upload {
  id: string; owner_id: string; filename: string; size: number; mime: string;
  staging_key: string; object_key: string; state: string; pending_until: string;
}
export interface Share {
  id: string; upload_id: string; owner_id: string; slug: string; filename: string; size: number;
  object_key: string; expires_at: string; revoked_at: string | null;
  password_hash: string | null; download_limit: number | null; download_count: number; created_at: string;
}
export interface Database {
  reserve(owner: string, id: string, filename: string, size: number, mime: string, pendingUntil: string, paidBytes: number, paidLinks: number): Promise<Upload>;
  pending(owner:string,id:string): Promise<Upload|null>;
  cancel(owner:string,id:string): Promise<void>;
  claim(owner: string, id: string): Promise<Upload>;
  complete(owner: string, id: string, slug: string, expiresAt: string, hash: string | null, limit: number | null): Promise<Share>;
  release(owner: string, id: string): Promise<void>;
  ownedShare(owner: string, id: string): Promise<Share | null>;
  getShare(slug: string): Promise<Share | null>;
  issueTicket(slug:string,id:string,expires:string): Promise<boolean>;
  consumeTicket(id:string): Promise<Share|null>;
  download(slug: string): Promise<Share | null>;
  list(owner: string): Promise<Share[]>;
  revoke(owner: string, id: string): Promise<void>;
  report(slug: string, reporter: string, reason: string): Promise<void>;
  expired(): Promise<Upload[]>;
  removeExpired(id: string): Promise<void>;
  limits(owner: string, paidBytes: number, paidLinks: number): Promise<{maxBytes:number; maxActiveLinks:number; activeLinks:number}>;
}
export interface Storage {
  uploadURL(upload: Upload): Promise<{url:string; headers:Record<string,string>}>;
  validateAndPromote(upload: Upload): Promise<void>;
  openDownload(share: Share): Promise<Response>;
  downloadURL(share: Share, ttl: number): Promise<string>;
  delete(keys: string[]): Promise<void>;
  sweepStaging(): Promise<void>;
}
