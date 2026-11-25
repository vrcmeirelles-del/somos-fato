import { useState } from 'react';
import { useSessao } from '../components/Layout';
import { Campo, Detalhes, Estado, Mensagem, Titulo } from '../components/ui';
import { api } from '../lib/api';
import { linhaImportacao, rotulo } from '../lib/formato';
import { useAcao, useCarregar } from '../lib/hooks';
import type { Etapa, ItemOportunidade, Pagina } from '../lib/tipos';

export function Crm({ abrirDetalhe, versao }: { abrirDetalhe: (id: number) => void; versao: number }) {
  const { ies, estrutura, tem } = useSessao();
  const [coorte, setCoorte] = useState('');
  const [curso, setCurso] = useState('');
  const [recarga, setRecarga] = useState(0);
  const colunas = useCarregar(async () => {
    const etapas = estrutura?.etapas ?? [];
    const r = await Promise.all(etapas.map((e) => api.oportunidades(ies!, { etapa: e, coorte: coorte || undefined, curso: curso ? Number(curso) : undefined, porPagina: 50 })));
    return etapas.map((e, i) => [e, r[i]!] as [Etapa, Pagina<ItemOportunidade>]);
  }, [ies, estrutura, coorte, curso, recarga, versao]);
  const recarregar = () => setRecarga((n) => n + 1);

  return (
    <>
      <Titulo titulo="Pipeline (CRM)" subtitulo="Oportunidades por etapa do funil. Transições validadas no servidor." />
      {tem('comercial', 'gestor') && <><NovaOportunidade aoCriar={recarregar} /><Importar aoImportar={recarregar} /></>}
      <div className="mb-4 flex flex-wrap items-end gap-3">
        <label className="text-sm">Coorte{' '}
          <select className="campo" aria-label="Coorte" value={coorte} onChange={(e) => setCoorte(e.target.value)}>
            <option value="">Todas as coortes</option>{estrutura?.coortes.map((c) => <option key={c}>{c}</option>)}
          </select>
        </label>
        <label className="text-sm">Curso{' '}
          <select className="campo" aria-label="Curso" value={curso} onChange={(e) => setCurso(e.target.value)}>
            <option value="">Todos os cursos</option>{estrutura?.cursos.map((c) => <option key={c.id} value={c.id}>{c.nome} · {c.turno}</option>)}
          </select>
        </label>
      </div>
      <Estado carregando={colunas.carregando && !colunas.dados} erro={colunas.erro} />
      <div role="list" className="grid auto-cols-[minmax(220px,1fr)] grid-flow-col gap-2.5 overflow-x-auto pb-2">
        {colunas.dados?.map(([etapa, pag]) => (
          <section key={etapa} role="listitem" aria-label={rotulo(etapa)} className="coluna min-h-[120px] rounded-xl bg-[#e8eef5] p-2.5">
            <h2 className="mb-2 flex justify-between text-sm font-semibold"><span>{rotulo(etapa)}</span><span>{pag.total}</span></h2>
            {pag.itens.map((o) => (
              <button key={o.id} className="cartao mb-2 block w-full rounded-lg border border-linha bg-white p-2 text-left text-sm" onClick={() => abrirDetalhe(o.id)}>
                <strong>{o.nome}</strong>
                <small className="block text-suave">{o.curso} · {o.turno} · {o.coorte}</small>
                <small className="block text-suave">{rotulo(o.forma_ingresso)} · {o.responsavel ?? 'sem responsável'}</small>
              </button>
            ))}
            {pag.total > pag.itens.length && <p className="nota">Exibindo {pag.itens.length} de {pag.total}. Use os filtros para refinar.</p>}
          </section>
        ))}
      </div>
    </>
  );
}

