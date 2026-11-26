import { ClipboardPaste, Download, FileSpreadsheet, Plus, Trash2 } from 'lucide-react';
import { useState } from 'react';
import { baixarTexto } from '../lib/contrato';
import { CABECALHO_MODELO, MODALIDADES, TURNOS, errosLinha, lerLinhasTexto, paraLinhas, type LinhaCurso } from '../lib/cursosPlanilha';
import { rotulo } from '../lib/formato';

const vazia = (): LinhaCurso => ({ nome: '', turno: 'noturno', modalidade: 'presencial', mensalidade: '', desconto: '30' });
const MODELO = `﻿${CABECALHO_MODELO}\r\nDireito;noturno;presencial;1290,00;30\r\nAdministração;ead;ead;399,00;40\r\nPsicologia;matutino;presencial;1190,00;25\r\n`;
const NOMES_ERRO: Record<string, string> = { nome: 'nome', turno: 'turno', modalidade: 'modalidade', mensalidade: 'mensalidade', desconto: 'desconto (0 a 100)', repetido: 'curso repetido no mesmo turno' };

// Tabela editável de cursos, com importação de planilha (.xlsx, .csv ou células coladas do Excel) e modelo para baixar.
export function TabelaCursos({ linhas, mudar }: { linhas: LinhaCurso[]; mudar: (l: LinhaCurso[]) => void }) {
  const [colar, setColar] = useState(false); const [texto, setTexto] = useState(''); const [aviso, setAviso] = useState('');
  const set = (i: number, x: Partial<LinhaCurso>) => mudar(linhas.map((l, j) => (j === i ? { ...l, ...x } : l)));
  const incluir = (novas: LinhaCurso[], origem: string) => {
    const base = linhas.filter((l) => l.nome.trim() || l.mensalidade.trim());
    mudar([...base, ...novas]); setAviso(`${novas.length} curso(s) importado(s) de ${origem}. Confira a tabela antes de provisionar.`);
  };
  async function arquivo(f: File) {
    setAviso('');
    try {
      if (/\.xlsx$/i.test(f.name)) {
        const { default: lerXlsx } = await import('read-excel-file');
        incluir(paraLinhas((await lerXlsx(f)) as (string | number | null)[][]), f.name);
      } else incluir(paraLinhas(lerLinhasTexto(await f.text())), f.name);
    } catch { setAviso('Não foi possível ler o arquivo. Use .xlsx, .csv (separado por ponto e vírgula) ou cole as células do Excel.'); }
  }
  const erros = linhas.map((l, i) => errosLinha(l, linhas, i));
  return (
    <div>
      <div className="mb-2 flex flex-wrap items-center gap-2">
        <label className="btn btn-sec btn-peq cursor-pointer"><FileSpreadsheet className="h-3.5 w-3.5" aria-hidden />Importar planilha (.xlsx ou .csv)
          <input type="file" className="sr-only" accept=".xlsx,.csv,.txt,text/csv,application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
            onChange={(e) => { const f = e.target.files?.[0]; if (f) void arquivo(f); e.target.value = ''; }} /></label>
        <button type="button" className="btn btn-sec btn-peq" onClick={() => setColar(!colar)}><ClipboardPaste className="h-3.5 w-3.5" aria-hidden />Colar do Excel</button>
        <button type="button" className="btn btn-fantasma btn-peq" onClick={() => baixarTexto('modelo-cursos.csv', 'text/csv', MODELO)}><Download className="h-3.5 w-3.5" aria-hidden />Baixar modelo</button>
      </div>
      {colar && (
        <div className="mb-2">
          <textarea className="campo min-h-[80px] w-full font-mono text-xs" aria-label="Células coladas do Excel" placeholder="Copie no Excel as colunas curso, turno, modalidade, mensalidade e desconto máximo e cole aqui"
            value={texto} onChange={(e) => setTexto(e.target.value)} />
          <button type="button" className="btn btn-peq mt-1" disabled={!texto.trim()} onClick={() => { incluir(paraLinhas(lerLinhasTexto(texto)), 'texto colado'); setTexto(''); setColar(false); }}>Incluir na tabela</button>
        </div>)}
      {aviso && <p role="status" className="mb-2 text-xs text-tec">{aviso}</p>}
      <div className="tabela" tabIndex={0} role="region" aria-label="Cursos da instituição">
        <table>
          <thead><tr><th>Curso</th><th>Turno</th><th>Modalidade</th><th>Mensalidade (R$)</th><th>Desconto máx. (%)</th><th><span className="sr-only">Ações</span></th></tr></thead>
          <tbody>{linhas.map((l, i) => {
            const er = erros[i]!; const mal = (c: string) => (er.includes(c) ? 'border-erro' : '');
            return (
              <tr key={i}>
                <td><input className={`campo min-w-[12rem] ${mal('nome')} ${mal('repetido')}`} aria-label={`Curso da linha ${i + 1}`} value={l.nome} onChange={(e) => set(i, { nome: e.target.value })} />
                  {er.length > 0 && (l.nome || l.mensalidade) && <p className="mt-0.5 text-[11px] text-erro">Corrija: {er.map((x) => NOMES_ERRO[x]).join(', ')}</p>}</td>
                <td><select className={`campo ${mal('turno')}`} aria-label={`Turno da linha ${i + 1}`} value={l.turno} onChange={(e) => set(i, { turno: e.target.value })}>
                  {!(TURNOS as readonly string[]).includes(l.turno) && <option value={l.turno}>{l.turno || 'escolher'}</option>}{TURNOS.map((t) => <option key={t} value={t}>{rotulo(t)}</option>)}</select></td>
                <td><select className={`campo ${mal('modalidade')}`} aria-label={`Modalidade da linha ${i + 1}`} value={l.modalidade} onChange={(e) => set(i, { modalidade: e.target.value })}>
                  {!(MODALIDADES as readonly string[]).includes(l.modalidade) && <option value={l.modalidade}>{l.modalidade || 'escolher'}</option>}{MODALIDADES.map((t) => <option key={t} value={t}>{rotulo(t)}</option>)}</select></td>
                <td><input className={`campo w-28 ${mal('mensalidade')}`} inputMode="decimal" placeholder="1.290,00" aria-label={`Mensalidade da linha ${i + 1}`} value={l.mensalidade} onChange={(e) => set(i, { mensalidade: e.target.value })} /></td>
                <td><input className={`campo w-20 ${mal('desconto')}`} inputMode="decimal" aria-label={`Desconto máximo da linha ${i + 1}`} value={l.desconto} onChange={(e) => set(i, { desconto: e.target.value })} /></td>
                <td><button type="button" className="btn btn-fantasma btn-peq" aria-label={`Remover linha ${i + 1}`} onClick={() => mudar(linhas.length > 1 ? linhas.filter((_, j) => j !== i) : [vazia()])}><Trash2 className="h-3.5 w-3.5" aria-hidden /></button></td>
              </tr>);
          })}</tbody>
        </table>
      </div>
      <button type="button" className="btn btn-fantasma btn-peq mt-1" onClick={() => mudar([...linhas, vazia()])}><Plus className="h-3.5 w-3.5" aria-hidden />Adicionar curso</button>
    </div>
  );
}
export const linhaVazia = vazia;
