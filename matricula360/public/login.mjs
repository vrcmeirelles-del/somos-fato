const form = document.getElementById('form');
const erro = document.getElementById('erro');
form.addEventListener('submit', async (ev) => {
  ev.preventDefault();
  erro.textContent = '';
  const botao = form.querySelector('button');
  botao.disabled = true;
  try {
    const r = await fetch('/api/login', {
      method: 'POST',
      headers: { 'content-type': 'application/json', 'x-m360': '1' },
      body: JSON.stringify({ email: form.email.value, senha: form.senha.value }),
    });
    const d = await r.json().catch(() => ({}));
    if (!r.ok) throw new Error(d.erro || 'Falha no login');
    const me = await (await fetch('/api/me')).json();
    const primeira = me.escopos[0];
    location.href = primeira ? `/ies/${primeira.ies_id}/dashboard` : (me.usuario.master ? '/master' : '/');
  } catch (e) {
    erro.textContent = e.message;
  } finally {
    botao.disabled = false;
  }
});
