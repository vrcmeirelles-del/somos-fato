// Gera supabase/TESTAR-NO-SQL-EDITOR.sql: a mesma bateria de RLS (semente + testes 20 e 30)
// embrulhada num único bloco DO, para colar no SQL Editor do Supabase.
// - Tudo roda numa transação; ao final o bloco levanta uma exceção com o placar,
//   o que DESFAZ tudo (dados, schema de teste, papéis e configurações de sessão).
// - Não toca no schema auth: a FK usuarios -> auth.users é removida só dentro da transação.
// - Aborta se o banco já tiver dados (proteção para quando houver uso real).
import { readFileSync, writeFileSync } from 'node:fs';

function dividir(sql) {
  const out = []; let atual = ''; let i = 0;
  while (i < sql.length) {
    const c = sql[i];
    if (c === '-' && sql[i + 1] === '-') { const f = sql.indexOf('\n', i); i = f < 0 ? sql.length : f + 1; atual += '\n'; continue; }
    if (c === '\\' && (i === 0 || sql[i - 1] === '\n')) { const f = sql.indexOf('\n', i); i = f < 0 ? sql.length : f + 1; continue; } // meta-comando psql
    if (c === "'") { const ini = i; i++; while (i < sql.length) { if (sql[i] === "'" && sql[i + 1] === "'") { i += 2; continue; } if (sql[i] === "'") { i++; break; } i++; } atual += sql.slice(ini, i); continue; }
    if (c === '$') {
      const m = sql.slice(i).match(/^\$[A-Za-z_]*\$/);
      if (m) { const tag = m[0]; const f = sql.indexOf(tag, i + tag.length); const fim = f + tag.length; atual += sql.slice(i, fim); i = fim; continue; }
    }
    if (c === ';') { if (atual.trim()) out.push(atual.trim()); atual = ''; i++; continue; }
    atual += c; i++;
  }
  if (atual.trim()) out.push(atual.trim());
  return out;
}

const ler = (f) => readFileSync(new URL(`../supabase/teste-local/${f}`, import.meta.url), 'utf8');
const semente = dividir(ler('10_semente.sql')).filter((s) => !/^insert into auth\.users/i.test(s));
const testes = [...dividir(ler('20_testes_rls.sql')), ...dividir(ler('30_testes_complementares.sql')), ...dividir(ler('40_testes_leitura.sql')), ...dividir(ler('50_testes_fase2.sql')), ...dividir(ler('60_testes_central.sql')), ...dividir(ler('70_testes_biblia_v02.sql')), ...dividir(ler('80_testes_crm.sql')), ...dividir(ler('90_testes_governanca.sql')), ...dividir(ler('95_testes_planejamento.sql')), ...dividir(ler('97_testes_funis.sql')), ...dividir(ler('98_testes_performance.sql')), ...dividir(ler('99_testes_recuperacao.sql')), ...dividir(ler('100_testes_academia.sql')), ...dividir(ler('101_testes_relacionamento.sql')), ...dividir(ler('102_testes_captacao_publica.sql')), ...dividir(ler('103_testes_documentos.sql')), ...dividir(ler('104_testes_eventos_seletivo.sql')), ...dividir(ler('105_testes_matricula_comunicacao.sql')), ...dividir(ler('106_testes_aceite_reforcado.sql')), ...dividir(ler('107_testes_bolsas.sql')), ...dividir(ler('108_testes_rematricula.sql')), ...dividir(ler('109_testes_sucesso_aluno.sql')), ...dividir(ler('110_testes_dois_fatores.sql')), ...dividir(ler('111_testes_campo.sql')), ...dividir(ler('112_testes_pesquisas.sql')), ...dividir(ler('113_testes_banca_aproveitamento.sql')), ...dividir(ler('114_testes_onda_c.sql'))];

const protecao = `  if exists (select 1 from public.ies) or exists (select 1 from public.usuarios) then
    raise exception 'ABORTADO: o banco já tem dados; este teste só roda em banco vazio.';
  end if;`;
const preambulo = [
  `alter table public.usuarios drop constraint if exists usuarios_id_fkey`,
  ...['ies', 'campus', 'cursos', 'pessoas', 'oportunidades'].map((t) => `alter table public.${t} alter column id restart with 1`),
];
const placar = [
  `create table teste.resultado (n serial, nome text)`,
  `grant insert on teste.resultado to anon, authenticated`,
  `grant usage on sequence teste.resultado_n_seq to anon, authenticated`,
  `create or replace function teste.ok(p boolean, p_nome text) returns void language plpgsql as $f$
   begin if p is distinct from true then raise exception 'FALHOU: %', p_nome; end if; insert into teste.resultado(nome) values (p_nome); end $f$`,
  `create or replace function teste.erro(p_sql text, p_codigo text, p_nome text) returns void language plpgsql as $f$
   begin
     begin execute p_sql;
     exception when others then
       if sqlstate = p_codigo or (sqlstate = 'PGRST' and sqlerrm::jsonb->>'code' = p_codigo) then insert into teste.resultado(nome) values (p_nome); return; end if;
       raise exception 'FALHOU: % — esperado %, obtido % (%)', p_nome, p_codigo, sqlstate, sqlerrm;
     end;
     raise exception 'FALHOU: % — deveria ter falhado com %', p_nome, p_codigo;
   end $f$`,
];
const tudo = [...preambulo, ...semente, ...placar, ...testes];
const corpo = tudo.map((s) => {
  if (/^do \$\$/i.test(s)) return '  execute $x$ ' + s + ' $x$;'; // corpo "$$" fica intacto dentro de $x$
  return `  execute $x$ ${s} $x$;`;
}).join('\n');

const saida = `-- Matrícula 360° — testes de isolamento (RLS) no banco REAL, para colar no SQL Editor do Supabase.
-- Projeto: jbimijcvvekomovodfze. Gerado por scripts/gerar-teste-remoto.mjs a partir de supabase/teste-local/.
-- COMO LER O RESULTADO: o editor vai mostrar um "erro" de propósito, porque é assim que tudo é desfeito.
--   * "RESULTADO: N verificações aprovadas, 0 falhas"  => tudo certo; nada ficou gravado.
--   * "FALHOU: ..."                                     => uma verificação falhou; nada ficou gravado.
--   * "ABORTADO: ..."                                   => o banco já tinha dados; nada foi executado.
do $bloco$
declare n int;
begin
${protecao}
${corpo}
  execute $x$ reset role $x$;
  select count(*) into n from teste.resultado;
  raise exception 'RESULTADO: % verificações aprovadas, 0 falhas (tudo desfeito; nada ficou gravado)', n;
end
$bloco$;
`;
writeFileSync(new URL('../supabase/TESTAR-NO-SQL-EDITOR.sql', import.meta.url), saida);
console.log(`gerado com ${tudo.length} comandos`);
