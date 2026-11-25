// Homologação local automatizada (Playwright pré-instalado no ambiente).
// Sobe o servidor com banco em memória, percorre fluxos por perfil em desktop e celular,
// verifica erros de console/CSP, rolagem horizontal e rótulos de formulário, e salva evidências.
import { spawn } from 'node:child_process';
import { mkdirSync, writeFileSync } from 'node:fs';
import { createRequire } from 'node:module';

const require = createRequire(import.meta.url);
const { chromium, devices } = require('playwright');
const PORTA = 4199;
const BASE = `http://127.0.0.1:${PORTA}`;
const SENHA = 'piloto-local-2026';
const OUT = 'docs/evidencias';
mkdirSync(OUT, { recursive: true });

const srv = spawn(process.execPath, ['--disable-warning=ExperimentalWarning', 'server.mjs'], { env: { ...process.env, PORT: String(PORTA), M360_BANCO: ':memory:' }, stdio: ['ignore', 'pipe', 'inherit'] });
await new Promise((ok, falha) => {
  srv.stdout.on('data', (b) => { if (String(b).includes('http://')) ok(); });
  setTimeout(() => falha(new Error('servidor não subiu')), 15000);
});

const resultados = [];
const registrar = (perfil, disp, passo, ok, detalhe = '') => { resultados.push({ perfil, dispositivo: disp, passo, ok, detalhe }); console.log(`${ok ? 'OK ' : 'FALHA'} [${disp}] ${perfil} · ${passo}${detalhe ? ' — ' + detalhe : ''}`); };

async function sessao(navegador, disp, email) {
  const ctx = await navegador.newContext(disp === 'celular' ? { ...devices['iPhone 13'] } : { viewport: { width: 1366, height: 860 } });
  const page = await ctx.newPage();
  const erros = [];
  page.on('console', (m) => { if (m.type() === 'error') erros.push(m.text()); });
  page.on('pageerror', (e) => erros.push(e.message));
  await page.goto(`${BASE}/login`);
  await page.fill('#email', email);
  await page.fill('#senha', SENHA);
  await Promise.all([page.waitForURL(/\/(ies|master)/), page.click('button[type=submit]')]);
  return { ctx, page, erros };
}
async function checar(page, perfil, disp, nome, erros) {
  await page.waitForLoadState('networkidle');
  const rolagem = await page.evaluate(() => document.documentElement.scrollWidth - document.documentElement.clientWidth);
  registrar(perfil, disp, `${nome}: sem rolagem horizontal da página`, rolagem <= 1, `excesso ${rolagem}px`);
  const semRotulo = await page.evaluate(() => [...document.querySelectorAll('input:not([type=hidden]), select, textarea')]
    .filter((el) => el.offsetParent !== null && !el.closest('label') && !el.getAttribute('aria-label') && !(el.id && document.querySelector(`label[for="${el.id}"]`))).length);
  registrar(perfil, disp, `${nome}: campos visíveis com rótulo acessível`, semRotulo === 0, `${semRotulo} sem rótulo`);
  registrar(perfil, disp, `${nome}: sem erros de console/CSP`, erros.length === 0, erros.join(' | ').slice(0, 300));
  await page.screenshot({ path: `${OUT}/${disp}-${perfil}-${nome}.png`, fullPage: true });
}

