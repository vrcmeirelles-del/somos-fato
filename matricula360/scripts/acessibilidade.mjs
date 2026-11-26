// Auditoria de acessibilidade (axe-core, WCAG 2.0/2.1 A e AA) das telas da equipe e das páginas públicas.
// Só navega: não grava dados. Uso: M360_BASE=http://localhost:4197 node scripts/acessibilidade.mjs
import { createRequire } from 'node:module';
import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
const require = createRequire(import.meta.url);
const { chromium } = require('playwright');
const AXE = readFileSync(new URL('../web/node_modules/axe-core/axe.min.js', import.meta.url), 'utf8');
const BASE = process.env.M360_BASE || 'http://localhost:4197';
const senhas = JSON.parse(readFileSync(new URL('../dados/contas-homologacao.json', import.meta.url), 'utf8'));
const OUT = new URL('../docs/evidencias/acessibilidade/', import.meta.url).pathname; mkdirSync(OUT, { recursive: true });
const ROTAS = ['inteligencia', 'performance', 'intervencoes', 'planejamento', 'formularios', 'eventos', 'comunicacao', 'campanhas', 'crm', 'agenda', 'funis', 'seletivo', 'matriculas',
  'propostas', 'bolsas', 'recuperacao', 'academia', 'relacionamento', 'sucesso', 'rematricula', 'configuracoes', 'permissoes', 'seguranca', 'integracoes', 'auditoria'];
const auditar = async (page) => { await page.addScriptTag({ content: AXE });
  return page.evaluate(async () => (await window.axe.run(document, { runOnly: { type: 'tag', values: ['wcag2a', 'wcag2aa', 'wcag21a', 'wcag21aa'] } })).violations
    .map((v) => ({ id: v.id, impacto: v.impact, ajuda: v.help, nos: v.nodes.length, exemplo: v.nodes[0]?.target?.join(' ') + ' :: ' + (v.nodes[0]?.html ?? '').slice(0, 160) }))); };
const b = await chromium.launch();
const res = {};
for (const vp of [{ nome: 'desktop', viewport: { width: 1366, height: 900 } }, { nome: 'celular', viewport: { width: 390, height: 844 } }]) {
  const ctx = await b.newContext({ viewport: vp.viewport, bypassCSP: true }); const page = await ctx.newPage();
  await page.goto(`${BASE}/login`); await page.fill('#email', 'm360.gestor.alfa@example.com'); await page.fill('#senha', senhas['m360.gestor.alfa@example.com']);
  await page.click('button[type=submit]'); await page.waitForURL(/inteligencia/, { timeout: 20000 });
  res[`${vp.nome}:login`] = []; 
  for (const r of ROTAS) {
    await page.goto(`${BASE}/ies/1/${r}`); await page.waitForLoadState('networkidle'); await page.waitForTimeout(400);
    res[`${vp.nome}:${r}`] = await auditar(page);
  }
  // ficha do candidato aberta a partir do CRM
  await page.goto(`${BASE}/ies/1/crm`); await page.waitForLoadState('networkidle');
  const card = page.locator('main [data-op], main article button, main li button').first();
  if (await card.count()) { await card.click().catch(() => {}); await page.waitForTimeout(1200); res[`${vp.nome}:ficha`] = await auditar(page); }
  await ctx.close();
  const pub = await b.newContext({ viewport: vp.viewport, bypassCSP: true }); const pp = await pub.newPage();
  await pp.goto(`${BASE}/login`); await pp.waitForLoadState('networkidle'); res[`${vp.nome}:login`] = await auditar(pp);
  await pp.goto(`${BASE}/portal#${'a'.repeat(64)}`); await pp.waitForLoadState('networkidle'); await pp.waitForTimeout(800); res[`${vp.nome}:portal-invalido`] = await auditar(pp);
  await pub.close();
}
await b.close();
const total = {}; for (const [k, vs] of Object.entries(res)) for (const v of vs) { (total[v.id] ??= { impacto: v.impacto, ajuda: v.ajuda, telas: [], exemplo: v.exemplo }).telas.push(`${k}(${v.nos})`); }
writeFileSync(`${OUT}/resultado.json`, JSON.stringify({ quando: new Date().toISOString(), base: BASE, telas: Object.keys(res).length, regras_violadas: total, por_tela: res }, null, 2));
console.log(`telas auditadas: ${Object.keys(res).length}; regras violadas: ${Object.keys(total).length}`);
for (const [id, v] of Object.entries(total)) console.log(`- ${id} [${v.impacto}] ${v.ajuda}\n    telas: ${v.telas.slice(0, 8).join(', ')}${v.telas.length > 8 ? ` … (+${v.telas.length - 8})` : ''}\n    ex.: ${v.exemplo}`);
