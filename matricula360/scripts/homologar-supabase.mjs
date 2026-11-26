// Homologação no navegador com as telas ligadas ao Supabase de homologação (sem publicar:
// o servidor local escuta só em 127.0.0.1 e entrega as telas; dados e regras ficam no Supabase).
// Usa as contas sintéticas de dados/contas-homologacao.json (senhas fora do Git).
import { spawn } from 'node:child_process';
import { mkdirSync, writeFileSync, readFileSync } from 'node:fs';
import { createRequire } from 'node:module';

const require = createRequire(import.meta.url);
const { chromium, devices } = require('playwright');
const SB_URL = process.env.M360_SUPABASE_URL || 'https://jbimijcvvekomovodfze.supabase.co';
const SB_CHAVE = process.env.M360_SUPABASE_CHAVE_PUBLICAVEL;
if (!SB_CHAVE) { console.error('Defina M360_SUPABASE_CHAVE_PUBLICAVEL (sb_publishable_...).'); process.exit(1); }
const senhas = JSON.parse(readFileSync('dados/contas-homologacao.json', 'utf8'));
const conta = (p) => `m360.${p}@example.com`;
const PORTA = 4198;
const EXTERNA = process.env.M360_BASE_EXTERNA; // ex.: https://matricula360-homologacao.onrender.com
const BASE = EXTERNA || `http://127.0.0.1:${PORTA}`;
const ESTATICO = process.env.M360_ESTATICO === '1';
const OUT = EXTERNA ? 'docs/evidencias/publicado' : ESTATICO ? 'docs/evidencias/render-simulado' : process.env.M360_UI === 'legado' ? 'docs/evidencias/supabase-legado' : 'docs/evidencias/supabase';
mkdirSync(OUT, { recursive: true });

const srv = EXTERNA ? null : ESTATICO
  ? spawn(process.execPath, ['scripts/servir-estatico.mjs'], { env: { ...process.env, PORT: String(PORTA), M360_SUPABASE_URL: SB_URL }, stdio: ['ignore', 'pipe', 'inherit'] })
  : spawn(process.execPath, ['--disable-warning=ExperimentalWarning', 'server.mjs'], {
  env: { ...process.env, PORT: String(PORTA), M360_SUPABASE_URL: SB_URL, M360_SUPABASE_CHAVE_PUBLICAVEL: SB_CHAVE, M360_UI: process.env.M360_UI || 'react' }, stdio: ['ignore', 'pipe', 'inherit'] });
if (srv) await new Promise((ok, falha) => { srv.stdout.on('data', (b) => { if (String(b).includes('http://')) ok(); }); setTimeout(() => falha(new Error('servidor não subiu')), 15000); });

const resultados = [];
const registrar = (perfil, disp, passo, ok, detalhe = '') => { resultados.push({ perfil, dispositivo: disp, passo, ok, detalhe }); console.log(`${ok ? 'OK ' : 'FALHA'} [${disp}] ${perfil} · ${passo}${detalhe ? ' — ' + detalhe : ''}`); };
const proxy = process.env.HTTPS_PROXY || process.env.https_proxy;
const navegador = await chromium.launch(proxy ? { proxy: { server: proxy, bypass: '127.0.0.1,localhost' } } : {});
if (EXTERNA) console.log(`Homologando o site publicado: ${EXTERNA}`);

async function sessao(disp, perfil) {
  const ctx = await navegador.newContext(disp === 'celular' ? { ...devices['iPhone 13'] } : { viewport: { width: 1366, height: 860 } });
  const page = await ctx.newPage();
  const erros = [];
  page.on('console', (m) => { if (m.type() === 'error' && !/status of 4\d\d/.test(m.text())) erros.push(m.text()); });
  page.on('pageerror', (e) => erros.push(e.message));
  await page.goto(`${BASE}/login`);
  await page.fill('#email', conta(perfil));
  await page.fill('#senha', senhas[conta(perfil)]);
  await Promise.all([page.waitForURL(/\/(ies|master)/, { timeout: 30000 }), page.click('button[type=submit]')]);
  return { ctx, page, erros };
}
async function checar(page, perfil, disp, nome, erros) {
  await page.waitForLoadState('networkidle');
  const rolagem = await page.evaluate(() => document.documentElement.scrollWidth - document.documentElement.clientWidth);
  registrar(perfil, disp, `${nome}: sem rolagem horizontal`, rolagem <= 1, `excesso ${rolagem}px`);
  registrar(perfil, disp, `${nome}: sem erros de console/CSP`, erros.length === 0, erros.join(' | ').slice(0, 300));
  await page.screenshot({ path: `${OUT}/${disp}-${perfil}-${nome}.png`, fullPage: disp === 'desktop' });
}
// Simula adulteração feita no próprio navegador: chama a RPC direto no Supabase com a sessão do usuário.
const chamar = (page, rpc, args) => page.evaluate(async ([nome, a]) => {
  const cfg = await (await fetch('/config.json')).json();
  const s = JSON.parse(sessionStorage.getItem('m360_sb_sessao') || 'null');
  const r = await fetch(`${cfg.supabase_url}/rest/v1/rpc/${nome}`, { method: 'POST',
    headers: { apikey: cfg.supabase_chave_publicavel, authorization: `Bearer ${s?.access}`, 'content-type': 'application/json' }, body: JSON.stringify(a) });
  const d = await r.json().catch(() => ({}));
  return { ok: r.ok, status: r.status, msg: d.message };
}, [rpc, args]);

