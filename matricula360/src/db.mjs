import { DatabaseSync } from 'node:sqlite';
import { readFileSync } from 'node:fs';

export function abrirBanco(caminho = ':memory:') {
  const db = new DatabaseSync(caminho);
  db.exec('PRAGMA foreign_keys = ON; PRAGMA busy_timeout = 5000;');
  if (caminho !== ':memory:') db.exec('PRAGMA journal_mode = WAL;');
  const existe = db.prepare("SELECT count(*) AS n FROM sqlite_master WHERE type='table' AND name='ies'").get().n;
  if (!existe) db.exec(readFileSync(new URL('./schema.sql', import.meta.url), 'utf8'));
  return db;
}
