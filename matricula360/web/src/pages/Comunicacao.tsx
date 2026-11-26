import { FileSignature, FileText, MessagesSquare, PlugZap, ShieldCheck, Upload } from 'lucide-react';
import { useState } from 'react';
import { useSessao } from '../components/Layout';
import { Aviso, Campo, Cartao, Chip, Detalhes, Estado, Kpi, Mensagem, Titulo, Vazio } from '../components/ui';
import { api } from '../lib/api';
import { lerCsv } from '../lib/arquivo';
import { centavos, rotulo } from '../lib/formato';
import { useAcao, useCarregar } from '../lib/hooks';
import type { ErroApi } from '../lib/supabase';

const GATILHOS = ['etapa_novo', 'etapa_contato', 'etapa_inscrito', 'etapa_pre_matricula', 'documento_pendente', 'evento_inscrito', 'manual'];

// Comunicação (L6): modelos e régua em modo simulação. Nada é enviado.
export function Comunicacao() {
  const { ies } = useSessao();
  const [recarga, setRecarga] = useState(0);
  const c = useCarregar(() => api.comunicacao(ies!), [ies, recarga]);
  const acao = useAcao();
  const fazer = (fn: () => Promise<string>) => acao.executar(async () => { const t = await fn(); setRecarga((n) => n + 1); return t; });
  const vazio = { nome: '', canal: 'email', gatilho: 'etapa_novo', assunto: '', corpo: 'Olá, {{nome}}! ' };
  const [n, setN] = useState(vazio);
  const d = c.dados;
  return (
    <>
      <Titulo titulo="Comunicação e réguas" subtitulo="Modelos por gatilho do funil, régua em modo simulação e textos para envio manual pela equipe." />
      {(c.erro as ErroApi | null)?.codigo === 'PGRST202' ? <Vazio texto="Disponível após a migração 21 do banco." /> : <Estado carregando={c.carregando && !d} erro={c.erro} />}
      <Mensagem m={acao.mensagem} />
      {d && (
        <div className="space-y-4">
          <Aviso>{d.aviso} Variáveis disponíveis: {'{{nome}}'}, {'{{curso}}'}, {'{{instituicao}}'}.</Aviso>
          <div className="kpis grid grid-cols-2 gap-3 md:grid-cols-4">
            <Kpi rotulo="Simuladas" valor={String(d.modelos.reduce((s, m) => s + m.simuladas, 0))} icone={MessagesSquare} />
            <Kpi rotulo="Bloqueadas (opt-out/LGPD)" valor={String(d.modelos.reduce((s, m) => s + m.bloqueadas, 0))} />
            <Kpi rotulo="Copiadas para envio manual" valor={String(d.modelos.reduce((s, m) => s + m.copiadas, 0))} />
            <Kpi rotulo="Taxa de abertura" valor="N/D" detalhe="Sem provedor de envio autorizado" />
          </div>
          {d.pode_gerir && (<>
            <Detalhes titulo="Novo modelo de mensagem">
              <form className="grid gap-2 sm:grid-cols-3" onSubmit={(e) => { e.preventDefault(); void fazer(async () => { await api.salvarModeloMensagem(ies!, n); setN(vazio); return 'Modelo criado.'; }); }}>
                <Campo rotulo="Nome"><input className="campo" required minLength={3} value={n.nome} onChange={(e) => setN({ ...n, nome: e.target.value })} /></Campo>
                <Campo rotulo="Canal"><select className="campo" value={n.canal} onChange={(e) => setN({ ...n, canal: e.target.value })}>{['email', 'whatsapp', 'sms'].map((x) => <option key={x} value={x}>{rotulo(x)}</option>)}</select></Campo>
                <Campo rotulo="Gatilho"><select className="campo" value={n.gatilho} onChange={(e) => setN({ ...n, gatilho: e.target.value })}>{GATILHOS.map((x) => <option key={x} value={x}>{rotulo(x)}</option>)}</select></Campo>
                {n.canal === 'email' && <Campo rotulo="Assunto" className="sm:col-span-3"><input className="campo" value={n.assunto} onChange={(e) => setN({ ...n, assunto: e.target.value })} /></Campo>}
                <Campo rotulo="Texto" className="sm:col-span-3"><textarea className="campo min-h-[80px]" required minLength={10} maxLength={2000} value={n.corpo} onChange={(e) => setN({ ...n, corpo: e.target.value })} /></Campo>
                <div><button className="btn btn-peq" disabled={acao.enviando}>Criar modelo</button></div>
              </form>
            </Detalhes>
            <button className="btn" disabled={acao.enviando} onClick={() => void fazer(async () => { const r = await api.executarRegua(ies!); return `Régua executada em simulação: ${r.simuladas} simulada(s), ${r.bloqueadas} bloqueada(s), ${r.enviadas} enviada(s).`; })}>
              Executar régua (simulação)</button>
          </>)}
          {!d.modelos.length && <Vazio texto="Nenhum modelo de mensagem." />}
          {d.modelos.map((m) => (
            <Cartao key={m.id} titulo={m.nome} icone={MessagesSquare} acao={<span><Chip>{rotulo(m.canal)}</Chip><Chip tipo="tec">{rotulo(m.gatilho)}</Chip></span>}>
              {m.assunto && <p className="text-sm font-medium">{m.assunto}</p>}
              <p className="whitespace-pre-line text-sm">{m.corpo}</p>
              <p className="nota mt-1">Simuladas {m.simuladas} · bloqueadas {m.bloqueadas} · copiadas {m.copiadas} · abertura N/D · clique N/D</p>
            </Cartao>))}
          {d.recentes && d.recentes.length > 0 && (
            <Cartao titulo="Mensagens recentes (simulação)" icone={MessagesSquare}>
              <div className="tabela"><table>
                <thead><tr>{['Quando', 'Pessoa', 'Canal', 'Destino', 'Situação'].map((h) => <th key={h} scope="col">{h}</th>)}</tr></thead>
                <tbody>{d.recentes.map((r) => <tr key={r.id}><td>{new Date(r.em).toLocaleString('pt-BR')}</td><td>{r.nome}</td><td>{rotulo(r.canal)}</td><td>{r.destino ?? '—'}</td>
                  <td><Chip tipo={r.status === 'bloqueada' ? 'erro' : 'tec'}>{rotulo(r.status)}</Chip><span className="block text-xs text-suave">{r.motivo}</span></td></tr>)}</tbody>
              </table></div>
            </Cartao>)}
        </div>)}
    </>
  );
}

