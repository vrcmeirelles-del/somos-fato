// Aplica as migrações Supabase num Postgres LOCAL descartável e roda os testes de RLS.
// Nunca aponte M360_PG_URL para um banco de produção ou de outro produto.
import { execFileSync, spawn, spawnSync } from 'node:child_process';

const URL_ADMIN = process.env.M360_PG_URL || 'postgresql://postgres:local@127.0.0.1:5432/postgres';
const BANCO = 'm360_teste_rls';
if (!/127\.0\.0\.1|localhost/.test(URL_ADMIN)) {
  console.error('Por segurança, este script só roda contra Postgres local.');
  process.exit(1);
}
const urlTeste = URL_ADMIN.replace(/\/[^/]*$/, `/${BANCO}`);
const psql = (url, args, opts = {}) => execFileSync('psql', [url, '-v', 'ON_ERROR_STOP=1', '-X', ...args], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'], ...opts });

psql(URL_ADMIN, ['-q', '-c', `DROP DATABASE IF EXISTS ${BANCO}`, '-c', `CREATE DATABASE ${BANCO}`]);
const arquivos = [
  'supabase/teste-local/00_simulacao_supabase.sql',
  'supabase/migrations/20261125000001_esquema_rls.sql',
  'supabase/migrations/20261125000002_rpcs.sql',
  'supabase/migrations/20261125000003_rpcs_complementares.sql',
  'supabase/migrations/20261125000004_indices_fk.sql',
  'supabase/migrations/20261125000005_rpcs_leitura.sql',
  'supabase/migrations/20261125000006_codigos_http.sql',
  'supabase/teste-local/10_semente.sql',
];
for (const f of arquivos) {
  try { psql(urlTeste, ['-q', '-f', f]); console.log(`aplicado: ${f}`); }
  catch (e) { console.error(`FALHA ao aplicar ${f}\n${e.stderr}`); process.exit(1); }
}

let falhou = false;
const rt = spawnSync('psql', [urlTeste, '-X', '-tAq', '-v', 'ON_ERROR_STOP=1', '-o', '/dev/null', '-f', 'supabase/teste-local/20_testes_rls.sql', '-f', 'supabase/teste-local/30_testes_complementares.sql', '-f', 'supabase/teste-local/40_testes_leitura.sql'], { encoding: 'utf8' });
const linhas = (rt.stderr || '').split('\n').map((l) => l.replace(/^psql:[^ ]+ (NOTICE|ERROR):\s+/, (_, t) => (t === 'ERROR' ? 'ERRO: ' : ''))).filter(Boolean);
for (const l of linhas) console.log(l);
const okRls = linhas.filter((l) => l.startsWith('OK ') && !l.startsWith('OK  fim')).length;
console.log(`--- ${okRls} verificações de RLS aprovadas; código de saída ${rt.status}`);
if (rt.status !== 0) falhou = true;

// Corrida real: duas sessões concorrentes mudando a mesma oportunidade com a mesma versão.
function sessao(apelido, para, atrasoMs, segurar) {
  const sql = `set role authenticated; select set_config('request.jwt.claim.sub', teste.id('${apelido}')::text, false);
    begin; select public.rpc_mover_etapa(3, '${para}', 1, 'corrida'); ${segurar ? 'select pg_sleep(1);' : ''} commit;`;
  return new Promise((ok) => setTimeout(() => {
    const p = spawn('psql', [urlTeste, '-X', '-q', '-v', 'ON_ERROR_STOP=1', '-c', sql]);
    let err = ''; p.stderr.on('data', (b) => { err += b; });
    p.on('close', (code) => ok({ code, err }));
  }, atrasoMs));
}
const relatorio = (await Promise.all([sessao('comercial_a', 'contato', 0, true), sessao('gestor_a', 'perdido', 300, false)]));
const [a, b] = relatorio;
const corridaOk = a.code === 0 && b.code !== 0 && /Conflito de versão/.test(b.err);
console.log(`${corridaOk ? 'OK ' : 'FALHOU:'} corrida real entre duas sessões: a primeira vence e a segunda recebe conflito de versão`);
if (!corridaOk) { falhou = true; console.log(a, b); }

const lint = execFileSync('psql', [urlTeste, '-X', '-tA', '-c', `
  select count(*) from pg_tables where schemaname in ('public','privado') and not rowsecurity`], { encoding: 'utf8' }).trim();
console.log(`${lint === '0' ? 'OK ' : 'FALHOU:'} todas as tabelas com RLS habilitada (${lint} sem RLS)`);
if (lint !== '0') falhou = true;
const semPath = execFileSync('psql', [urlTeste, '-X', '-tA', '-c', `
  select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname in ('public','privado') and not coalesce(array_to_string(p.proconfig, ',') like '%search_path=%', false)`], { encoding: 'utf8' }).trim();
console.log(`${semPath === '0' ? 'OK ' : 'FALHOU:'} todas as funções com search_path fixo (${semPath} sem)`);
if (semPath !== '0') falhou = true;

psql(URL_ADMIN, ['-q', '-c', `DROP DATABASE IF EXISTS ${BANCO}`]);
process.exit(falhou ? 1 : 0);
