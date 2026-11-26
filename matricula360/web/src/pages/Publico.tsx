import { CheckCircle2, Download, FileUp, GraduationCap, Loader2, ShieldCheck } from 'lucide-react';
import { useEffect, useRef, useState, type ReactNode } from 'react';
import { useParams } from 'react-router-dom';
import { Campo, Chip, Mensagem } from '../components/ui';
import { publico } from '../lib/api';
import { lerBase64 } from '../lib/arquivo';
import { moeda, rotulo } from '../lib/formato';
import { useAcao, useCarregar } from '../lib/hooks';
import { TextoContrato } from '../components/TextoContrato';
import { baixarTexto, comprovanteHtml, nomeComprovante } from '../lib/contrato';
import type { CodigoAceite, FormularioPublico as TForm, PortalDados, PortalMatricula } from '../lib/tipos';

// Moldura das páginas públicas: sem menu interno, sem dados da equipe.
function Moldura({ instituicao, children }: { instituicao?: string; children: ReactNode }) {
  return (
    <div className="min-h-screen bg-fundo">
      <header className="bg-marinho px-4 py-4 text-white"><div className="mx-auto flex max-w-3xl items-center gap-2"><GraduationCap className="h-5 w-5" aria-hidden />
        <span className="font-semibold">{instituicao ?? 'Matrícula 360°'}</span></div></header>
      <main className="mx-auto max-w-3xl px-4 py-6">{children}</main>
      <footer className="mx-auto max-w-3xl px-4 pb-6 text-xs text-suave">Ambiente de homologação com dados sintéticos. Seus dados são tratados conforme a LGPD.</footer>
    </div>
  );
}

// ---------------------------------------------------------------- formulário público de captação
export function FormularioPublico() {
  const { slug = '' } = useParams();
  const inicio = useRef(Date.now());
  const f = useCarregar(async () => { await publico.iniciar(); return publico.formulario(slug); }, [slug]);
  const acao = useAcao();
  const [dados, setDados] = useState({ nome: '', email: '', telefone: '', curso_id: '', aceite: false, site: '' });
  const [fim, setFim] = useState<{ mensagem: string; portal?: string } | null>(null);
  const d: TForm | null = f.dados;
  if (f.erro) return <Moldura><p role="alert" className="text-erro">{f.erro.message}</p></Moldura>;
  if (!d) return <Moldura><p className="flex items-center gap-2 text-suave"><Loader2 className="h-4 w-4 animate-spin" aria-hidden />Carregando…</p></Moldura>;
  if (fim) {
    const link = fim.portal ? `${location.origin}/portal#${fim.portal}` : null;
    return (
      <Moldura instituicao={d.instituicao}>
        <div className="rounded-xl border border-linha bg-white p-5" role="status">
          <p className="flex items-center gap-2 text-lg font-semibold text-ok"><CheckCircle2 className="h-5 w-5" aria-hidden />{fim.mensagem}</p>
          {link && (<>
            <p className="mt-3 text-sm">Guarde este link pessoal para acompanhar sua inscrição, enviar documentos e cuidar dos seus dados. Ele não será enviado por e-mail.</p>
            <p className="mt-2 break-all rounded-lg bg-fundo p-2 text-xs"><a className="text-tec underline" href={link}>{link}</a></p>
            <button className="btn btn-sec btn-peq mt-2" onClick={() => void navigator.clipboard?.writeText(link)}>Copiar link</button>
          </>)}
        </div>
      </Moldura>
    );
  }
  return (
    <Moldura instituicao={d.instituicao}>
      <h1 className="text-2xl font-semibold text-marinho">{d.titulo}</h1>
      {d.descricao && <p className="mt-1 text-suave">{d.descricao}</p>}
      <form className="mt-4 space-y-3 rounded-xl border border-linha bg-white p-5" onSubmit={(e) => { e.preventDefault(); void acao.executar(async () => {
        const r = await publico.inscrever(slug, { ...dados, curso_id: Number(dados.curso_id), versao_consentimento: d.versao_consentimento, tempo_ms: Date.now() - inicio.current });
        setFim({ mensagem: r.mensagem, portal: r.portal }); }); }}>
        <Campo rotulo="Nome completo"><input className="campo" required minLength={3} maxLength={120} autoComplete="name" value={dados.nome} onChange={(e) => setDados({ ...dados, nome: e.target.value })} /></Campo>
        <Campo rotulo="E-mail"><input className="campo" type="email" required autoComplete="email" value={dados.email} onChange={(e) => setDados({ ...dados, email: e.target.value })} /></Campo>
        {d.pede_telefone && <Campo rotulo="Celular (opcional)"><input className="campo" inputMode="tel" autoComplete="tel" value={dados.telefone} onChange={(e) => setDados({ ...dados, telefone: e.target.value })} /></Campo>}
        <Campo rotulo="Curso de interesse"><select className="campo" required value={dados.curso_id} onChange={(e) => setDados({ ...dados, curso_id: e.target.value })}>
          <option value="">Selecione…</option>{d.cursos.map((c) => <option key={c.id} value={c.id}>{c.nome} · {rotulo(c.turno)} · {rotulo(c.modalidade)} · {c.campus}</option>)}</select></Campo>
        {/* Campo-isca: invisível para pessoas; robôs costumam preencher. */}
        <div aria-hidden="true" style={{ position: 'absolute', left: '-10000px', width: 1, height: 1, overflow: 'hidden' }}>
          <label>Site<input tabIndex={-1} autoComplete="off" value={dados.site} onChange={(e) => setDados({ ...dados, site: e.target.value })} /></label></div>
        <fieldset className="rounded-lg bg-fundo p-3 text-sm"><legend className="flex items-center gap-1 font-semibold"><ShieldCheck className="h-4 w-4 text-tec" aria-hidden />Consentimento (versão {d.versao_consentimento})</legend>
          <p className="whitespace-pre-line">{d.texto_consentimento}</p>
          <label className="mt-2 flex items-start gap-2"><input type="checkbox" required checked={dados.aceite} onChange={(e) => setDados({ ...dados, aceite: e.target.checked })} />Li e aceito o termo acima.</label></fieldset>
        <Mensagem m={acao.mensagem} />
        <button className="btn w-full sm:w-auto" disabled={acao.enviando}>Enviar inscrição</button>
      </form>
    </Moldura>
  );
}

