import { scryptSync, randomBytes, timingSafeEqual, createHash } from 'node:crypto';

const N = 16384;

export function gerarHash(senha) {
  if (typeof senha !== 'string' || senha.length < 10 || senha.length > 200) {
    throw new Error('Senha deve ter entre 10 e 200 caracteres');
  }
  const sal = randomBytes(16);
  const h = scryptSync(senha, sal, 32, { N });
  return `scrypt$${N}$${sal.toString('base64')}$${h.toString('base64')}`;
}

// Hash fictício: gasta o mesmo tempo quando o usuário não existe (evita enumeração por tempo).
const FICTICIO = gerarHash('senha-ficticia-para-tempo-constante');

export function conferirSenha(senha, armazenado) {
  const [alg, n, sal, h] = (armazenado || FICTICIO).split('$');
  if (alg !== 'scrypt') return false;
  const calc = scryptSync(String(senha ?? ''), Buffer.from(sal, 'base64'), 32, { N: Number(n) });
  const ok = timingSafeEqual(calc, Buffer.from(h, 'base64'));
  return Boolean(armazenado) && ok;
}

export const novoToken = () => randomBytes(32).toString('base64url');
export const hashToken = (t) => createHash('sha256').update(String(t)).digest('hex');
export const senhaTemporaria = () => randomBytes(12).toString('base64url');
