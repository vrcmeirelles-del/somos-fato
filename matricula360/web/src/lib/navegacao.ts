// Mapa dos dez ambientes. Itens "planejado" aparecem desabilitados com a fase prevista:
// não há página de lista fingindo módulo pronto (critério de aceite da Fase 2).
import {
  Activity, BarChart3, CalendarClock, CalendarDays, ClipboardList, FileCheck2, Gauge, MessagesSquare, PlugZap, BookOpen, Building2, ClipboardCheck, FileText, GraduationCap, HandCoins, HeartHandshake, KanbanSquare, KeyRound,
  LayoutDashboard, LifeBuoy, Megaphone, RefreshCcw, RotateCw, ScrollText, Settings, ShieldCheck, Target, Users, Workflow, type LucideIcon,
} from 'lucide-react';
import type { Papel } from './tipos';

export interface ItemNav { rotulo: string; rota?: (ies: number) => string; icone: LucideIcon; fase?: 'P1' | 'P2' | 'P3'; papeis?: Papel[]; master?: boolean }
export interface Ambiente { id: string; rotulo: string; icone: LucideIcon; itens: ItemNav[] }

const OPERACAO: Papel[] = ['gestor', 'comercial', 'secretaria', 'financeiro'];
export const AMBIENTES: Ambiente[] = [
  { id: 'inteligencia', rotulo: 'Central de Inteligência', icone: LayoutDashboard, itens: [
    { rotulo: 'Painel executivo', rota: (i) => `/ies/${i}/inteligencia`, icone: BarChart3 },
    { rotulo: 'Performance e gargalos (MAIM)', rota: (i) => `/ies/${i}/performance`, icone: Gauge, papeis: ['gestor', 'reitoria', 'coordenador', 'comercial'] },
    { rotulo: 'Fila de intervenções (MAIM)', rota: (i) => `/ies/${i}/intervencoes`, icone: Activity, papeis: OPERACAO },
  ] },
  { id: 'planejamento', rotulo: 'Planejamento Estratégico', icone: Target, itens: [
    { rotulo: 'Plano, objetivos e 5W2H', rota: (i) => `/ies/${i}/planejamento`, icone: Target, papeis: ['gestor', 'reitoria', 'coordenador'] },
  ] },
  { id: 'marketing', rotulo: 'Marketing e Captação', icone: Megaphone, itens: [
    { rotulo: 'Formulários de captação', rota: (i) => `/ies/${i}/formularios`, icone: ClipboardList, papeis: ['gestor'] },
    { rotulo: 'Eventos e visitas', rota: (i) => `/ies/${i}/eventos`, icone: CalendarDays, papeis: ['gestor', 'comercial', 'secretaria'] },
    { rotulo: 'Comunicação e réguas', rota: (i) => `/ies/${i}/comunicacao`, icone: MessagesSquare, papeis: ['gestor', 'comercial'] },
    { rotulo: 'Campanhas e custos', rota: (i) => `/ies/${i}/campanhas`, icone: Megaphone, papeis: ['gestor', 'reitoria', 'coordenador', 'comercial', 'financeiro'] },
  ] },
  { id: 'crm', rotulo: 'CRM Educacional', icone: Users, itens: [
    { rotulo: 'Pipeline (CRM)', rota: (i) => `/ies/${i}/crm`, icone: KanbanSquare },
    { rotulo: 'Agenda comercial', rota: (i) => `/ies/${i}/agenda`, icone: CalendarClock, papeis: ['gestor', 'comercial'] },
  ] },
  { id: 'funis', rotulo: 'Funis Comerciais', icone: Workflow, itens: [
    { rotulo: 'Funis configuráveis', rota: (i) => `/ies/${i}/funis`, icone: Workflow, papeis: ['gestor', 'reitoria', 'coordenador', 'comercial'] },
  ] },
  { id: 'conversao', rotulo: 'Conversão e Matrículas', icone: ClipboardCheck, itens: [
    { rotulo: 'Processo seletivo', rota: (i) => `/ies/${i}/seletivo`, icone: FileCheck2, papeis: ['gestor', 'secretaria', 'coordenador', 'comercial'] },
    { rotulo: 'Matrículas', rota: (i) => `/ies/${i}/matriculas`, icone: ClipboardCheck },
    { rotulo: 'Propostas', rota: (i) => `/ies/${i}/propostas`, icone: FileText, papeis: ['gestor', 'comercial'] },
    { rotulo: 'Bolsas e financiamento', rota: (i) => `/ies/${i}/bolsas`, icone: HandCoins, papeis: ['gestor', 'financeiro', 'comercial', 'secretaria', 'coordenador', 'reitoria'] },
  ] },
  { id: 'recuperacao', rotulo: 'Recuperação e Aceleração', icone: RefreshCcw, itens: [
    { rotulo: 'Protocolos, reativação e sprints', rota: (i) => `/ies/${i}/recuperacao`, icone: RefreshCcw, papeis: ['gestor', 'reitoria', 'coordenador', 'comercial'] },
  ] },
  { id: 'academia', rotulo: 'Academia de Captação', icone: GraduationCap, itens: [
    { rotulo: 'Trilhas, rubricas e PDI', rota: (i) => `/ies/${i}/academia`, icone: BookOpen, papeis: ['gestor', 'reitoria', 'comercial'] },
  ] },
  { id: 'relacionamento', rotulo: 'Relacionamento Estudantil', icone: HeartHandshake, itens: [
    { rotulo: 'Permanência, indicações e embaixadores', rota: (i) => `/ies/${i}/relacionamento`, icone: HeartHandshake, papeis: ['gestor', 'reitoria', 'coordenador', 'secretaria'] },
    { rotulo: 'Sucesso do aluno', rota: (i) => `/ies/${i}/sucesso`, icone: LifeBuoy, papeis: ['gestor', 'secretaria', 'coordenador', 'financeiro', 'reitoria'] },
    { rotulo: 'Rematrícula', rota: (i) => `/ies/${i}/rematricula`, icone: RotateCw, papeis: ['gestor', 'secretaria', 'financeiro', 'coordenador', 'reitoria'] },
  ] },
  { id: 'governanca', rotulo: 'Governança Institucional', icone: ShieldCheck, itens: [
    { rotulo: 'Configurações e metas', rota: (i) => `/ies/${i}/configuracoes`, icone: Settings, papeis: ['gestor'] },
    { rotulo: 'Perfis e permissões', rota: (i) => `/ies/${i}/permissoes`, icone: KeyRound },
    { rotulo: 'Integrações e dados', rota: (i) => `/ies/${i}/integracoes`, icone: PlugZap, papeis: ['gestor', 'secretaria', 'financeiro'] },
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
