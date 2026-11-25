import { beforeEach, describe, expect, it } from 'vitest';
import { ErroApi, criarCliente, lerSessao } from './supabase';

type Resp = { status: number; corpo: unknown };
function falso(respostas: Resp[]) {
  const chamadas: { url: string; init?: RequestInit }[] = [];
  const http = (async (url: string, init?: RequestInit) => {
    chamadas.push({ url, init });
    const r = respostas.shift();
    if (!r) throw new Error('chamada inesperada: ' + url);
    return new Response(JSON.stringify(r.corpo), { status: r.status, headers: { 'content-type': 'application/json' } });
  }) as unknown as typeof fetch;
  return { http, chamadas };
}
const token = { access_token: 'a1', refresh_token: 'r1', expires_in: 3600, user: { email: 'x@example.com' } };

describe('cliente Supabase', () => {
  beforeEach(() => sessionStorage.clear());

  it('login guarda sessão e RPC envia apikey + bearer', async () => {
    const f = falso([{ status: 200, corpo: token }, { status: 200, corpo: { ok: 1 } }]);
    const c = criarCliente('https://p.supabase.co', 'sb_publishable_x', f.http);
    await c.entrar('x@example.com', 'segredo');
    expect(lerSessao()?.email).toBe('x@example.com');
    expect(await c.rpc('rpc_me')).toEqual({ ok: 1 });
    const h = f.chamadas[1]!.init!.headers as Record<string, string>;
    expect(f.chamadas[1]!.url).toBe('https://p.supabase.co/rest/v1/rpc/rpc_me');
    expect(h.apikey).toBe('sb_publishable_x');
    expect(h.authorization).toBe('Bearer a1');
  });

  it('credencial errada vira mensagem genérica (sem revelar se o e-mail existe)', async () => {
    const f = falso([{ status: 400, corpo: { error_description: 'Invalid login credentials' } }]);
    const c = criarCliente('https://p.supabase.co', 'k', f.http);
    await expect(c.entrar('x@example.com', 'errada')).rejects.toMatchObject({ message: 'Credenciais inválidas', status: 400 });
    expect(lerSessao()).toBeNull();
  });

  it('mapeia códigos lógicos do banco para status da interface', async () => {
    const casos: [string, number][] = [['P0002', 404], ['42501', 403], ['40001', 409], ['22023', 422]];
    for (const [code, status] of casos) {
      const f = falso([{ status: 200, corpo: token }, { status: 400, corpo: { code, message: 'm', details: '7' } }]);
      const c = criarCliente('https://p.supabase.co', 'k', f.http);
      await c.entrar('x@example.com', 's');
      const e = await c.rpc('rpc_x').catch((x: ErroApi) => x);
      expect(e).toBeInstanceOf(ErroApi);
      expect((e as ErroApi).status).toBe(status);
      if (code === '40001') expect((e as ErroApi).detalhe).toBe('7');
    }
  });

  it('JWT expirado: renova uma vez e repete a chamada', async () => {
    const f = falso([
      { status: 200, corpo: token },
      { status: 401, corpo: { message: 'JWT expired' } },
      { status: 200, corpo: { ...token, access_token: 'a2', refresh_token: 'r2' } },
      { status: 200, corpo: { ok: 2 } },
    ]);
    const c = criarCliente('https://p.supabase.co', 'k', f.http);
    await c.entrar('x@example.com', 's');
    expect(await c.rpc('rpc_me')).toEqual({ ok: 2 });
    expect(f.chamadas[2]!.url).toContain('grant_type=refresh_token');
    expect((f.chamadas[3]!.init!.headers as Record<string, string>).authorization).toBe('Bearer a2');
  });

  it('sem sessão não chama a rede', async () => {
    const f = falso([]);
    const c = criarCliente('https://p.supabase.co', 'k', f.http);
    await expect(c.rpc('rpc_me')).rejects.toMatchObject({ status: 401 });
    expect(f.chamadas.length).toBe(0);
  });

  it('sair limpa a sessão local mesmo se o logout remoto falhar', async () => {
    const f = falso([{ status: 200, corpo: token }, { status: 500, corpo: {} }]);
    const c = criarCliente('https://p.supabase.co', 'k', f.http);
    await c.entrar('x@example.com', 's');
    await c.sair();
    expect(lerSessao()).toBeNull();
  });
});
