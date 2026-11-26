// Escolhe o destino das chamadas das telas: API local (piloto SQLite) ou Supabase (homologação).
// O modo vem de /config.json, servido pelo servidor local conforme as variáveis de ambiente.
import { criarClienteSupabase, criarAdaptador } from './supabase.mjs';

let configuracao;
async function config() {
  if (!configuracao) configuracao = await fetch('/config.json').then((r) => r.json()).catch(() => ({ modo: 'local' }));
  return configuracao;
}
let cliente; let adaptador;
async function supabase() {
  if (!cliente) {
    const c = await config();
    cliente = criarClienteSupabase({ url: c.supabase_url, chave: c.supabase_chave_publicavel });
    adaptador = criarAdaptador(cliente);
  }
  return { cliente, adaptador };
}
const uuid = () => (crypto.randomUUID ? crypto.randomUUID() : `${Date.now()}-${Math.random().toString(36).slice(2)}`);

export async function modo() { return (await config()).modo; }

export async function entrar(email, senha) {
  if ((await config()).modo === 'supabase') return (await supabase()).cliente.entrar(email, senha);
  const r = await fetch('/api/login', { method: 'POST', headers: { 'content-type': 'application/json', 'x-m360': '1' }, body: JSON.stringify({ email, senha }) });
  const d = await r.json().catch(() => ({}));
  if (!r.ok) throw Object.assign(new Error(d.erro || 'Falha no login'), { status: r.status });
}

export async function api(metodo, url, corpo) {
  try {
    if ((await config()).modo === 'supabase') return await (await supabase()).adaptador(metodo, url, corpo);
    const opts = { method: metodo, credentials: 'same-origin', headers: {} };
    if (metodo !== 'GET') {
      opts.headers = { 'content-type': 'application/json', 'x-m360': '1', 'idempotency-key': uuid() };
      opts.body = JSON.stringify(corpo ?? {});
    }
    const r = await fetch(url, opts);
    const d = await r.json().catch(() => ({}));
    if (!r.ok) throw Object.assign(new Error(d.erro || `Erro ${r.status}`), { status: r.status });
    return d;
  } catch (e) {
    if (e.status === 401 && location.pathname !== '/login') location.href = '/login';
    throw e;
  }
}
