// Gera supabase/migrations/20261125000006_codigos_http.sql.
// Motivo (homologação no Supabase real, 25/11/2026):
//   * SQLSTATE P0002 chegava ao navegador como HTTP 500 (o PostgREST não o mapeia).
//   * SQLSTATE 40001 (serialization_failure) faz o PostgREST repetir a transação até estourar
//     o tempo ("upstream request timeout"), travando a tela em conflito de versão.
// Correção: erros com status HTTP explícito via SQLSTATE 'PGRST' (404 e 409), sem nova tentativa.
// O script recria a ÚLTIMA definição de cada função afetada (migrações 1 a 5), trocando só o raise.
import { readFileSync, writeFileSync, readdirSync } from 'node:fs';

const dir = new URL('../supabase/migrations/', import.meta.url);
const arquivos = readdirSync(dir).filter((f) => /^2026112500000[1-5]_.*\.sql$/.test(f)).sort();
const funcoes = new Map();
for (const f of arquivos) {
  const sql = readFileSync(new URL(f, dir), 'utf8');
  for (const m of sql.matchAll(/create or replace function ([\w.]+)\([\s\S]*?\$\$;/g)) funcoes.set(m[1], m[0]);
}
const NAO_ENCONTRADO = "raise exception 'Não encontrado' using errcode = 'P0002'";
const afetadas = [...funcoes.entries()].filter(([nome, corpo]) => corpo.includes(NAO_ENCONTRADO) && nome !== 'privado.exigir_versao');
const corpo = afetadas.map(([nome, c]) => `-- ${nome}\n${c.split(NAO_ENCONTRADO).join("perform privado.erro_http(404, 'P0002', 'Não encontrado')")}`).join('\n\n');
const restantes = afetadas.filter(([, c]) => c.includes("'P0002'") && !c.includes(NAO_ENCONTRADO));
if (restantes.length) throw new Error('P0002 em formato inesperado');

const saida = `-- Matrícula 360° — migração 6: códigos HTTP corretos para "não encontrado" (404) e conflito de versão (409).
-- Gerada por scripts/gerar-migracao-6.mjs. Achado da homologação no Supabase real (25/11/2026):
--   P0002 chegava como HTTP 500; 40001 fazia o PostgREST repetir a transação até "upstream request timeout".
-- Usa SQLSTATE 'PGRST' (recurso do PostgREST) para fixar o status HTTP. Comportamento e regras inalterados.

create or replace function privado.erro_http(p_status int, p_codigo text, p_mensagem text, p_detalhe text default null)
returns void language plpgsql set search_path = '' as $$
begin
  raise sqlstate 'PGRST' using
    message = json_build_object('code', p_codigo, 'message', p_mensagem, 'details', p_detalhe, 'hint', null)::text,
    detail = json_build_object('status', p_status, 'headers', json_build_object())::text;
end $$;
revoke execute on function privado.erro_http(int, text, text, text) from public, anon, authenticated;

create or replace function privado.exigir_versao(p_op bigint, p_esperada int) returns int
language plpgsql security definer set search_path = '' as $$
declare v int;
begin
  update public.oportunidades set versao = versao + 1, atualizado_em = now()
   where id = p_op and versao = p_esperada returning versao into v;
  if v is null then
    perform privado.erro_http(409, '40001',
      'Conflito de versão: o registro foi alterado por outra operação. Recarregue e tente novamente.',
      (select versao::text from public.oportunidades where id = p_op));
  end if;
  return v;
end $$;

${corpo}
`;
writeFileSync(new URL('20261125000006_codigos_http.sql', dir), saida);
console.log(`migração 6 gerada: ${afetadas.length} funções recriadas + erro_http + exigir_versao`);
console.log(afetadas.map(([n]) => n).join(', '));
