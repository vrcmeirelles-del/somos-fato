-- Matrícula 360° — esquema do piloto local (SQLite via node:sqlite).
-- Equivalente Postgres/Supabase com RLS fica para a fase de homologação remota,
-- que depende de autorização de infraestrutura. Somente dados sintéticos.

PRAGMA foreign_keys = ON;

CREATE TABLE ies (
  id INTEGER PRIMARY KEY,
  nome TEXT NOT NULL UNIQUE CHECK (length(nome) BETWEEN 2 AND 120),
  plano TEXT NOT NULL DEFAULT 'piloto' CHECK (plano IN ('piloto','essencial','completo')),
  status TEXT NOT NULL DEFAULT 'ativa' CHECK (status IN ('ativa','suspensa')),
  sla_horas INTEGER NOT NULL DEFAULT 2 CHECK (sla_horas BETWEEN 1 AND 168),
  max_followups INTEGER NOT NULL DEFAULT 3 CHECK (max_followups BETWEEN 0 AND 10),
  dias_sem_contato INTEGER NOT NULL DEFAULT 3 CHECK (dias_sem_contato BETWEEN 1 AND 60),
  capacidade_atendente INTEGER NOT NULL DEFAULT 50 CHECK (capacidade_atendente BETWEEN 1 AND 1000),
  criado_em TEXT NOT NULL
);

CREATE TABLE campus (
  id INTEGER PRIMARY KEY,
  ies_id INTEGER NOT NULL REFERENCES ies(id),
  nome TEXT NOT NULL,
  UNIQUE (ies_id, nome)
);

CREATE TABLE cursos (
  id INTEGER PRIMARY KEY,
  ies_id INTEGER NOT NULL REFERENCES ies(id),
  campus_id INTEGER NOT NULL REFERENCES campus(id),
  nome TEXT NOT NULL,
  turno TEXT NOT NULL CHECK (turno IN ('matutino','vespertino','noturno','integral','ead')),
  modalidade TEXT NOT NULL CHECK (modalidade IN ('presencial','ead','semipresencial')),
  mensalidade_centavos INTEGER NOT NULL CHECK (mensalidade_centavos > 0),
  desconto_max_pct REAL NOT NULL DEFAULT 30 CHECK (desconto_max_pct BETWEEN 0 AND 100),
  UNIQUE (ies_id, campus_id, nome, turno)
);

CREATE TABLE usuarios (
  id INTEGER PRIMARY KEY,
  email TEXT NOT NULL UNIQUE COLLATE NOCASE,
  nome TEXT NOT NULL,
  senha_hash TEXT NOT NULL,
  master INTEGER NOT NULL DEFAULT 0 CHECK (master IN (0,1)),
  ativo INTEGER NOT NULL DEFAULT 1 CHECK (ativo IN (0,1)),
  revogado_em TEXT,
  criado_em TEXT NOT NULL
);

-- Escopo = papel concedido explicitamente em uma IES, opcionalmente restrito a um curso.
CREATE TABLE escopos (
  id INTEGER PRIMARY KEY,
  usuario_id INTEGER NOT NULL REFERENCES usuarios(id),
  ies_id INTEGER NOT NULL REFERENCES ies(id),
  curso_id INTEGER REFERENCES cursos(id),
  papel TEXT NOT NULL CHECK (papel IN ('gestor','reitoria','coordenador','comercial','secretaria','financeiro')),
  concedido_por INTEGER REFERENCES usuarios(id),
  concedido_em TEXT NOT NULL,
  revogado_em TEXT,
  -- coordenador só existe com curso definido
  CHECK (papel <> 'coordenador' OR curso_id IS NOT NULL)
);
CREATE UNIQUE INDEX escopo_unico ON escopos(usuario_id, ies_id, ifnull(curso_id, 0), papel) WHERE revogado_em IS NULL;

CREATE TABLE sessoes (
  token_hash TEXT PRIMARY KEY,
  usuario_id INTEGER NOT NULL REFERENCES usuarios(id),
  criado_em TEXT NOT NULL,
  expira_em TEXT NOT NULL
);

