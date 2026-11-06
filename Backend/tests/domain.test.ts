import {describe,it,expect} from 'vitest';
import {expiryAt,isExpired,downloadTTL,validateFile,validateLimit,validatePassword,blockedMagic,escapeHTML} from '../src/domain';
import {hashPassword,verifyPassword} from '../src/crypto';
const now=new Date('2026-11-05T10:00:00Z');
describe('expiry',()=>{
 for(const [choice,s] of [['1h',3600],['24h',86400],['7d',604800]] as const) it(choice,()=>{
  const end=expiryAt(choice,now);expect(end.getTime()-now.getTime()).toBe(s*1000);
  expect(isExpired(end,new Date(end.getTime()-1))).toBe(false);expect(isExpired(end,end)).toBe(true);
 });
 it('rejects unknown/prototype choices',()=>{for(const x of ['30d','__proto__','toString',null,3600])expect(()=>expiryAt(x,now)).toThrow();});
 it('bounds signed lifetime and fails closed for invalid dates',()=>{
  expect(isExpired('invalid',now)).toBe(true);expect(downloadTTL(new Date(+now+10_000).toISOString(),now)).toBe(10);
  expect(downloadTTL(new Date(+now+3600_000).toISOString(),now)).toBe(30);expect(downloadTTL(now.toISOString(),now)).toBe(0);
 });
});
describe('validation',()=>{
 it('rejects executable, nested extensions, paths, bad sizes and risky types',()=>{
  for(const n of ['a.exe','a.app.zip','../a.pdf','a\n.pdf'])expect(()=>validateFile(n,5,'application/pdf')).toThrow();
  expect(()=>validateFile('a.pdf',NaN,'application/pdf')).toThrow();expect(()=>validateFile('a.svg',5,'image/svg+xml')).toThrow();
  expect(validateFile('scan.pdf',10,'application/pdf').size).toBe(10);expect(blockedMagic(new Uint8Array([0x4d,0x5a,0,0]))).toBe(true);
 });
 it('bounds passwords and download counts',()=>{
  expect(validateLimit(null)).toBeNull();expect(validateLimit(1)).toBe(1);for(const n of [0,1.2,10001])expect(()=>validateLimit(n)).toThrow();
  expect(validatePassword('')).toBeNull();expect(()=>validatePassword('short')).toThrow();
 });
 it('salts and peppers hashes and rejects wrong passwords',async()=>{
  const pepper='p'.repeat(64),hash=await hashPassword('a private password',pepper);
  expect(hash).not.toContain('a private password');expect(hash).not.toBe(await hashPassword('a private password',pepper));
  expect(await verifyPassword('a private password',hash!,pepper)).toBe(true);expect(await verifyPassword('wrong',hash!,pepper)).toBe(false);
  expect(await verifyPassword('a private password',hash!,'q'.repeat(64))).toBe(false);
 });
 it('escapes public names',()=>expect(escapeHTML('<img onerror="x">')).toBe('&lt;img onerror=&quot;x&quot;&gt;'));
});