// Navega pelo menu lateral (no celular, abre a gaveta antes).
async function ir(page, nome) {
  // Abaixo de 1024px o menu é uma gaveta: espera o botão existir e abre.
  if ((page.viewportSize()?.width ?? 1366) < 1024) await page.getByRole('button', { name: 'Abrir menu' }).click({ timeout: 15000 });
  await page.getByRole('link', { name: nome, exact: true }).click();
  await page.waitForLoadState('networkidle');
}

try {
  for (const disp of ['desktop', 'celular']) {
    // Gestor Alfa
    {
      const { ctx, page, erros } = await sessao(disp, 'gestor.alfa');
      await page.waitForSelector('.kpi');
      const kpis = await page.textContent('.kpis');
      registrar('gestor', disp, 'painel com dados do Supabase (16 da semente + as criadas na homologação)', /Oportunidades\s*(1[6-9]|[2-9]\d)/.test(kpis), kpis.replace(/\s+/g, ' ').slice(0, 120));
      registrar('gestor', disp, 'faixa indica homologação', (await page.locator('.faixa').first().textContent()).includes('omologação'));
      await checar(page, 'gestor', disp, 'painel', erros);
      const main = await page.textContent('main');
      registrar('gestor', disp, 'Central: funil com 6 etapas', (await page.locator('ol[aria-label="Funil comercial"] li').count()) === 6);
      registrar('gestor', disp, 'Central: desempenho por turno e modalidade', main.includes('Desempenho por turno') && main.includes('Noturno') && main.includes('Presencial'));
      registrar('gestor', disp, 'Central: custo por lead N/D com motivo (sem investimento)', main.includes('Sem investimento cadastrado'));
      registrar('gestor', disp, 'Central: alertas do MAIM', main.includes('Alertas e intervenções do MAIM'));
      registrar('gestor', disp, 'Central: sem rótulo técnico REACT', !(await page.textContent('body')).includes('REACT'));
      await page.selectOption('#filtro-curso', { label: 'Direito · noturno' });
      await page.waitForTimeout(1500);
      registrar('gestor', disp, 'filtro global de curso aplicado (cobertura recorte)', (await page.textContent('main')).includes('recorte filtrado') && page.url().includes('curso='));
      const beta = await chamar(page, 'rpc_bi', { p_ies: 2, p_coorte: '2027.1' });
      registrar('gestor', disp, 'IDOR: BI da IES Beta recusado pelo banco', !beta.ok && beta.status === 404, `status ${beta.status}`);
      if (disp === 'desktop') {
        await ir(page, 'Pipeline (CRM)');
        await page.waitForSelector('.cartao');
        await checar(page, 'gestor', disp, 'crm', erros);
        await page.locator('.coluna[aria-label="Inscrito"] .cartao').first().click();
        await page.waitForSelector('#det-corpo >> text=oportunidade.criar', { timeout: 15000 }).catch(() => null);
        registrar('gestor', disp, 'detalhe com histórico auditado', (await page.textContent('#det-corpo')).includes('oportunidade.criar'));
        await page.fill('input[aria-label="Desconto em %"]', '55');
        await page.click('text=Gerar proposta');
        await page.waitForSelector('text=Pendente de aprovação', { timeout: 15000 });
        registrar('gestor', disp, 'proposta acima do limite fica pendente', true);
        await page.screenshot({ path: `${OUT}/${disp}-gestor-detalhe.png` });
        await page.click('#det-corpo button[aria-label="Fechar"]');
        await ir(page, 'Propostas e bolsas');
        await page.waitForSelector('main table');
        await page.waitForSelector('main table tbody tr', { timeout: 15000 });
        const propria = page.locator('tr:has-text("Gestora Alfa") button:text("Aprovar")').first();
        if (await propria.count()) {
          await propria.click();
          await page.waitForSelector('text=Segregação de funções', { timeout: 15000 });
          registrar('gestor', disp, 'não aprova a própria proposta (segregação)', true);
        }
        await ir(page, 'Configurações e metas');
        await page.waitForFunction(() => document.querySelector('input[aria-label="Meta Direito"]')?.value === '10', null, { timeout: 15000 }).catch(() => null);
        registrar('gestor', disp, 'Configurações carregam a meta cadastrada (Direito = 10)', (await page.inputValue('input[aria-label="Meta Direito"]')) === '10');
        await checar(page, 'gestor', disp, 'configuracoes', erros);
        await ir(page, 'Auditoria');
        await page.waitForSelector('main li > p', { timeout: 15000 });
        const frases = await page.$$eval('main li > p', (els) => els.map((e) => e.textContent || ''));
        const cruas = frases.filter((f) => /— [a-z_]+\.[a-z_]+ \(/.test(f));
        registrar('gestor', disp, 'auditoria em linguagem institucional (nenhum evento em código cru)', frases.length > 0 && cruas.length === 0, `${frases.length} eventos; crus: ${cruas.slice(0, 2).join(' | ')}`);
        await checar(page, 'gestor', disp, 'auditoria', erros);
        await ir(page, 'Fila de intervenções (MAIM)');
        await page.waitForSelector('text=tarefa(s) aberta(s)', { timeout: 15000 });
        registrar('gestor', disp, 'fila sem botão de disparo externo', (await page.getByRole('button', { name: 'Disparar' }).count()) === 0);
        await checar(page, 'gestor', disp, 'intervencoes', erros);
      }
      await ctx.close();
    }
    // Comercial Alfa
    {
      const { ctx, page, erros } = await sessao(disp, 'comercial.alfa');
      await ir(page, 'Pipeline (CRM)');
      await page.waitForSelector('.cartao');
      if (disp === 'desktop') {
        await page.click('summary:has-text("Nova oportunidade")');
        await page.fill('label:has-text("Nome") input', 'Teste automatizado E2E');
        await page.fill('label:has-text("E-mail") input', `homolog.${Date.now()}@example.com`);
        await page.fill('label:has-text("Coorte") input', '2027.1');
        await page.click('text=Cadastrar');
        await page.waitForSelector('role=status >> text=Base legal obrigatória', { timeout: 15000 }).catch(() => null);
        registrar('comercial', disp, 'sem base legal o banco recusa (LGPD)', (await page.textContent('main')).includes('Base legal obrigatória'));
        await page.selectOption('label:has-text("Base legal") select', 'consentimento');
        await page.fill('label:has-text("Origem") input', 'teste automatizado (E2E)');
        await page.click('text=Cadastrar');
        await page.waitForSelector('text=criada e distribuída', { timeout: 15000 });
        registrar('comercial', disp, 'cadastro com base legal gravado no Supabase', true);
        await page.locator('.coluna[aria-label="Novo"] .cartao:has-text("Teste automatizado E2E")').first().click();
        await page.waitForSelector('#det-titulo');
        await page.click('#det-corpo button:text("→ Contato")');
        await page.waitForSelector('text=Etapa atualizada para Contato', { timeout: 15000 });
        registrar('comercial', disp, 'move etapa com versão', true);
        await page.click('#det-corpo button:text("→ Inscrito")');
        await page.waitForSelector('text=Etapa atualizada para Inscrito', { timeout: 15000 });
        await page.fill('input[aria-label="Desconto em %"]', '60');
        await page.click('text=Gerar proposta');
        await page.waitForSelector('#det-corpo >> text=Pendente de aprovação', { timeout: 15000 });
        registrar('comercial', disp, 'proposta do comercial acima do limite fica pendente', true);
        // CRM avançado (migração 10): só verificado quando o banco já tem a migração.
        if (await page.locator('#det-corpo h3:has-text("Linha do tempo")').count()) {
          const marca = `contato E2E ${Date.now()}`;
          await page.fill('#det-corpo label:has-text("Resumo do contato") textarea', marca);
          await page.click('#det-corpo button:text("Registrar interação")');
          await page.waitForSelector(`#det-corpo li:has-text("${marca}")`, { timeout: 15000 });
          registrar('comercial', disp, 'CRM: interação registrada aparece na linha do tempo', true);
          await page.fill('#det-corpo label:has-text("Objeção") input', 'achou a mensalidade alta (E2E)');
          await page.click('#det-corpo button:text("Registrar objeção")');
          await page.waitForSelector('#det-corpo li:has-text("achou a mensalidade alta (E2E)") >> text=Aberta', { timeout: 15000 });
          registrar('comercial', disp, 'CRM: objeção registrada como aberta', true);
          await page.fill('#det-corpo label:has-text("O que fazer") input', 'retornar sobre a proposta (E2E)');
          await page.click('#det-corpo button:text("Agendar")');
          await page.waitForSelector('#det-corpo li:has-text("retornar sobre a proposta (E2E)")', { timeout: 15000 });
          registrar('comercial', disp, 'CRM: agendamento aparece na agenda da ficha', true);
          const ficha = await page.textContent('#det-corpo');
          registrar('comercial', disp, 'CRM: score explicável com aviso de não decisão', ficha.includes('Score de priorização') && ficha.includes('não é usado para decidir ingresso'));
          await page.click('#det-corpo button[aria-label="Fechar"]');
          await page.fill('input[aria-label="Buscar por nome, e-mail ou telefone"]', 'Teste automatizado');
          await page.click('button[aria-label="Buscar"]');
          await page.waitForTimeout(2000);
          const nomes = await page.locator('.cartao strong').allTextContents();
          registrar('comercial', disp, 'CRM: busca por nome filtra o quadro', nomes.length > 0 && nomes.every((n) => n.includes('Teste automatizado')), `${nomes.length} cartões`);
          const cartao = page.locator('.coluna[aria-label="Inscrito"] .cartao:has-text("Teste automatizado E2E")').first();
          // Arrasto com o mouse em passos (o atalho dragTo não dispara os eventos HTML5 de forma confiável).
          const de = await cartao.boundingBox(); const para = await page.locator('.coluna[aria-label="Novo"]').boundingBox();
          await page.mouse.move(de.x + de.width / 2, de.y + de.height / 2); await page.mouse.down();
          await page.mouse.move(de.x + de.width / 2 + 10, de.y + de.height / 2 + 10, { steps: 5 });
          await page.mouse.move(para.x + para.width / 2, para.y + 60, { steps: 15 }); await page.mouse.up();
          await page.waitForSelector('main [role=alert]', { timeout: 15000 }).catch(() => null);
          registrar('comercial', disp, 'CRM: arrastar para transição inválida é recusado pelo servidor',
            (await page.locator('main [role=alert]:has-text("Transição inválida")').count()) > 0 && (await page.locator('.coluna[aria-label="Inscrito"] .cartao:has-text("Teste automatizado E2E")').count()) > 0);
          await ir(page, 'Agenda comercial');
          await page.waitForSelector('text=retornar sobre a proposta (E2E)', { timeout: 15000 }).catch(() => null);
          registrar('comercial', disp, 'CRM: agenda comercial lista o agendamento', (await page.textContent('main')).includes('retornar sobre a proposta (E2E)'));
          await ir(page, 'Pipeline (CRM)');
        } else {
          console.log('AVISO CRM avançado não verificado: banco sem a migração 10.');
          await page.click('#det-corpo button[aria-label="Fechar"]');
        }
      }
      const val = await chamar(page, 'rpc_validar', { p_op: 1, p_dimensao: 'documental', p_resultado: 'valida', p_evidencia: 'tentativa indevida', p_versao: 1 });
      registrar('comercial', disp, 'comercial não valida (403 do banco)', !val.ok && [403, 422].includes(val.status), `${val.status} ${val.msg}`);
      await checar(page, 'comercial', disp, 'crm', erros);
      await ctx.close();
    }
    // Gestor aprova a proposta criada pelo comercial nesta rodada (segregação: quem cria não aprova)
    if (disp === 'desktop') {
      const { ctx, page, erros } = await sessao(disp, 'gestor.alfa');
      await ir(page, 'Propostas e bolsas');
      await page.waitForSelector('main table tbody tr', { timeout: 15000 });
      const aprovar = page.locator('tr:has-text("Teste automatizado E2E"):has-text("Atendente Alfa") button:text("Aprovar")').first();
      if (await aprovar.count()) {
        await aprovar.click();
        await page.waitForSelector('text=: Aprovada', { timeout: 15000 });
        registrar('gestor', disp, 'aprova proposta criada por outro usuário', true);
      } else registrar('gestor', disp, 'aprova proposta criada por outro usuário', false, 'proposta do comercial não encontrada');
      await checar(page, 'gestor', disp, 'propostas', erros);
      await ctx.close();
    }
    // Secretaria e financeiro: validação com evidência
    if (disp === 'desktop') {
      for (const [perfil, dim] of [['secretaria.alfa', 'Documental'], ['financeiro.alfa', 'Financeira']]) {
        const { ctx, page, erros } = await sessao(disp, perfil);
        await ir(page, 'Matrículas');
        await page.waitForSelector('main table');
        const linha = page.locator('tr:has(button:text("Registrar"))').first();
        await linha.locator('select[aria-label="Dimensão"]').selectOption({ label: dim });
        await linha.locator('input[aria-label="Evidência"]').fill(`Conferência ${dim.toLowerCase()} na homologação Supabase`);
        await linha.locator('button:text("Registrar")').click();
        await page.waitForSelector('text=Validação registrada com evidência', { timeout: 15000 });
        registrar(perfil, disp, `validação ${dim.toLowerCase()} gravada no Supabase`, true);
        await checar(page, perfil.split('.')[0], disp, 'matriculas', erros);
        await ctx.close();
      }
    }
    // Coordenação: só Direito e dados mascarados
    {
      const { ctx, page, erros } = await sessao(disp, 'coord.alfa');
      await page.waitForSelector('.kpi');
      registrar('coordenador', disp, 'painel limitado ao curso autorizado', (await page.textContent('main')).includes('somente cursos autorizados'));
      await ir(page, 'Pipeline (CRM)');
      await page.waitForSelector('.cartao');
      registrar('coordenador', disp, 'CRM sem Administração', (await page.locator('.cartao:has-text("Administração")').count()) === 0);
      await page.locator('.cartao').first().click();
      await page.waitForSelector('text=Dados mascarados', { timeout: 15000 });
      registrar('coordenador', disp, 'contatos mascarados pelo banco', true);
      await page.click('#det-corpo button[aria-label="Fechar"]');
      await checar(page, 'coordenador', disp, 'crm', erros);
      await ctx.close();
    }
    // Gestor Beta: isolamento entre instituições
    {
      const { ctx, page, erros } = await sessao(disp, 'gestor.beta');
      await page.waitForSelector('.kpi');
      const kpis = await page.textContent('.kpis');
      registrar('gestor-beta', disp, 'vê só a Beta (8 oportunidades)', /Oportunidades\s*8/.test(kpis), kpis.replace(/\s+/g, ' ').slice(0, 80));
      const alfa = await chamar(page, 'rpc_estrutura', { p_ies: 1 });
      registrar('gestor-beta', disp, 'IDOR: estrutura da Alfa recusada', !alfa.ok && alfa.status === 404, `status ${alfa.status}`);
      await checar(page, 'gestor-beta', disp, 'painel', erros);
      await ctx.close();
    }
    // Master
    {
      const { ctx, page, erros } = await sessao(disp, 'master');
      registrar('master', disp, 'Master cai no painel Master', page.url().endsWith('/master'));
      await page.waitForSelector('main table tbody tr', { timeout: 15000 });
      registrar('master', disp, 'lista as 2 IES', (await page.locator('main table tbody tr').count()) === 2);
      const cand = await chamar(page, 'rpc_detalhe', { p_op: 1 });
      registrar('master', disp, 'Master sem escopo não lê candidato', !cand.ok && cand.status === 404, `status ${cand.status}`);
      await page.locator('button:text("Acessos")').first().click();
      await page.waitForSelector('text=Conceder escopo');
      await checar(page, 'master', disp, 'master', erros);
      await ctx.close();
    }
  }
} catch (e) {
  registrar('execucao', '-', 'erro inesperado', false, e.message.split('\n')[0]);
} finally {
  await navegador.close();
  srv?.kill();
}
const falhas = resultados.filter((r) => !r.ok);
writeFileSync(`${OUT}/resultado.json`, JSON.stringify({ em: new Date().toISOString(), projeto: SB_URL, total: resultados.length, falhas: falhas.length, resultados }, null, 2));
console.log(`\n${resultados.length - falhas.length}/${resultados.length} verificações OK`);
process.exit(falhas.length ? 1 : 0);
