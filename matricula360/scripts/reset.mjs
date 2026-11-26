// Recria o banco do piloto com dados sintéticos (apaga somente dados/piloto.sqlite*).
import { rmSync, existsSync } from 'node:fs';

const BANCO = process.env.M360_BANCO || 'dados/piloto.sqlite';
if (!BANCO.startsWith('dados/')) {
  console.error('Por segurança, o reset só atua dentro de dados/.');
  process.exit(1);
}
for (const suf of ['', '-wal', '-shm']) {
  if (existsSync(BANCO + suf)) rmSync(BANCO + suf);
}
console.log(`Banco ${BANCO} removido. Rode "npm start" para recriar com dados sintéticos.`);