-- Pessoa: dados pessoais mínimos. Deduplicação por e-mail ou telefone normalizado dentro da IES.
CREATE TABLE pessoas (
  id INTEGER PRIMARY KEY,
  ies_id INTEGER NOT NULL REFERENCES ies(id),
  nome TEXT NOT NULL,
  email TEXT,
  telefone TEXT,
  base_legal TEXT NOT NULL CHECK (base_legal IN ('consentimento','procedimentos_preliminares_contrato','legitimo_interesse')),
  origem TEXT NOT NULL CHECK (length(origem) BETWEEN 2 AND 80),
  optout_email INTEGER NOT NULL DEFAULT 0,
  optout_whatsapp INTEGER NOT NULL DEFAULT 0,
  optout_telefone INTEGER NOT NULL DEFAULT 0,
  anonimizada_em TEXT,
  criado_em TEXT NOT NULL,
  CHECK (anonimizada_em IS NOT NULL OR email IS NOT NULL OR telefone IS NOT NULL)
);
CREATE UNIQUE INDEX pessoa_email ON pessoas(ies_id, email) WHERE email IS NOT NULL;
CREATE UNIQUE INDEX pessoa_tel ON pessoas(ies_id, telefone) WHERE telefone IS NOT NULL;

CREATE TABLE oportunidades (
  id INTEGER PRIMARY KEY,
  ies_id INTEGER NOT NULL REFERENCES ies(id),
  curso_id INTEGER NOT NULL REFERENCES cursos(id),
  pessoa_id INTEGER NOT NULL REFERENCES pessoas(id),
  forma_ingresso TEXT NOT NULL CHECK (forma_ingresso IN ('vestibular','enem','transferencia','segunda_graduacao','reingresso','indicacao','convenio','visita_escolar','evento','pos_graduacao')),
  coorte TEXT NOT NULL CHECK (coorte GLOB '[0-9][0-9][0-9][0-9].[12]'),
  etapa TEXT NOT NULL DEFAULT 'novo' CHECK (etapa IN ('novo','contato','inscrito','pre_matricula','matricula_comercial','confirmado','perdido','cancelado')),
  versao INTEGER NOT NULL DEFAULT 1,
  responsavel_id INTEGER REFERENCES usuarios(id),
  motivo_perda TEXT,
  val_documental INTEGER NOT NULL DEFAULT 0,
  val_financeira INTEGER NOT NULL DEFAULT 0,
  val_academica INTEGER NOT NULL DEFAULT 0,
  matricula_comercial_em TEXT,
  confirmada_em TEXT,
  cancelada_em TEXT,
  motivo_cancelamento TEXT,
  criado_em TEXT NOT NULL,
  atualizado_em TEXT NOT NULL,
  UNIQUE (pessoa_id, curso_id, coorte)
);
CREATE INDEX op_ies_coorte ON oportunidades(ies_id, coorte, etapa);

-- Defesa em profundidade: o banco recusa ingresso efetivo sem as três validações,
-- mesmo que a camada de aplicação falhe.
CREATE TRIGGER confirmacao_integra BEFORE UPDATE OF etapa ON oportunidades
WHEN NEW.etapa = 'confirmado' AND (NEW.val_documental = 0 OR NEW.val_financeira = 0 OR NEW.val_academica = 0 OR OLD.etapa <> 'matricula_comercial')
BEGIN SELECT RAISE(ABORT, 'confirmacao incompleta'); END;

CREATE TABLE validacoes (
  id INTEGER PRIMARY KEY,
  oportunidade_id INTEGER NOT NULL REFERENCES oportunidades(id),
  dimensao TEXT NOT NULL CHECK (dimensao IN ('documental','financeira','academica')),
  resultado TEXT NOT NULL CHECK (resultado IN ('valida','invalida','isencao_formal')),
  evidencia TEXT NOT NULL CHECK (length(evidencia) BETWEEN 5 AND 500),
  usuario_id INTEGER NOT NULL REFERENCES usuarios(id),
  em TEXT NOT NULL,
  CHECK (resultado <> 'isencao_formal' OR dimensao = 'financeira')
);