const navegador = await chromium.launch();
try {
  for (const disp of ['desktop', 'celular']) {
    // Página pública e demo legada
    {
      const ctx = await navegador.newContext(disp === 'celular' ? { ...devices['iPhone 13'] } : { viewport: { width: 1366, height: 860 } });
      const page = await ctx.newPage(); const erros = [];
      page.on('pageerror', (e) => erros.push(e.message));
      page.on('console', (m) => { if (m.type() === 'error') erros.push(m.text()); });
      await page.goto(BASE + '/'); await checar(page, 'publico', disp, 'inicio', erros);
      await page.goto(BASE + '/demo'); await page.click('#simulate');
      registrar('publico', disp, 'demo: simulação', (await page.textContent('#forecast')).includes('953'), await page.textContent('#forecast'));
      await checar(page, 'publico', disp, 'demo', erros);
      await ctx.close();
    }
    // Gestor
    {
      const { ctx, page, erros } = await sessao(navegador, disp, 'gestor.alfa@piloto.invalid');
      await page.waitForSelector('.kpi');
      const conv = await page.textContent('.kpis');
      registrar('gestor', disp, 'painel: indicadores carregados', /Conversão/.test(conv));
      await checar(page, 'gestor', disp, 'painel', erros);
      await page.selectOption('#coorte', '2026.2');
      await page.waitForTimeout(300);
      registrar('gestor', disp, 'painel: coorte sem meta exibe N/D', (await page.locator('.kpi .nd').count()) > 0);
      if (disp === 'desktop') {
        await page.click('text=Executar ciclo MAIM');
        await page.waitForSelector('text=Ciclo MAIM:');
        registrar('gestor', disp, 'MAIM: ciclo executado', true);
      }
      await page.click('nav >> text=CRM');
      await page.waitForSelector('.cartao');
      await checar(page, 'gestor', disp, 'crm', erros);
      await page.locator('.coluna[aria-label="Inscrito"] .cartao').first().click();
      await page.waitForSelector('#det-titulo');
      await page.fill('input[aria-label="Desconto em %"]', '55');
      await page.click('text=Gerar proposta');
      await page.waitForSelector('text=Pendente de aprovação');
      registrar('gestor', disp, 'proposta acima do limite fica pendente', true);
      await page.screenshot({ path: `${OUT}/${disp}-gestor-detalhe.png` });
      await page.click('#det-corpo button[aria-label="Fechar"]');
      await page.click('nav >> text=Propostas');
      await page.waitForSelector('table');
      await checar(page, 'gestor', disp, 'propostas', erros);
      await page.click('nav >> text=Configurações');
      await page.waitForSelector('text=Auditoria (somente leitura)');
      await checar(page, 'gestor', disp, 'configuracoes', erros);
      await ctx.close();
    }
    // Comercial: cria oportunidade
    {
      const { ctx, page, erros } = await sessao(navegador, disp, 'comercial1.alfa@piloto.invalid');
      await page.click('nav >> text=CRM');
      await page.click('summary:has-text("Nova oportunidade")');
      await page.fill('label:has-text("Nome") input', `Candidata Homologação ${disp}`);
      await page.fill('label:has-text("E-mail") input', `homolog.${disp}@exemplo.invalid`);
      await page.selectOption('label:has-text("Base legal") select', 'consentimento');
      await page.fill('label:has-text("Origem") input', 'homologação');
      await page.click('text=Cadastrar');
      await page.waitForSelector('text=criada e distribuída');
      registrar('comercial', disp, 'cadastro de oportunidade com base legal', true);
      await page.click('summary:has-text("Nova oportunidade")');
      await checar(page, 'comercial', disp, 'crm', erros);
      await ctx.close();
    }
    // Secretaria: valida
    {
      const { ctx, page, erros } = await sessao(navegador, disp, 'secretaria.alfa@piloto.invalid');
      await page.click('nav >> text=Matrículas');
      await page.waitForSelector('table');
      await checar(page, 'secretaria', disp, 'matriculas', erros);
      const linha = page.locator('tr:has(button:text("Registrar"))').first();
      await linha.locator('input[aria-label="Evidência"]').fill('Documentos conferidos na homologação');
      await linha.locator('button:text("Registrar")').click();
      await page.waitForSelector('text=Validação registrada com evidência');
      registrar('secretaria', disp, 'validação com evidência', true);
      await ctx.close();
    }
    // Coordenador: escopo restrito e dados mascarados
    {
      const { ctx, page, erros } = await sessao(navegador, disp, 'coord.direito.alfa@piloto.invalid');
      await page.waitForSelector('.kpi');
      registrar('coordenador', disp, 'painel restrito a cursos autorizados', (await page.textContent('main')).includes('somente cursos autorizados'));
      await page.click('nav >> text=CRM');
      await page.waitForSelector('.cartao');
      const adm = await page.locator('.cartao:has-text("Administração")').count();
      registrar('coordenador', disp, 'CRM sem cursos não autorizados', adm === 0, `${adm} cartões de outro curso`);
      await page.locator('.cartao').first().click();
      await page.waitForSelector('text=Dados mascarados');
      registrar('coordenador', disp, 'dados pessoais mascarados', true);
      await page.click('#det-corpo button[aria-label="Fechar"]');
      await checar(page, 'coordenador', disp, 'crm', erros);
      await ctx.close();
    }
    // Master
    {
      const { ctx, page, erros } = await sessao(navegador, disp, 'master@piloto.invalid');
      registrar('master', disp, 'master cai no painel Master', page.url().endsWith('/master'));
      await page.waitForSelector('table');
      await page.locator('button:text("Acessos")').first().click();
      await page.waitForSelector('text=Conceder escopo');
      await checar(page, 'master', disp, 'master', erros);
      const r = await page.evaluate(async () => (await fetch('/api/ies/1/oportunidades')).status);
      registrar('master', disp, 'master sem escopo não lê candidatos', r === 404, `status ${r}`);
      await ctx.close();
    }
  }
} catch (e) {
  registrar('execucao', '-', 'erro inesperado', false, e.message);
} finally {
  await navegador.close();
  srv.kill();
}
const falhas = resultados.filter((r) => !r.ok);
writeFileSync(`${OUT}/resultado.json`, JSON.stringify({ em: new Date().toISOString(), total: resultados.length, falhas: falhas.length, resultados }, null, 2));
console.log(`\n${resultados.length - falhas.length}/${resultados.length} verificações OK`);
process.exit(falhas.length ? 1 : 0);