// Integrações, importações, contrato, documentos exigidos e solicitações de titulares (L5, L8, L9, LGPD).
export function Integracoes() {
  const { ies, tem } = useSessao();
  const [recarga, setRecarga] = useState(0);
  const i = useCarregar(() => (tem('gestor') ? api.integracoes(ies!) : Promise.resolve(null)), [ies, recarga]);
  const acao = useAcao();
  const fazer = (fn: () => Promise<string>) => acao.executar(async () => { const t = await fn(); setRecarga((n) => n + 1); return t; });
  return (
    <>
      <Titulo titulo="Integrações e dados" subtitulo="Integrações externas (desligadas), importações por planilha, contrato de matrícula, documentos exigidos e solicitações de titulares." />
      {(i.erro as ErroApi | null)?.codigo === 'PGRST202' ? <Vazio texto="Disponível após a migração 21 do banco." /> : <Estado carregando={i.carregando && !i.dados} erro={i.erro} />}
      <Mensagem m={acao.mensagem} />
      {!i.erro && !i.carregando && (
        <div className="space-y-4">
          {i.dados && <Cartao titulo="Integrações externas" icone={PlugZap}>
            <Aviso>{i.dados.aviso}</Aviso>
            <div className="tabela mt-2"><table>
              <thead><tr>{['Integração', 'Situação', 'Pedido', ''].map((h) => <th key={h} scope="col">{h}</th>)}</tr></thead>
              <tbody>{i.dados.itens.map((x) => (
                <tr key={x.tipo}><td>{rotulo(x.tipo)}</td><td><Chip tipo={x.status === 'pedido_registrado' ? 'pend' : undefined}>{rotulo(x.status)}</Chip></td>
                  <td className="text-xs">{x.pedido_em ? `${x.pedido_por} em ${new Date(x.pedido_em).toLocaleDateString('pt-BR')}: ${x.observacao}` : '—'}</td>
                  <td>{x.status === 'desligada' && <button className="btn btn-sec btn-peq" disabled={acao.enviando} onClick={() => {
                    const obs = window.prompt(`Pedido de ativação de ${rotulo(x.tipo)}: informe fornecedor e finalidade. O pedido não ativa nada; a decisão é do responsável do produto.`); if (!obs) return;
                    void fazer(async () => { await api.integracoes(ies!, x.tipo, obs); return 'Pedido registrado.'; }); }}>Registrar pedido</button>}</td></tr>))}</tbody>
            </table></div>
          </Cartao>}
          <Importacoes fazer={fazer} enviando={acao.enviando} />
          {tem('gestor') && <Contrato />}
          {tem('gestor') && <DocumentosExigidos />}
          {tem('gestor') && <Solicitacoes />}
        </div>)}
    </>
  );
}