CREATE TABLE propostas (
  id INTEGER PRIMARY KEY,
  ies_id INTEGER NOT NULL REFERENCES ies(id),
  oportunidade_id INTEGER NOT NULL REFERENCES oportunidades(id),
  mensalidade_centavos INTEGER NOT NULL,
  desconto_pct REAL NOT NULL CHECK (desconto_pct BETWEEN 0 AND 100),
  valor_final_centavos INTEGER NOT NULL,
  validade TEXT NOT NULL,
  status TEXT NOT NULL CHECK (status IN ('pendente_aprovacao','aprovada','rejeitada','aceita','expirada')),
  criado_por INTEGER NOT NULL REFERENCES usuarios(id),
  decidido_por INTEGER REFERENCES usuarios(id),
  criado_em TEXT NOT NULL,
  decidido_em TEXT,
  -- segregação de funções: quem cria não aprova
  CHECK (decidido_por IS NULL OR decidido_por <> criado_por)
);

CREATE TABLE tarefas (
  id INTEGER PRIMARY KEY,
  ies_id INTEGER NOT NULL REFERENCES ies(id),
  oportunidade_id INTEGER NOT NULL REFERENCES oportunidades(id),
  tipo TEXT NOT NULL CHECK (tipo IN ('primeiro_contato','follow_up','pendencia_validacao','recuperacao')),
  canal TEXT CHECK (canal IN ('email','whatsapp','telefone')),
  responsavel_id INTEGER REFERENCES usuarios(id),
  vence_em TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'aberta' CHECK (status IN ('aberta','concluida','suprimida','cancelada')),
  resultado TEXT,
  criado_em TEXT NOT NULL,
  encerrada_em TEXT
);
CREATE INDEX tarefa_fila ON tarefas(ies_id, status, vence_em);

CREATE TABLE metas (
  ies_id INTEGER NOT NULL REFERENCES ies(id),
  curso_id INTEGER NOT NULL REFERENCES cursos(id),
  coorte TEXT NOT NULL CHECK (coorte GLOB '[0-9][0-9][0-9][0-9].[12]'),
  meta INTEGER NOT NULL CHECK (meta >= 0),
  PRIMARY KEY (ies_id, curso_id, coorte)
);

-- Auditoria append-only: o próprio banco recusa UPDATE e DELETE.
-- Dados pessoais não são gravados aqui (somente IDs e metadados).
CREATE TABLE auditoria (
  id INTEGER PRIMARY KEY,
  ies_id INTEGER REFERENCES ies(id),
  usuario_id INTEGER REFERENCES usuarios(id),
  acao TEXT NOT NULL,
  entidade TEXT NOT NULL,
  entidade_id TEXT,
  dados TEXT NOT NULL DEFAULT '{}',
  em TEXT NOT NULL
);
CREATE INDEX auditoria_ent ON auditoria(entidade, entidade_id);
CREATE TRIGGER auditoria_sem_update BEFORE UPDATE ON auditoria BEGIN SELECT RAISE(ABORT, 'auditoria imutavel'); END;
CREATE TRIGGER auditoria_sem_delete BEFORE DELETE ON auditoria BEGIN SELECT RAISE(ABORT, 'auditoria imutavel'); END;

-- Idempotência de escritas: mesma chave + mesmo usuário => mesma resposta, sem reexecutar.
CREATE TABLE idempotencia (
  usuario_id INTEGER NOT NULL REFERENCES usuarios(id),
  chave TEXT NOT NULL,
  rota TEXT NOT NULL,
  status INTEGER NOT NULL,
  corpo TEXT NOT NULL,
  em TEXT NOT NULL,
  PRIMARY KEY (usuario_id, chave)
);
