import { Problem } from './domain';
const enc = new TextEncoder();
export function base64url(bytes: Uint8Array): string {
  return btoa(String.fromCharCode(...bytes)).replace(/\+/g,'-').replace(/\//g,'_').replace(/=+$/,'');
}
export function randomToken(bytes = 18): string { return base64url(crypto.getRandomValues(new Uint8Array(bytes))); }
export function equal(a: string, b: string): boolean {
  const aa = enc.encode(a), bb = enc.encode(b);
  let result = aa.length ^ bb.length;
  for (let i=0; i<Math.max(aa.length,bb.length); i++) result |= (aa[i] ?? 0) ^ (bb[i] ?? 0);
  return result === 0;
}
export async function hmac(secret: string, value: string): Promise<string> {
  if (secret.length < 32) throw new Problem('service_unconfigured',503);
  const key = await crypto.subtle.importKey('raw',enc.encode(secret),{name:'HMAC',hash:'SHA-256'},false,['sign']);
  return base64url(new Uint8Array(await crypto.subtle.sign('HMAC',key,enc.encode(value))));
}
async function derive(password: string, salt: string, pepper: string): Promise<string> {
  const material = await hmac(pepper,password);
  const key = await crypto.subtle.importKey('raw',enc.encode(material),'PBKDF2',false,['deriveBits']);
  // Workers WebCrypto supports at most 100,000 iterations. An independent,
  // server-only pepper prevents offline guessing from a database-only leak.
  return base64url(new Uint8Array(await crypto.subtle.deriveBits({name:'PBKDF2',hash:'SHA-256',salt:enc.encode(salt),iterations:100_000},key,256)));
}
export async function hashPassword(password: string | null, pepper: string): Promise<string | null> {
  if (password === null) return null;
  const salt = randomToken(24);
  return `pbkdf2-sha256:100000:${salt}:${await derive(password,salt,pepper)}`;
}
export async function verifyPassword(password: string, hash: string, pepper: string): Promise<boolean> {
  const [version, rounds, salt, digest] = hash.split(':');
  if (version !== 'pbkdf2-sha256' || rounds !== '100000' || !salt || !digest) return false;
  return equal(await derive(password,salt,pepper),digest);
}
export async function anonymousKey(ip: string, secret: string): Promise<string> {
  return hmac(secret,`${new Date().toISOString().slice(0,10)}:${ip}`);
}
