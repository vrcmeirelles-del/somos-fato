// Gera dist/config.json para hospedagem estática (Render). Usa SOMENTE a chave publicável.
// Sem as variáveis, não gera nada: no modo local, o servidor Node fornece /config.json.
import { writeFileSync } from 'node:fs';

const url = process.env.M360_SUPABASE_URL;
const chave = process.env.M360_SUPABASE_CHAVE_PUBLICAVEL;
if (!url && !chave) {
  console.log('config.json não gerado (sem M360_SUPABASE_URL/M360_SUPABASE_CHAVE_PUBLICAVEL): uso local.');
  process.exit(0);
}
if (!/^https:\/\/[a-z0-9]+\.supabase\.co$/.test(url || '')) { console.error('M360_SUPABASE_URL inválida (esperado https://<ref>.supabase.co).'); process.exit(1); }
if (!/^sb_publishable_[A-Za-z0-9_-]+$/.test(chave || '')) { console.error('M360_SUPABASE_CHAVE_PUBLICAVEL deve ser a chave PUBLICÁVEL (sb_publishable_...). Nunca use a secreta.'); process.exit(1); }
writeFileSync('dist/config.json', JSON.stringify({ modo: 'supabase', supabase_url: url, supabase_chave_publicavel: chave }));
console.log(`config.json gerado para ${url}`);