function NovaOportunidade({ aoCriar }: { aoCriar: () => void }) {
  const { ies, estrutura } = useSessao();
  const acao = useAcao();
  const vazio = { nome: '', email: '', telefone: '', curso_id: String(estrutura?.cursos[0]?.id ?? ''), forma_ingresso: 'vestibular', coorte: estrutura?.coortes[0] ?? '2027.1', base_legal: '', origem: '' };
  const [f, setF] = useState(vazio);
  const campo = (k: keyof typeof vazio) => ({ value: f[k], onChange: (e: { target: { value: string } }) => setF({ ...f, [k]: e.target.value }) });
  return (
    <Detalhes titulo="Nova oportunidade">
      <form className="flex flex-wrap items-end gap-2" onSubmit={(ev) => { ev.preventDefault(); void acao.executar(async () => {
        const dados: Record<string, unknown> = { ...f, curso_id: Number(f.curso_id) };
        if (!f.email) delete dados.email; if (!f.telefone) delete dados.telefone;
        const r = await api.criarOportunidade(ies!, dados);
        setF(vazio); aoCriar();
        return r.duplicada ? `Já existia oportunidade para esta pessoa, curso e coorte (#${r.id}). Nada foi duplicado.` : `Oportunidade #${r.id} criada e distribuída.`;
      }); }}>
        <Campo rotulo="Nome"><input className="campo" required maxLength={120} {...campo('nome')} /></Campo>
        <Campo rotulo="E-mail"><input className="campo" type="email" {...campo('email')} /></Campo>
        <Campo rotulo="Telefone"><input className="campo" inputMode="tel" {...campo('telefone')} /></Campo>
        <Campo rotulo="Curso"><select className="campo" {...campo('curso_id')}>{estrutura?.cursos.map((c) => <option key={c.id} value={c.id}>{c.nome} · {c.turno}</option>)}</select></Campo>
        <Campo rotulo="Forma de ingresso"><select className="campo" {...campo('forma_ingresso')}>{estrutura?.formas_ingresso.map((x) => <option key={x} value={x}>{rotulo(x)}</option>)}</select></Campo>
        <Campo rotulo="Coorte"><input className="campo w-24" pattern="\d{4}\.[12]" {...campo('coorte')} /></Campo>
        <Campo rotulo="Base legal (LGPD)"><select className="campo" {...campo('base_legal')}><option value="">Selecione…</option>{estrutura?.bases_legais.map((x) => <option key={x} value={x}>{rotulo(x)}</option>)}</select></Campo>
        <Campo rotulo="Origem"><input className="campo" placeholder="ex.: site, evento escolar" {...campo('origem')} /></Campo>
        <button className="btn" type="submit" disabled={acao.enviando}>Cadastrar</button>
      </form>
      <Mensagem m={acao.mensagem} />
    </Detalhes>
  );
}

function Importar({ aoImportar }: { aoImportar: () => void }) {
  const { ies, estrutura } = useSessao();
  const acao = useAcao();
  const [texto, setTexto] = useState('');
  const [rejeitadas, setRejeitadas] = useState<{ linha: number; motivo: string }[]>([]);
  return (
    <Detalhes titulo="Importar lista (deduplicada)">
      <p className="nota mb-2">Uma linha por candidato: nome;email;telefone;curso_id;forma_ingresso;coorte;base_legal;origem. Cursos: {estrutura?.cursos.map((c) => `${c.id}=${c.nome}`).join(', ')}. Linhas sem origem ou base legal são rejeitadas.</p>
      <textarea className="campo min-h-[110px] w-full" aria-label="Linhas para importar" value={texto} onChange={(e) => setTexto(e.target.value)}
        placeholder="nome;email;telefone;curso_id;forma_ingresso;coorte;base_legal;origem" />
      <button className="btn mt-2" disabled={acao.enviando} onClick={() => void acao.executar(async () => {
        const linhas = texto.split('\n').map((l) => l.trim()).filter(Boolean);
        if (!linhas.length || linhas.length > 500) throw new Error('Envie de 1 a 500 linhas');
        let criadas = 0; let duplicadas = 0; const rej: { linha: number; motivo: string }[] = [];
        for (const [i, l] of linhas.entries()) {
          try { const r = await api.criarOportunidade(ies!, linhaImportacao(l)); if (r.duplicada) duplicadas++; else criadas++; }
          catch (e) { rej.push({ linha: i + 1, motivo: (e as Error).message }); }
        }
        setRejeitadas(rej); aoImportar();
        return `Importação: ${criadas} criadas, ${duplicadas} duplicadas, ${rej.length} rejeitadas.`;
      })}>Importar</button>
      <Mensagem m={acao.mensagem} />
      {rejeitadas.length > 0 && <ul className="text-sm text-erro">{rejeitadas.map((r) => <li key={r.linha}>Linha {r.linha}: {r.motivo}</li>)}</ul>}
    </Detalhes>
  );
}
