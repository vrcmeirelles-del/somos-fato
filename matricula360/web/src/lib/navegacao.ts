// Mapa dos dez ambientes. Itens "planejado" aparecem desabilitados com a fase prevista:
// não há página de lista fingindo módulo pronto (critério de aceite da Fase 2).
import {
  Activity, BarChart3, CalendarClock, BookOpen, Building2, ClipboardCheck, FileText, GraduationCap, HeartHandshake, KanbanSquare,
  LayoutDashboard, Megaphone, RefreshCcw, ScrollText, Settings, ShieldCheck, Target, Users, Workflow, type LucideIcon,
} from 'lucide-react';
import type { Papel } from './tipos';

export interface ItemNav { rotulo: string; rota?: (ies: number) => string; icone: LucideIcon; fase?: 'P1' | 'P2' | 'P3'; papeis?: Papel[]; master?: boolean }
export interface Ambiente { id: string; rotulo: string; icone: LucideIcon; itens: ItemNav[] }

const OPERACAO: Papel[] = ['gestor', 'comercial', 'secretaria', 'financeiro'];
export const AMBIENTES: Ambiente[] = [
  { id: 'inteligencia', rotulo: 'Central de Inteligência', icone: LayoutDashboard, itens: [
    { rotulo: 'Painel executivo', rota: (i) => `/ies/${i}/inteligencia`, icone: BarChart3 },
    { rotulo: 'Fila de intervenções (MAIM)', rota: (i) => `/ies/${i}/intervencoes`, icone: Activity, papeis: OPERACAO },
  ] },
  { id: 'planejamento', rotulo: 'Planejamento Estratégico', icone: Target, itens: [
    { rotulo: 'Objetivos, metas e orçamento', icone: Target, fase: 'P1' },
  ] },
  { id: 'marketing', rotulo: 'Marketing e Captação', icone: Megaphone, itens: [
    { rotulo: 'Campanhas e canais', icone: Megaphone, fase: 'P1' },
  ] },
  { id: 'crm', rotulo: 'CRM Educacional', icone: Users, itens: [
    { rotulo: 'Pipeline (CRM)', rota: (i) => `/ies/${i}/crm`, icone: KanbanSquare },
    { rotulo: 'Agenda comercial', rota: (i) => `/ies/${i}/agenda`, icone: CalendarClock, papeis: ['gestor', 'comercial'] },
  ] },
  { id: 'funis', rotulo: 'Funis Comerciais', icone: Workflow, itens: [
    { rotulo: 'Funis configuráveis', icone: Workflow, fase: 'P1' },
  ] },
  { id: 'conversao', rotulo: 'Conversão e Matrículas', icone: ClipboardCheck, itens: [
    { rotulo: 'Matrículas', rota: (i) => `/ies/${i}/matriculas`, icone: ClipboardCheck },
    { rotulo: 'Propostas e bolsas', rota: (i) => `/ies/${i}/propostas`, icone: FileText, papeis: ['gestor', 'comercial'] },
  ] },
  { id: 'recuperacao', rotulo: 'Recuperação e Aceleração', icone: RefreshCcw, itens: [
    { rotulo: 'Sales Farming e reativação', icone: RefreshCcw, fase: 'P2' },
  ] },
  { id: 'academia', rotulo: 'Academia de Captação', icone: GraduationCap, itens: [
    { rotulo: 'Trilhas, rubricas e PDI', icone: BookOpen, fase: 'P2' },
  ] },
  { id: 'relacionamento', rotulo: 'Relacionamento Estudantil', icone: HeartHandshake, itens: [
    { rotulo: 'Permanência e rematrícula', icone: HeartHandshake, fase: 'P3' },
  ] },
  { id: 'governanca', rotulo: 'Governança Institucional', icone: ShieldCheck, itens: [
    { rotulo: 'Configurações e metas', rota: (i) => `/ies/${i}/configuracoes`, icone: Settings, papeis: ['gestor'] },
    { rotulo: 'Auditoria', rota: (i) => `/ies/${i}/auditoria`, icone: ScrollText, papeis: ['gestor'] },
    { rotulo: 'Painel Master', rota: () => '/master', icone: Building2, master: true },
  ] },
];

// Breadcrumb a partir da rota atual.
export function trilha(caminho: string): string[] {
  for (const a of AMBIENTES) for (const i of a.itens) {
    if (!i.rota) continue;
    const modelo = i.rota(0).replace('/ies/0/', '/ies/');
    const alvo = caminho.replace(/^\/ies\/\d+\//, '/ies/');
    if (alvo === modelo) return [a.rotulo, i.rotulo];
  }
  return [];
}
