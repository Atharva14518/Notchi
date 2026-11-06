import { Problem, uuid } from './domain';
import type { Env } from './types';
export async function authenticate(request: Request, env: Env): Promise<string> {
  const token = request.headers.get('Authorization') ?? '';
  if (!/^Bearer [\w.\-]+$/i.test(token) || token.length>8192) throw new Problem('sign_in_required',401);
  // Supabase Auth verifies the signature, issuer, expiry and account state.
  // Do not trust decoded client claims or user-editable user_metadata for tier.
  const response = await fetch(`${env.SUPABASE_URL}/auth/v1/user`,{headers:{apikey:env.SUPABASE_ANON_KEY,Authorization:token}});
  if (!response.ok) throw new Problem(response.status>=500 ? 'auth_unavailable' : 'sign_in_required',response.status>=500 ? 503 : 401);
  const user = await response.json() as {id:string};
  return uuid(user.id);
}
export function authRequest(value: Record<string,unknown>) {
  const state = value.state, challenge = value.challenge;
  if (typeof state!=='string' || !/^[\w-]{43,128}$/.test(state) || typeof challenge!=='string' || !/^[\w-]{43}$/.test(challenge)) throw new Problem('invalid_auth_request');
  return {state,challenge};
}
export function authRedirect(env:Env,state:string) { return `${env.PUBLIC_BASE_URL}/auth/callback?state=${encodeURIComponent(state)}`; }
export async function authToken(env:Env,grant:'pkce'|'refresh_token',body:Record<string,string>) {
  const response = await fetch(`${env.SUPABASE_URL}/auth/v1/token?grant_type=${grant}`,{method:'POST',headers:{apikey:env.SUPABASE_ANON_KEY,'Content-Type':'application/json'},body:JSON.stringify(body)});
  if (!response.ok) throw new Problem('sign_in_failed',401);
  const value = await response.json() as {access_token:string;refresh_token:string;expires_in:number;token_type:string;user:{id:string}};
  if (!value.access_token || !value.refresh_token || !(value.expires_in>0)) throw new Problem('auth_unavailable',503);
  return {accessToken:value.access_token,refreshToken:value.refresh_token,expiresIn:value.expires_in,userId:uuid(value.user?.id)};
}
