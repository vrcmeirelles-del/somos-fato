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

if (BANCO !== ':memory:') mkdirSync(dirname(BANCO), { recursive: true });
const novo = BANCO === ':memory:' || !existsSync(BANCO);
const db = abrirBanco(BANCO);
const servico = criarServico(db);
if (novo) {
  const senha = process.env.M360_SENHA_PILOTO || SENHA_PADRAO_PILOTO;
  semear(db, servico, { senha });
  console.log(`Banco piloto criado com dados sintéticos em ${BANCO}.`);
}

createServer(criarApp(servico)).listen(PORTA, HOST, () => {
  console.log(`Matrícula 360° (piloto) em http://${HOST}:${PORTA}`);
  console.log('Somente dados sintéticos. IA e envio externo desativados.');
});