// ---------------------------------------------------------------- portal do candidato (token no fragmento da URL, nunca enviado ao servidor web)
export function Portal() {
  const token = typeof location !== 'undefined' ? location.hash.replace(/^#/, '') : '';
  const [recarga, setRecarga] = useState(0);
  const p = useCarregar(async () => { await publico.iniciar(); return publico.portal(token); }, [token, recarga]);
  const acao = useAcao();
  const fazer = (fn: () => Promise<string>) => acao.executar(async () => { const t = await fn(); setRecarga((n) => n + 1); return t; });
  useEffect(() => { document.title = 'Minha inscrição · Matrícula 360°'; }, []);
  if (!token) return <Moldura><p>Abra o link pessoal recebido ao concluir a inscrição ou enviado pela equipe da instituição.</p></Moldura>;
  if (p.erro) return <Moldura><p role="alert" className="text-erro">{p.erro.message}</p></Moldura>;
  const d: PortalDados | null = p.dados;
  if (!d) return <Moldura><p className="flex items-center gap-2 text-suave"><Loader2 className="h-4 w-4 animate-spin" aria-hidden />Carregando…</p></Moldura>;
  return (
    <Moldura instituicao={d.instituicao}>
      <h1 className="text-2xl font-semibold text-marinho">Olá, {d.nome.split(' ')[0]}</h1>
      <Mensagem m={acao.mensagem} />
      <Secao titulo="Minhas inscrições">
        {d.inscricoes.map((i) => (
          <div key={i.id} className="mb-2 rounded-lg border border-linha p-3 text-sm">
            <p className="font-semibold">{i.curso} · {rotulo(i.turno)} · {rotulo(i.modalidade)} · {i.coorte}</p>
            <p><Chip tipo={i.etapa === 'confirmado' ? 'ok' : ['perdido', 'cancelado'].includes(i.etapa) ? undefined : 'tec'}>{i.situacao}</Chip></p>
            {i.validacoes && <p className="mt-1 text-xs">Validações: {Object.entries(i.validacoes).map(([k, v]) => `${rotulo(k)} ${v ? '✓' : 'pendente'}`).join(' · ')}</p>}
            {i.proposta && <p className="mt-1 text-xs">Proposta: {moeda(i.proposta.valor_final_centavos)}/mês · {rotulo(i.proposta.status)} · válida até {new Date(i.proposta.validade).toLocaleDateString('pt-BR')}</p>}
          </div>))}
      </Secao>
      <PortalDocumentos token={token} fazer={fazer} enviando={acao.enviando} recarga={recarga} />
      <PortalSeletivo token={token} fazer={fazer} enviando={acao.enviando} recarga={recarga} />
      <PortalMatricula token={token} nome={d.nome} fazer={fazer} enviando={acao.enviando} recarga={recarga} />
      <Secao titulo="Meus dados e privacidade (LGPD)">
        <p className="text-sm">E-mail: {d.email ?? '—'} · Celular: {d.telefone ?? '—'} · Base legal: {rotulo(d.consentimento.base_legal)}{d.consentimento.versao ? ` · termo v${d.consentimento.versao}` : ''}</p>
        <div className="mt-2 flex flex-wrap gap-2">{(['email', 'whatsapp', 'telefone'] as const).map((c) => d.optout[c]
          ? <Chip key={c}>{rotulo(c)}: sem contato</Chip>
          : <button key={c} className="btn btn-sec btn-peq" disabled={acao.enviando} onClick={() => { if (window.confirm(`Não receber mais contato por ${rotulo(c)}?`)) void fazer(async () => { await publico.optout(token, c); return `Pronto: sem contato por ${rotulo(c)}.`; }); }}>
              Não quero contato por {rotulo(c)}</button>)}</div>
        <div className="mt-3 flex flex-wrap gap-2">{['acesso', 'correcao', 'eliminacao'].map((t) => (
          <button key={t} className="btn btn-fantasma btn-peq" disabled={acao.enviando} onClick={() => { const det = window.prompt(`Detalhe a solicitação de ${rotulo(t).toLowerCase()} (opcional):`) ?? undefined;
            void fazer(async () => { await publico.solicitar(token, t, det); return 'Solicitação registrada; a instituição responderá por aqui.'; }); }}>Solicitar {rotulo(t).toLowerCase()}</button>))}</div>
        {d.solicitacoes.length > 0 && <ul className="mt-2 text-xs">{d.solicitacoes.map((s, i) => <li key={i}>{rotulo(s.tipo)} · {rotulo(s.status)}{s.resposta ? ` — ${s.resposta}` : ''}</li>)}</ul>}
      </Secao>
    </Moldura>
  );
}

function Secao({ titulo, children }: { titulo: string; children: ReactNode }) {
  return <section className="mt-5 rounded-xl border border-linha bg-white p-4"><h2 className="mb-2 font-semibold text-marinho">{titulo}</h2>{children}</section>;
}
type Fazer = (fn: () => Promise<string>) => Promise<void>;

function PortalDocumentos({ token, fazer, enviando, recarga }: { token: string; fazer: Fazer; enviando: boolean; recarga: number }) {
  const docs = useCarregar(() => publico.documentos(token), [token, recarga]);
  if (!docs.dados?.length) return null;
  return (
    <Secao titulo="Documentos">
      {docs.dados.map((x) => (
        <div key={x.oportunidade_id} className="mb-3">
          <p className="text-sm font-medium">{x.curso} · {x.coorte}</p>
          <ul className="mt-1 space-y-1 text-sm">{x.checklist.map((i) => (
            <li key={i.tipo} className="flex flex-wrap items-center gap-2">
              <span>{i.descricao}{i.obrigatorio ? '' : ' (opcional)'}</span>
              {i.documento ? <Chip tipo={i.documento.status === 'aprovado' ? 'ok' : i.documento.status === 'recusado' ? 'erro' : 'pend'}>{rotulo(i.documento.status)}</Chip> : <Chip>não enviado</Chip>}
              {i.documento?.motivo_recusa && <span className="text-xs text-erro">{i.documento.motivo_recusa}</span>}
              {i.documento?.status !== 'aprovado' && (
                <label className="btn btn-sec btn-peq cursor-pointer"><FileUp className="h-3.5 w-3.5" aria-hidden />Enviar
                  <input type="file" className="sr-only" accept="application/pdf,image/jpeg,image/png" disabled={enviando} onChange={(e) => {
                    const arq = e.target.files?.[0]; if (!arq) return;
                    void fazer(async () => { await publico.enviarDocumento(token, x.oportunidade_id, i.tipo, arq.name, await lerBase64(arq)); return 'Documento enviado para análise.'; });
                  }} /></label>)}
            </li>))}</ul>
        </div>))}
      <p className="nota">PDF, JPG ou PNG, até 3 MB.</p>
    </Secao>
  );
}

function PortalSeletivo({ token, fazer, enviando, recarga }: { token: string; fazer: Fazer; enviando: boolean; recarga: number }) {
  const s = useCarregar(() => publico.seletivo(token), [token, recarga]);
  const insc = useCarregar(() => publico.portal(token), [token, recarga]);
  const [escolha, setEscolha] = useState<Record<number, { agenda: string; enem: string; op: string }>>({});
  const [redacao, setRedacao] = useState('');
  const d = s.dados;
  if (!d || (!d.processos_abertos.length && !d.candidaturas.length && !d.eventos.length)) return null;
  const abertas = (insc.dados?.inscricoes ?? []).filter((i) => !['perdido', 'cancelado', 'confirmado'].includes(i.etapa));
  return (
    <Secao titulo="Processo seletivo e eventos">
      {d.candidaturas.map((c) => (
        <div key={c.id} className="mb-2 rounded-lg bg-fundo p-3 text-sm">
          <p className="font-medium">{c.processo} · {c.curso}</p>
          {c.agenda && <p>Prova: {new Date(c.agenda.inicio).toLocaleString('pt-BR')} · {c.agenda.local}</p>}
          <p>{c.resultado_divulgado ? <Chip tipo={c.resultado === 'aprovado' ? 'ok' : undefined}>Resultado: {rotulo(c.resultado ?? '')}</Chip> : <Chip tipo="tec">Resultado ainda não divulgado</Chip>}</p>
          {c.tema_redacao && !c.redacao_enviada && (
            <div className="mt-2"><p className="font-semibold">Tema: {c.tema_redacao}</p>
              <textarea className="campo mt-1 min-h-[200px] w-full" aria-label="Redação" value={redacao} onChange={(e) => setRedacao(e.target.value)} />
              <p className="nota">{redacao.trim().length} caracteres (mínimo 200). Envio único.</p>
              <button className="btn btn-peq mt-1" disabled={enviando} onClick={() => { if (window.confirm('Enviar a redação? Não será possível alterar depois.')) void fazer(async () => { await publico.enviarRedacao(token, c.id, redacao); setRedacao(''); return 'Redação enviada.'; }); }}>Enviar redação</button></div>)}
          {c.redacao_enviada && <p className="text-xs text-ok">Redação enviada.</p>}
        </div>))}
      {d.processos_abertos.map((pr) => {
        const e = escolha[pr.id] ?? { agenda: '', enem: '', op: String(abertas[0]?.id ?? '') };
        return (
          <div key={pr.id} className="mb-2 rounded-lg border border-linha p-3 text-sm">
            <p className="font-medium">{pr.nome} · {rotulo(pr.tipo)} · inscrições até {new Date(`${pr.inscricoes_ate}T12:00:00`).toLocaleDateString('pt-BR')}</p>
            {pr.instrucoes && <p className="text-xs">{pr.instrucoes}</p>}
            <div className="mt-1 flex flex-wrap items-end gap-2">
              {abertas.length > 1 && <Campo rotulo="Inscrição"><select className="campo" value={e.op} onChange={(x) => setEscolha({ ...escolha, [pr.id]: { ...e, op: x.target.value } })}>
                {abertas.map((a) => <option key={a.id} value={a.id}>{a.curso}</option>)}</select></Campo>}
              {pr.tipo === 'prova_agendada' && <Campo rotulo="Data da prova"><select className="campo" value={e.agenda} onChange={(x) => setEscolha({ ...escolha, [pr.id]: { ...e, agenda: x.target.value } })}>
                <option value="">Selecione…</option>{pr.agendas.filter((a) => a.vagas_restantes > 0).map((a) => <option key={a.id} value={a.id}>{new Date(a.inicio).toLocaleString('pt-BR')} · {a.local}</option>)}</select></Campo>}
              {pr.tipo === 'enem' && <Campo rotulo="Nota do ENEM"><input className="campo w-28" inputMode="decimal" value={e.enem} onChange={(x) => setEscolha({ ...escolha, [pr.id]: { ...e, enem: x.target.value } })} /></Campo>}
              <button className="btn btn-peq" disabled={enviando || !e.op} onClick={() => void fazer(async () => {
                await publico.candidatar(token, pr.id, Number(e.op), e.agenda ? Number(e.agenda) : undefined, e.enem ? Number(e.enem.replace(',', '.')) : undefined); return 'Inscrição no processo seletivo realizada.'; })}>Inscrever-me</button>
            </div>
            {pr.tipo === 'enem' && <p className="nota">A nota declarada será conferida pela instituição no boletim oficial.</p>}
          </div>);
      })}
      {d.eventos.length > 0 && <ul className="mt-2 text-sm">{d.eventos.map((ev, i) => <li key={i}>{ev.titulo} · {rotulo(ev.tipo)} · {new Date(ev.inicio).toLocaleString('pt-BR')}{ev.local ? ` · ${ev.local}` : ''} <Chip>{rotulo(ev.status)}</Chip></li>)}</ul>}
    </Secao>
  );
}

function PortalMatricula({ token, nome, fazer, enviando, recarga }: { token: string; nome: string; fazer: Fazer; enviando: boolean; recarga: number }) {
  const m = useCarregar(() => publico.matricula(token), [token, recarga]);
  if (!m.dados?.length) return null;
  return (
    <Secao titulo="Matrícula online">
      {m.dados.map((x) => <MatriculaItem key={x.oportunidade_id} x={x} token={token} nome={nome} fazer={fazer} enviando={enviando} />)}
    </Secao>
  );
}

const VAZIO_REP = { nome: '', cpf: '', nascimento: '', vinculo: '', declaro: false };
function idadeEm(nasc: string): number | null {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(nasc)) return null;
  const n = new Date(`${nasc}T12:00:00`); const h = new Date();
  let i = h.getFullYear() - n.getFullYear();
  if (h.getMonth() < n.getMonth() || (h.getMonth() === n.getMonth() && h.getDate() < n.getDate())) i--;
  return i;
}
const soDigitos = (v: string) => v.replace(/\D/g, '').slice(0, 11);