function Importacoes({ fazer, enviando }: { fazer: (fn: () => Promise<string>) => Promise<void>; enviando: boolean }) {
  const { ies, tem } = useSessao();
  const [rel, setRel] = useState<{ linha: number; motivo: string }[]>([]);
  const ler = (f: File) => new Promise<string>((ok) => { const r = new FileReader(); r.onload = () => ok(String(r.result)); r.readAsText(f, 'utf-8'); });
  return (
    <Cartao titulo="Importações por planilha (CSV com ; )" icone={Upload}>
      <p className="nota mb-2">Use enquanto as integrações estiverem desligadas. Reimportar a mesma planilha não duplica custos.</p>
      <div className="grid gap-3 sm:grid-cols-2">
        {tem('gestor', 'financeiro') && <label className="rounded-lg border border-dashed border-linha p-3 text-sm">
          <strong>Custos de mídia</strong><span className="block text-xs text-suave">Colunas: campanha;data;valor;descricao (valor em reais, ex.: 450,00)</span>
          <input type="file" accept=".csv,text/csv" className="mt-2 text-xs" disabled={enviando} onChange={(e) => { const f = e.target.files?.[0]; if (!f) return;
            void fazer(async () => { const linhas = lerCsv(await ler(f)).map((l) => ({ campanha: l.campanha, data: l.data, valor_centavos: centavos(l.valor ?? '0'), descricao: l.descricao }));
              const r = await api.importarCustos(ies!, linhas); setRel(r.rejeitadas); return `Custos: ${r.importadas} importado(s), ${r.repetidas} já existente(s), ${r.rejeitadas.length} rejeitado(s).`; }); }} /></label>}
        {tem('gestor', 'secretaria') && <label className="rounded-lg border border-dashed border-linha p-3 text-sm">
          <strong>Vínculos acadêmicos</strong><span className="block text-xs text-suave">Colunas: email;marco (d30, d90 ou rematricula);situacao (ativo, trancado, evadido, transferido);data;observacao</span>
          <input type="file" accept=".csv,text/csv" className="mt-2 text-xs" disabled={enviando} onChange={(e) => { const f = e.target.files?.[0]; if (!f) return;
            void fazer(async () => { const r = await api.importarVinculos(ies!, lerCsv(await ler(f))); setRel(r.rejeitadas); return `Vínculos: ${r.importadas} importado(s), ${r.rejeitadas.length} rejeitado(s).`; }); }} /></label>}
      </div>
      {rel.length > 0 && <ul className="mt-2 text-xs text-erro">{rel.map((x) => <li key={x.linha}>Linha {x.linha}: {x.motivo}</li>)}</ul>}
    </Cartao>
  );
}

function Contrato() {
  const { ies } = useSessao();
  const [recarga, setRecarga] = useState(0);
  const c = useCarregar(() => api.contratos(ies!), [ies, recarga]);
  const acao = useAcao();
  const [texto, setTexto] = useState('');
  const atual = c.dados?.versoes.find((v) => v.ativo);
  return (
    <Cartao titulo="Contrato da matrícula online" icone={FileSignature}>
      {c.dados && <p className="mb-2 rounded-lg bg-amber-50 px-3 py-2 text-xs text-alerta">{c.dados.aviso}</p>}
      {atual ? <p className="text-sm">Versão vigente: <strong>v{atual.versao}</strong> · {atual.aceites} aceite(s)</p> : <p className="nota">Nenhum contrato publicado: a matrícula online fica indisponível no portal.</p>}
      <Mensagem m={acao.mensagem} />
      <Detalhes titulo={atual ? 'Publicar nova versão' : 'Publicar contrato'}>
        <textarea className="campo min-h-[160px] w-full" placeholder={atual?.texto ?? 'Texto do contrato de prestação de serviços educacionais…'} value={texto} onChange={(e) => setTexto(e.target.value)} />
        <button className="btn btn-peq mt-2" disabled={acao.enviando || texto.trim().length < 100} onClick={() => void acao.executar(async () => {
          const r = await api.salvarContrato(ies!, texto); setTexto(''); setRecarga((n) => n + 1); return `Contrato v${r.versao} publicado; aceites anteriores mantêm a versão aceita.`; })}>Publicar versão</button>
      </Detalhes>
    </Cartao>
  );
}

