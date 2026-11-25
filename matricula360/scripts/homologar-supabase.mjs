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
const BASE = `http://127.0.0.1:${PORTA}`;
const OUT = 'docs/evidencias/supabase';
mkdirSync(OUT, { recursive: true });

const srv = spawn(process.execPath, ['--disable-warning=ExperimentalWarning', 'server.mjs'], {
  env: { ...process.env, PORT: String(PORTA), M360_SUPABASE_URL: SB_URL, M360_SUPABASE_CHAVE_PUBLICAVEL: SB_CHAVE }, stdio: ['ignore', 'pipe', 'inherit'] });
await new Promise((ok, falha) => { srv.stdout.on('data', (b) => { if (String(b).includes('http://')) ok(); }); setTimeout(() => falha(new Error('servidor não subiu')), 15000); });

const resultados = [];
const registrar = (perfil, disp, passo, ok, detalhe = '') => { resultados.push({ perfil, dispositivo: disp, passo, ok, detalhe }); console.log(`${ok ? 'OK ' : 'FALHA'} [${disp}] ${perfil} · ${passo}${detalhe ? ' — ' + detalhe : ''}`); };
const proxy = process.env.HTTPS_PROXY || process.env.https_proxy;
const navegador = await chromium.launch(proxy ? { proxy: { server: proxy, bypass: '127.0.0.1,localhost' } } : {});

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
// Chama a ponte das telas direto no navegador (simula adulteração feita pelo usuário no próprio cliente).
const chamar = (page, metodo, url, corpo) => page.evaluate(async ([m, u, c]) => {
  const { api } = await import('/api.mjs');
  try { return { ok: true, d: await api(m, u, c) }; } catch (e) { return { ok: false, status: e.status, msg: e.message }; }
}, [metodo, url, corpo]);

