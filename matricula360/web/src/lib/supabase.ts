// Cliente mínimo do Supabase (Auth + RPC), sem SDK: menos superfície e controle total dos erros.
// Toda autorização acontece no banco (RLS + RPCs). Este cliente só autentica e transporta.
const CHAVE_SESSAO = 'm360_sb_sessao';

export interface Sessao { access: string; refresh: string; expira: number; email?: string }
export interface Config { modo: 'supabase' | 'local'; supabase_url?: string; supabase_chave_publicavel?: string }

export class ErroApi extends Error {
  constructor(message: string, public status: number, public codigo?: string, public detalhe?: string | null) { super(message); }
}

// Códigos lógicos devolvidos pelas RPCs (ver migrações 2 e 6) -> status HTTP para a interface.
export const STATUS_POR_CODIGO: Record<string, number> = { P0002: 404, '42501': 403, '40001': 409, '22023': 422 };

export function lerSessao(): Sessao | null {
  try { return JSON.parse(sessionStorage.getItem(CHAVE_SESSAO) || 'null') as Sessao | null; } catch { return null; }
}
function gravarSessao(s: Sessao | null): void {
  try { if (s) sessionStorage.setItem(CHAVE_SESSAO, JSON.stringify(s)); else sessionStorage.removeItem(CHAVE_SESSAO); } catch { /* sem storage */ }
}

export function criarCliente(url: string, chave: string, http: typeof fetch = (...a) => fetch(...a)) {
  async function auth(caminho: string, corpo: unknown, token?: string) {
    const r = await http(`${url}/auth/v1/${caminho}`, {
      method: 'POST',
      headers: { apikey: chave, 'content-type': 'application/json', ...(token ? { authorization: `Bearer ${token}` } : {}) },
      body: JSON.stringify(corpo ?? {}),
    });
    const d = (await r.json().catch(() => ({}))) as Record<string, unknown>;
    if (!r.ok) {
      const msg = r.status === 400 ? 'Credenciais inválidas' : String(d.error_description || d.msg || d.message || 'Falha na autenticação');
      throw new ErroApi(msg, r.status);
    }
    return d;
  }
  function guardar(d: Record<string, unknown>, email?: string) {
    gravarSessao({ access: String(d.access_token), refresh: String(d.refresh_token), expira: Date.now() + Number(d.expires_in) * 1000,
      email: email ?? (d.user as { email?: string } | undefined)?.email });
  }
  async function entrar(email: string, senha: string) { guardar(await auth('token?grant_type=password', { email, password: senha })); }
  async function renovar() {
    const s = lerSessao();
    if (!s?.refresh) throw new ErroApi('Sessão expirada', 401);
    guardar(await auth('token?grant_type=refresh_token', { refresh_token: s.refresh }), s.email);
  }
  async function sair() {
    const s = lerSessao();
    gravarSessao(null);
    if (s?.access) await auth('logout', {}, s.access).catch(() => undefined);
  }
  async function rpc<T>(nome: string, args: Record<string, unknown> = {}, tentativa = 0): Promise<T> {
    let s = lerSessao();
    if (!s) throw new ErroApi('Sessão ausente', 401);
    if (s.expira - Date.now() < 60_000) { await renovar(); s = lerSessao(); }
    const r = await http(`${url}/rest/v1/rpc/${nome}`, {
      method: 'POST',
      headers: { apikey: chave, authorization: `Bearer ${s!.access}`, 'content-type': 'application/json' },
      body: JSON.stringify(args),
    });
    const d = (await r.json().catch(() => null)) as { code?: string; message?: string; details?: string | null } | null;
    if (r.status === 401 && /JWT/i.test(d?.message ?? '') && tentativa === 0) { await renovar(); return rpc<T>(nome, args, 1); }
    if (!r.ok) throw new ErroApi(d?.message || `Erro ${r.status}`, (d?.code && STATUS_POR_CODIGO[d.code]) || r.status, d?.code, d?.details);
    return d as T;
  }
  return { entrar, sair, rpc };
}
export type Cliente = ReturnType<typeof criarCliente>;
