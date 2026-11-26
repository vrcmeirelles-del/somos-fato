import { entrar, api, modo } from './api.mjs';

const form = document.getElementById('form');
const erro = document.getElementById('erro');
modo().then((m) => {
  if (m === 'supabase') document.querySelector('.aviso').textContent = 'Homologação conectada ao Supabase, com dados sintéticos. Não insira dados reais de candidatos.';
});
form.addEventListener('submit', async (ev) => {
  ev.preventDefault();
  erro.textContent = '';
  const botao = form.querySelector('button');
  botao.disabled = true;
  try {
    await entrar(form.email.value, form.senha.value);
    const me = await api('GET', '/api/me');
    const primeira = me.escopos[0];
    location.href = primeira ? `/ies/${primeira.ies_id}/dashboard` : (me.usuario.master ? '/master' : '/');
  } catch (e) {
    erro.textContent = e.status === 400 || e.status === 401 ? 'Credenciais inválidas' : e.message;
  } finally {
    botao.disabled = false;
  }
});