function MatriculaItem({ x, token, nome, fazer, enviando }: { x: PortalMatricula; token: string; nome: string; fazer: Fazer; enviando: boolean }) {
  const [f, setF] = useState({ li: false, concordo: false, ciente: false, nome: '', cpf: '', nascimento: '', codigo: '' });
  const [rep, setRep] = useState(VAZIO_REP);
  const [codigo, setCodigo] = useState<CodigoAceite | null>(null);
  const idade = idadeEm(f.nascimento);
  const menor = idade !== null && idade < 18;
  const prazo = x.prazo_arrependimento_dias ?? 7;
  const baixar = () => void fazer(async () => { const c = await publico.comprovante(token, x.oportunidade_id); baixarTexto(nomeComprovante(c), 'text/html', comprovanteHtml(c)); return 'Comprovante baixado. Guarde o arquivo.'; });

  if (x.aceite) return (
    <div className="text-sm">
      <p className="font-medium">{x.curso} · {x.coorte}</p>
      {x.aceite.desistencia_em
        ? <p className="text-suave">Desistência registrada em {new Date(x.aceite.desistencia_em).toLocaleString('pt-BR')}. A matrícula foi cancelada.</p>
        : <p className="text-ok">Matrícula aceita em {new Date(x.aceite.aceito_em).toLocaleString('pt-BR')} (contrato v{x.aceite.contrato_versao}). Próximo passo: validações pela instituição.</p>}
      <div className="mt-2 flex flex-wrap gap-2">
        {x.procedimento && <button className="btn btn-sec btn-peq" disabled={enviando} onClick={baixar}><Download className="h-3.5 w-3.5" aria-hidden />Baixar comprovante e contrato</button>}
        {x.aceite.pode_desistir && <button className="btn btn-fantasma btn-peq" disabled={enviando} onClick={() => {
          const motivo = window.prompt(`Desistir da matrícula? Você pode desistir em até ${prazo} dias após o aceite, sem precisar justificar. Se quiser, conte o motivo (opcional):`);
          if (motivo === null) return;
          void fazer(async () => (await publico.desistir(token, x.oportunidade_id, motivo || undefined)).mensagem); }}>Desistir da matrícula</button>}
      </div>
      {x.aceite.pode_desistir && x.aceite.arrependimento_ate && <p className="nota mt-1">Prazo para desistir pelo portal: até {new Date(x.aceite.arrependimento_ate).toLocaleString('pt-BR')}.</p>}
      <p className="nota mt-1">{x.pagamento}</p>
    </div>);

  if (!(x.etapa === 'pre_matricula' && x.proposta?.status === 'aprovada' && x.contrato)) return (
    <p className="text-sm text-suave">{x.curso}: a matrícula online fica disponível com a proposta aprovada, na etapa de pré-matrícula.</p>);
  if (!x.procedimento) return <p className="text-sm text-suave">{x.curso}: matrícula online em atualização. Tente novamente mais tarde.</p>;

  const p = x.proposta; const k = x.contrato;
  const pronto = f.li && f.concordo && f.ciente && f.nome.trim() && soDigitos(f.cpf).length === 11 && idade !== null && /^\d{6}$/.test(f.codigo)
    && (!menor || (rep.nome.trim() && soDigitos(rep.cpf).length === 11 && rep.nascimento && rep.vinculo && rep.declaro));
  return (
    <div className="space-y-3 text-sm">
      <p className="font-medium">{x.curso} · {x.coorte}</p>
      <div className="rounded-lg border border-linha p-3">
        <p className="font-semibold">Condições da proposta</p>
        <p>Mensalidade {moeda(p.mensalidade_centavos)}, desconto {p.desconto_pct}% → <strong>{moeda(p.valor_final_centavos)}/mês</strong>. Válida até {new Date(p.validade).toLocaleString('pt-BR')}.</p>
      </div>
      <div>
        <p className="font-semibold">Contrato de prestação de serviços educacionais (versão {k.versao})</p>
        <p className="nota">As cláusulas que limitam direitos aparecem em destaque.</p>
        <TextoContrato texto={k.texto} className="mt-1 max-h-96 overflow-y-auto rounded-lg border border-linha bg-fundo p-3" />
      </div>
      <fieldset className="space-y-1 rounded-lg bg-fundo p-3"><legend className="font-semibold">Declarações</legend>
        <label className="flex items-start gap-2"><input type="checkbox" checked={f.li} onChange={(e) => setF({ ...f, li: e.target.checked })} />Li o contrato (versão {k.versao}).</label>
        <label className="flex items-start gap-2"><input type="checkbox" checked={f.concordo} onChange={(e) => setF({ ...f, concordo: e.target.checked })} />Concordo com as condições da proposta: {moeda(p.valor_final_centavos)}/mês.</label>
        <label className="flex items-start gap-2"><input type="checkbox" checked={f.ciente} onChange={(e) => setF({ ...f, ciente: e.target.checked })} />Estou ciente de que posso desistir pelo portal em até {prazo} dias após o aceite.</label>
      </fieldset>
      <fieldset className="grid gap-2 rounded-lg bg-fundo p-3 sm:grid-cols-3"><legend className="font-semibold">Identificação do candidato</legend>
        <Campo rotulo={`Nome completo (${nome})`} className="sm:col-span-3"><input className="campo" autoComplete="name" value={f.nome} onChange={(e) => setF({ ...f, nome: e.target.value })} /></Campo>
        <Campo rotulo="CPF"><input className="campo" inputMode="numeric" autoComplete="off" placeholder="000.000.000-00" value={f.cpf} onChange={(e) => setF({ ...f, cpf: e.target.value })} /></Campo>
        <Campo rotulo="Data de nascimento"><input className="campo" type="date" value={f.nascimento} onChange={(e) => setF({ ...f, nascimento: e.target.value })} /></Campo>
      </fieldset>
      {menor && (
        <fieldset className="grid gap-2 rounded-lg border border-alerta/40 bg-amber-50 p-3 sm:grid-cols-3"><legend className="font-semibold">Representante legal (candidato menor de 18 anos)</legend>
          <p className="sm:col-span-3">O aceite de quem tem menos de 18 anos precisa do pai, da mãe ou do tutor legal, que aceita junto com o candidato.</p>
          <Campo rotulo="Nome completo do representante" className="sm:col-span-3"><input className="campo" value={rep.nome} onChange={(e) => setRep({ ...rep, nome: e.target.value })} /></Campo>
          <Campo rotulo="CPF do representante"><input className="campo" inputMode="numeric" placeholder="000.000.000-00" value={rep.cpf} onChange={(e) => setRep({ ...rep, cpf: e.target.value })} /></Campo>
          <Campo rotulo="Nascimento do representante"><input className="campo" type="date" value={rep.nascimento} onChange={(e) => setRep({ ...rep, nascimento: e.target.value })} /></Campo>
          <Campo rotulo="Vínculo"><select className="campo" value={rep.vinculo} onChange={(e) => setRep({ ...rep, vinculo: e.target.value })}>
            <option value="">Selecione…</option><option value="mae">Mãe</option><option value="pai">Pai</option><option value="tutor">Tutor(a) legal</option></select></Campo>
          <label className="flex items-start gap-2 sm:col-span-3"><input type="checkbox" checked={rep.declaro} onChange={(e) => setRep({ ...rep, declaro: e.target.checked })} />
            Declaro que sou representante legal do candidato e que o represento ou assisto neste aceite.</label>
        </fieldset>)}
      <fieldset className="rounded-lg bg-fundo p-3"><legend className="font-semibold">Confirmação</legend>
        <p>Enviaremos um código de 6 dígitos para {x.confirmacao?.destino ?? 'o contato do cadastro'}.</p>
        <div className="mt-2 flex flex-wrap items-end gap-2">
          <button type="button" className="btn btn-sec btn-peq" disabled={enviando} onClick={() => void fazer(async () => {
            const r = await publico.codigoAceite(token, x.oportunidade_id); setCodigo(r); return `Código gerado; vale por 15 minutos.`; })}>{codigo ? 'Pedir novo código' : 'Receber código'}</button>
          <Campo rotulo="Código"><input className="campo w-28" inputMode="numeric" maxLength={6} autoComplete="one-time-code" value={f.codigo} onChange={(e) => setF({ ...f, codigo: e.target.value.replace(/\D/g, '') })} /></Campo>
        </div>
        {codigo?.codigo_simulacao && <p className="mt-2 rounded bg-amber-50 p-2 text-xs text-alerta" role="status">{codigo.aviso} Código: <strong className="font-mono text-sm">{codigo.codigo_simulacao}</strong></p>}
      </fieldset>
      <button className="btn" disabled={enviando || !pronto} onClick={() => void fazer(async () => {
        const r = await publico.aceitar(token, x.oportunidade_id, { contrato_versao: k.versao, proposta_id: p.id, li_contrato: f.li, concordo_condicoes: f.concordo, ciente_arrependimento: f.ciente,
          nome: f.nome, cpf: soDigitos(f.cpf), nascimento: f.nascimento, codigo: f.codigo,
          ...(menor ? { responsavel: { nome: rep.nome, cpf: soDigitos(rep.cpf), nascimento: rep.nascimento, vinculo: rep.vinculo, declaro: rep.declaro } } : {}) });
        if (!r.aceito) throw new Error(`${r.erro ?? 'Não foi possível aceitar'}. Tentativas restantes: ${r.tentativas_restantes ?? 0}.`);
        return `Matrícula aceita. ${r.proximo_passo ?? ''} Baixe o comprovante abaixo.`; })}>Aceitar matrícula</button>
      <p className="nota">{x.pagamento}</p>
    </div>
  );
}
