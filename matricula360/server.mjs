// Matrícula 360° — servidor do piloto local.
// Escuta somente em 127.0.0.1 por padrão. Não expor à internet. Somente dados sintéticos.
import { createServer } from 'node:http';
import { existsSync, mkdirSync } from 'node:fs';
import { dirname } from 'node:path';
import { abrirBanco } from './src/db.mjs';
import { criarServico } from './src/servico.mjs';
import { criarApp } from './src/app.mjs';
import { semear, SENHA_PADRAO_PILOTO } from './src/semente.mjs';

const PORTA = Number(process.env.PORT || 4173);
const HOST = process.env.HOST || '127.0.0.1';
const BANCO = process.env.M360_BANCO || 'dados/piloto.sqlite';

if (process.env.M360_ENVIO_EXTERNO && process.env.M360_ENVIO_EXTERNO !== 'desativado') {
  console.error('Envio externo não é suportado nesta versão. Remova M360_ENVIO_EXTERNO.');
  process.exit(1);
}

// Modo homologação Supabase: só a URL do projeto e a chave PUBLICÁVEL (nunca a secreta).
const SB_URL = process.env.M360_SUPABASE_URL;
const SB_CHAVE = process.env.M360_SUPABASE_CHAVE_PUBLICAVEL;
let supabase = null;
if (SB_URL || SB_CHAVE) {
  if (!/^https:\/\/[a-z0-9]+\.supabase\.co$/.test(SB_URL || '')) { console.error('M360_SUPABASE_URL inválida (esperado https://<ref>.supabase.co).'); process.exit(1); }
  if (!/^sb_publishable_/.test(SB_CHAVE || '')) { console.error('M360_SUPABASE_CHAVE_PUBLICAVEL deve ser a chave publicável (sb_publishable_...). Nunca use a chave secreta.'); process.exit(1); }
  supabase = { url: SB_URL, chave: SB_CHAVE };
}

let servico = null;
if (!supabase) {
  if (BANCO !== ':memory:') mkdirSync(dirname(BANCO), { recursive: true });
  const novo = BANCO === ':memory:' || !existsSync(BANCO);
  const db = abrirBanco(BANCO);
  servico = criarServico(db);
  if (novo) {
    const senha = process.env.M360_SENHA_PILOTO || SENHA_PADRAO_PILOTO;
    semear(db, servico, { senha });
    console.log(`Banco piloto criado com dados sintéticos em ${BANCO}.`);
  }
}

createServer(criarApp(servico, { supabase })).listen(PORTA, HOST, () => {
  console.log(`Matrícula 360° (${supabase ? 'homologação Supabase: ' + supabase.url : 'piloto local'}) em http://${HOST}:${PORTA}`);
  console.log('Somente dados sintéticos. IA e envio externo desativados.');
});
