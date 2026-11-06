export const FREE_MAX_BYTES = 100_000_000;
export const FREE_MAX_LINKS = 5;
export const UPLOAD_TTL_SECONDS = 900;
export const PENDING_TTL_SECONDS = 1800;
export const DOWNLOAD_TTL_SECONDS = 30;
export type Expiry = '1h' | '24h' | '7d';
const seconds: Record<Expiry, number> = { '1h': 3600, '24h': 86400, '7d': 604800 };
export class Problem extends Error {
  constructor(public code: string, public status = 400) { super(code); }
}
export function expiryAt(choice: unknown, now = new Date()): Date {
  if (typeof choice !== 'string' || !Object.hasOwn(seconds,choice)) throw new Problem('invalid_expiry');
  return new Date(now.getTime() + seconds[choice as Expiry] * 1000);
}
export function isExpired(expiresAt: string | Date, now = new Date()): boolean {
  const value = new Date(expiresAt).getTime();
  return !Number.isFinite(value) || value <= now.getTime();
}
export function downloadTTL(expiresAt: string, now = new Date()): number {
  return Math.max(0, Math.min(DOWNLOAD_TTL_SECONDS, Math.floor((new Date(expiresAt).getTime() - now.getTime()) / 1000)));
}
const blocked = new Set('exe com scr dll msi msix app dmg pkg iso sh bash zsh command bat cmd ps1 vbs js jse mjs cjs html htm svg jar apk deb rpm'.split(' '));
export function validateFile(name: unknown, size: unknown, mime: unknown) {
  if (typeof name !== 'string' || !name.trim() || new TextEncoder().encode(name).length > 220 || /[\\/\x00-\x1f\x7f]/u.test(name) || name === '.' || name === '..') throw new Problem('invalid_filename');
  const parts = name.toLowerCase().split('.');
  // Block risky nested extensions as well as the final suffix (e.g. app.zip).
  if (parts.slice(1).some(p => blocked.has(p))) throw new Problem('blocked_type');
  if (typeof size !== 'number' || !Number.isSafeInteger(size) || size < 1) throw new Problem('invalid_size');
  if (typeof mime !== 'string' || mime.length > 120 || !/^[\w.+-]+\/[\w.+-]+$/.test(mime)) throw new Problem('invalid_type');
  if (/javascript|html|svg|executable|x-msdownload|x-sh|x-shellscript/i.test(mime)) throw new Problem('blocked_type');
  return { name: name.trim(), size, mime };
}
export function validateLimit(value: unknown): number | null {
  if (value === null || value === undefined) return null;
  if (typeof value !== 'number' || !Number.isSafeInteger(value) || value < 1 || value > 10_000) throw new Problem('invalid_download_limit');
  return value;
}
export function validatePassword(value: unknown): string | null {
  if (value === undefined || value === null || value === '') return null;
  if (typeof value !== 'string' || value.length < 8 || value.length > 128) throw new Problem('invalid_password');
  return value;
}
export function uuid(value: unknown): string {
  if (typeof value !== 'string' || !/^[a-f\d]{8}-(?:[a-f\d]{4}-){3}[a-f\d]{12}$/i.test(value)) throw new Problem('invalid_id');
  return value;
}
export function validSlug(value: string): boolean { return /^[\w-]{24}$/.test(value); }
export function blockedMagic(bytes: Uint8Array): boolean {
  const hex = Array.from(bytes.slice(0,4), x => x.toString(16).padStart(2,'0')).join('');
  return ['7f454c46','feedface','cefaedfe','feedfacf','cffaedfe','cafebabe','bebafeca'].includes(hex) || hex.startsWith('4d5a') || (bytes[0] === 35 && bytes[1] === 33);
}
export function escapeHTML(value: string): string {
  return value.replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]!));
}