try {
  for (const disp of ['desktop', 'celular']) {
    // Gestor Alfa
    {
      const { ctx, page, erros } = await sessao(disp, 'gestor.alfa');
      await page.waitForSelector('.kpi');
      const kpis = await page.textContent('.kpis');
      registrar('gestor', disp, 'painel com dados do Supabase (16 da semente + as criadas na homologação)', /Oportunidades\s*(1[6-9]|[2-9]\d)/.test(kpis), kpis.replace(/\s+/g, ' ').slice(0, 120));
      registrar('gestor', disp, 'faixa indica homologação Supabase', (await page.textContent('.faixa')).includes('Homologação Supabase'));
      await checar(page, 'gestor', disp, 'painel', erros);
      await page.selectOption('#agrupar', 'turno');
      await page.waitForTimeout(800);
      registrar('gestor', disp, 'BI agrupado por turno', (await page.textContent('main table')).includes('noturno'));
      const beta = await chamar(page, 'GET', '/api/ies/2/bi?coorte=2027.1');
      registrar('gestor', disp, 'IDOR: BI da IES Beta recusado pelo banco', !beta.ok && beta.status === 404, `status ${beta.status}`);
      if (disp === 'desktop') {
        await page.click('nav >> text=CRM');
        await page.waitForSelector('.cartao');
        await checar(page, 'gestor', disp, 'crm', erros);
        await page.locator('.coluna[aria-label="Inscrito"] .cartao').first().click();
        await page.waitForSelector('#det-titulo');
        registrar('gestor', disp, 'detalhe com histórico auditado', (await page.textContent('#det-corpo')).includes('oportunidade.criar'));
        await page.fill('input[aria-label="Desconto em %"]', '55');
        await page.click('text=Gerar proposta');
        await page.waitForSelector('text=Pendente de aprovação', { timeout: 15000 });
        registrar('gestor', disp, 'proposta acima do limite fica pendente', true);
        await page.screenshot({ path: `${OUT}/${disp}-gestor-detalhe.png` });
        await page.click('#det-corpo button[aria-label="Fechar"]');
        await page.click('nav >> text=Propostas');
        await page.waitForSelector('main table');
        const aprovar = page.locator('tr:has-text("Atendente Alfa") button:text("Aprovar")').first();
        if (await aprovar.count()) {
          await aprovar.click();
          await page.waitForSelector('text=: Aprovada', { timeout: 15000 });
          registrar('gestor', disp, 'aprova proposta criada por outro usuário', true);
        } else registrar('gestor', disp, 'aprova proposta criada por outro usuário', false, 'nenhuma pendente do comercial');
        const propria = page.locator('tr:has-text("Gestora Alfa") button:text("Aprovar")').first();
        if (await propria.count()) {
          await propria.click();
          await page.waitForSelector('text=Segregação de funções', { timeout: 15000 });
          registrar('gestor', disp, 'não aprova a própria proposta (segregação)', true);
        }
        await page.click('nav >> text=Configurações');
        await page.waitForSelector('text=Auditoria (somente leitura)');
        await page.waitForSelector('code');
        await checar(page, 'gestor', disp, 'configuracoes', erros);
      }
      await ctx.close();
    }
    // Comercial Alfa
    {
      const { ctx, page, erros } = await sessao(disp, 'comercial.alfa');
      await page.click('nav >> text=CRM');
      await page.waitForSelector('.cartao');
      if (disp === 'desktop') {
        await page.click('summary:has-text("Nova oportunidade")');
        await page.fill('label:has-text("Nome") input', 'Candidata Homologação Supabase');
        await page.fill('label:has-text("E-mail") input', `homolog.${Date.now()}@example.com`);
        await page.fill('label:has-text("Coorte") input', '2027.1');
        await page.click('text=Cadastrar');
        await page.waitForSelector('role=status >> text=Base legal obrigatória', { timeout: 15000 }).catch(() => null);
        registrar('comercial', disp, 'sem base legal o banco recusa (LGPD)', (await page.textContent('main')).includes('Base legal obrigatória'));
        await page.selectOption('label:has-text("Base legal") select', 'consentimento');
        await page.fill('label:has-text("Origem") input', 'homologação supabase');
        await page.click('text=Cadastrar');
        await page.waitForSelector('text=criada e distribuída', { timeout: 15000 });
        registrar('comercial', disp, 'cadastro com base legal gravado no Supabase', true);
        await page.locator('.coluna[aria-label="Novo"] .cartao:has-text("Candidata Homologação Supabase")').first().click();
        await page.waitForSelector('#det-titulo');
        await page.click('#det-corpo button:text("→ Contato")');
        await page.waitForSelector('text=Etapa atualizada para Contato', { timeout: 15000 });
        registrar('comercial', disp, 'move etapa com versão', true);
        await page.click('#det-corpo button[aria-label="Fechar"]');
      }
      const val = await chamar(page, 'POST', '/api/oportunidades/1/validacoes', { dimensao: 'documental', resultado: 'valida', evidencia: 'tentativa indevida', versao_esperada: 1 });
      registrar('comercial', disp, 'comercial não valida (403 do banco)', !val.ok && [403, 422].includes(val.status), `${val.status} ${val.msg}`);
      await checar(page, 'comercial', disp, 'crm', erros);
      await ctx.close();
    }
    // Secretaria e financeiro: validação com evidência
    if (disp === 'desktop') {
      for (const [perfil, dim] of [['secretaria.alfa', 'Documental'], ['financeiro.alfa', 'Financeira']]) {
        const { ctx, page, erros } = await sessao(disp, perfil);
        await page.click('nav >> text=Matrículas');
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
      await page.click('nav >> text=CRM');
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
      const alfa = await chamar(page, 'GET', '/api/ies/1/estrutura');
      registrar('gestor-beta', disp, 'IDOR: estrutura da Alfa recusada', !alfa.ok && alfa.status === 404, `status ${alfa.status}`);
      await checar(page, 'gestor-beta', disp, 'painel', erros);
      await ctx.close();
    }
    // Master
    {
      const { ctx, page, erros } = await sessao(disp, 'master');
      registrar('master', disp, 'Master cai no painel Master', page.url().endsWith('/master'));
      await page.waitForSelector('main table');
      registrar('master', disp, 'lista as 2 IES', (await page.locator('main table tbody tr').count()) === 2);
      const cand = await chamar(page, 'GET', '/api/oportunidades/1');
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
  srv.kill();
}
const falhas = resultados.filter((r) => !r.ok);
writeFileSync(`${OUT}/resultado.json`, JSON.stringify({ em: new Date().toISOString(), projeto: SB_URL, total: resultados.length, falhas: falhas.length, resultados }, null, 2));
console.log(`\n${resultados.length - falhas.length}/${resultados.length} verificações OK`);
process.exit(falhas.length ? 1 : 0);