function DocumentosExigidos() {
  const { ies, estrutura } = useSessao();
  const [recarga, setRecarga] = useState(0);
  const d = useCarregar(() => api.configurarDocumentos(ies!, null), [ies, recarga]);
  const acao = useAcao();
  const [n, setN] = useState({ tipo: '', descricao: '', forma_ingresso: '', obrigatorio: true });
  return (
    <Cartao titulo="Documentos exigidos" icone={FileText}>
      <Mensagem m={acao.mensagem} />
      {d.dados && (<>
        <label className="flex items-center gap-2 text-sm"><input type="checkbox" checked={d.dados.exigir_documentos} disabled={acao.enviando} onChange={(e) => void acao.executar(async () => {
          await api.configurarDocumentos(ies!, e.target.checked); setRecarga((x) => x + 1); return e.target.checked ? 'Validação documental passa a exigir o checklist aprovado.' : 'Exigência desligada.'; })} />
          Exigir todos os documentos obrigatórios aprovados antes da validação documental</label>
        <ul className="mt-2 text-sm">{d.dados.itens.map((x) => <li key={`${x.forma_ingresso}-${x.tipo}`}>{x.descricao} <Chip>{x.forma_ingresso ? rotulo(x.forma_ingresso) : 'todas as formas'}</Chip>{x.obrigatorio ? <Chip tipo="pend">obrigatório</Chip> : <Chip>opcional</Chip>}</li>)}</ul>
        <form className="mt-2 flex flex-wrap items-end gap-2" onSubmit={(e) => { e.preventDefault(); void acao.executar(async () => { await api.configurarDocumentos(ies!, null, n); setRecarga((x) => x + 1); setN({ tipo: '', descricao: '', forma_ingresso: '', obrigatorio: true }); return 'Item incluído.'; }); }}>
          <Campo rotulo="Código"><input className="campo w-32" required pattern="[a-z0-9_]{3,40}" value={n.tipo} onChange={(e) => setN({ ...n, tipo: e.target.value })} /></Campo>
          <Campo rotulo="Descrição" className="grow"><input className="campo" required minLength={3} value={n.descricao} onChange={(e) => setN({ ...n, descricao: e.target.value })} /></Campo>
          <Campo rotulo="Forma de ingresso"><select className="campo" value={n.forma_ingresso} onChange={(e) => setN({ ...n, forma_ingresso: e.target.value })}><option value="">Todas</option>
            {estrutura?.formas_ingresso.map((x) => <option key={x} value={x}>{rotulo(x)}</option>)}</select></Campo>
          <label className="flex items-center gap-1 pb-2 text-sm"><input type="checkbox" checked={n.obrigatorio} onChange={(e) => setN({ ...n, obrigatorio: e.target.checked })} />Obrigatório</label>
          <button className="btn btn-sec btn-peq" disabled={acao.enviando}>Incluir</button>
        </form>
      </>)}
    </Cartao>
  );
}

function Solicitacoes() {
  const { ies } = useSessao();
  const [recarga, setRecarga] = useState(0);
  const s = useCarregar(() => api.solicitacoesTitular(ies!), [ies, recarga]);
  const acao = useAcao();
  return (
    <Cartao titulo="Solicitações de titulares (LGPD)" icone={ShieldCheck}>
      <Mensagem m={acao.mensagem} />
      {s.dados?.length ? (
        <div className="tabela"><table>
          <thead><tr>{['Titular', 'Pedido', 'Prazo interno', 'Situação', ''].map((h) => <th key={h} scope="col">{h}</th>)}</tr></thead>
          <tbody>{s.dados.map((x) => (
            <tr key={x.id}><td>{x.nome}</td><td>{rotulo(x.tipo)}{x.detalhe && <span className="block text-xs text-suave">{x.detalhe}</span>}</td>
              <td>{new Date(x.prazo).toLocaleDateString('pt-BR')}</td><td><Chip tipo={x.status === 'aberta' ? 'pend' : 'ok'}>{rotulo(x.status)}</Chip>{x.resposta && <span className="block text-xs">{x.resposta}</span>}</td>
              <td className="whitespace-nowrap">{x.status === 'aberta' && ['atendida', 'recusada'].map((st) => <button key={st} className="btn btn-sec btn-peq mr-1" disabled={acao.enviando} onClick={() => {
                const r = window.prompt(`Resposta ao titular (${rotulo(st).toLowerCase()}):`); if (!r) return;
                void acao.executar(async () => { await api.tratarSolicitacao(x.id, st, r); setRecarga((n) => n + 1); return 'Solicitação tratada.'; }); }}>{rotulo(st)}</button>)}</td></tr>))}</tbody>
        </table></div>
      ) : <p className="nota">Nenhuma solicitação. Pedidos de eliminação atendidos devem ser executados com "Anonimizar titular" na ficha.</p>}
    </Cartao>
  );
}
