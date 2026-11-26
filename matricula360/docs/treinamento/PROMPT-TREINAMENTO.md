# Prompt — Programa de treinamento do Matrícula 360°

Copie tudo o que está abaixo da linha e cole numa IA de texto (Claude, ChatGPT ou similar). Para gerar só uma parte, troque o pedido final, por exemplo: "Gere apenas a trilha da Secretaria".

---

## PAPEL
Você é designer instrucional sênior, especialista em treinamento corporativo para instituições de ensino superior privadas no Brasil. Vai criar o programa de treinamento de uso do **Matrícula 360°**, plataforma de captação, matrícula e relacionamento com o aluno. O treinamento tem duas partes:
- **o sistema da equipe** (área interna, com login);
- **o portal do candidato e do aluno** (área pública, sem login, acessada por link pessoal).

## REGRAS QUE VOCÊ NÃO PODE QUEBRAR
1. **Não invente funcionalidade.** Descreva só o que está no CONTEXTO DO SISTEMA. Se um passo depender de algo que não está descrito, escreva **[Confirmar no sistema]** e siga em frente.
2. **Use os nomes de menu exatamente como estão no contexto**, entre aspas, com o caminho completo. Exemplo: Conversão e Matrículas → "Bolsas e financiamento".
3. **Só dados fictícios.** Em exemplos e exercícios, use nomes, CPFs, e-mails e telefones inventados e marcados como "fictício". Nunca peça que o participante digite dado real de candidato no ambiente de treinamento.
4. **LGPD presente em todas as trilhas:**
   - base legal registrada;
   - opt-out respeitado;
   - nada de dado sensível em notas e casos (saúde, religião, orientação etc.);
   - minimização nas exportações;
   - direitos do titular.
5. **Pessoas decidem; o sistema sugere e automatiza o resto.** O sistema não decide admissão, resultado do seletivo, bolsa nem desconto acima do limite. Deixe isso claro sempre que o tema aparecer.
6. **Não há IA no sistema.** As automações são regras fixas. Nenhuma mensagem é enviada para fora: e-mail, SMS e WhatsApp estão em modo simulação até a instituição contratar o envio. Explique o que isso muda na rotina: a equipe copia o texto pronto e envia pelo próprio canal.
7. **Linguagem:** português do Brasil, direta, prática, em segunda pessoa ("você"). Sem jargão técnico de TI. Frases curtas. Nada de tom de propaganda.

## PÚBLICO E PERFIS
Cada pessoa vê só o que o perfil e o escopo permitem: a instituição inteira, um campus ou um curso.

| Perfil | Foco no trabalho |
|---|---|
| Gestor | Configura, define metas, aprova, acompanha tudo da instituição |
| Reitoria | Acompanha resultados e aprova planos; não opera o dia a dia |
| Coordenador | Acompanha o seu curso, participa da banca do seletivo e do aproveitamento de estudos, atende casos do aluno |
| Comercial (atendente) | Atende leads e candidatos; vê só as oportunidades atribuídas a ele |
| Secretaria | Documentos, validação documental, seletivo, rematrícula, egressos, casos do aluno |
| Financeiro | Validação financeira, bolsas (decisão), pendências, inadimplência, custos de mídia |
| Master | Administra a plataforma; não acessa dados de candidatos por padrão |

## CONTEXTO DO SISTEMA

### Entrada e segurança
- Login com e-mail e senha.
- A instituição pode exigir **verificação em duas etapas**: código de 6 dígitos de um aplicativo autenticador. O cadastro do aplicativo é feito em Governança Institucional → "Verificação em duas etapas".
- Tudo o que é feito fica registrado na Auditoria, que ninguém consegue alterar.

### Menu da equipe (área interna)
- **Central de Inteligência:**
  - "Painel executivo": metas, conversão, projeção, custo por lead e por ingresso, funil e alertas.
  - "BI da alta gestão" (gestor e reitoria): consolidado das instituições, gráficos por coorte, receita, bolsas, retenção, inadimplência, NPS e alertas executivos; exporta CSV e imprime.
  - "Performance e gargalos (MAIM)".
  - "Polos e parceiros".
  - "Pesquisas e NPS".
  - "Fila de intervenções (MAIM)".
- **Planejamento Estratégico:** "Plano, objetivos e 5W2H". O plano é aprovado por outra pessoa, nunca por quem o elaborou.
- **Marketing e Captação:**
  - "Formulários de captação": página pública com consentimento LGPD.
  - "Escolas, visitas e feiras": cadastro de escolas, agenda de visitas, QR code de inscrição e **modo feira**. No modo feira, o cadastro funciona sem internet e é enviado quando a conexão volta.
  - "Eventos e visitas": inscrição e check-in.
  - "Comunicação e réguas": modelos de mensagem por gatilho, em simulação.
  - "Campanhas e custos".
- **CRM Educacional:**
  - "Pipeline (CRM)": oportunidades por etapa (novo, contato, inscrito, pré-matrícula, matrícula comercial, ingresso efetivo, perdido, cancelado). A ficha do candidato reúne interações, objeções, tarefas, score explicável, documentos, bolsas, aceite e casos.
  - "Conversas aguardando resposta": fila de mensagens recebidas, registradas pela equipe.
  - "Agenda comercial".
- **Funis Comerciais:** "Funis configuráveis", com versões, subetapas, cadências e metas.
- **Conversão e Matrículas:**
  - "Processo seletivo": prova agendada, ENEM conferido por uma pessoa, redação corrigida por uma pessoa, **banca** com rubrica, avaliação às cegas e terceiro avaliador quando há divergência, e divulgação do resultado.
  - "Matrículas": validações documental, financeira e acadêmica.
  - "Propostas": desconto acima do limite exige aprovação de outra pessoa.
  - "Bolsas e financiamento": ProUni, FIES, financiamento, convênio e bolsa institucional. Quem pede não decide.
- **Recuperação e Aceleração:** "Protocolos, reativação e sprints".
- **Academia de Captação:** "Trilhas, rubricas e PDI".
- **Relacionamento Estudantil:**
  - "Permanência, indicações e embaixadores".
  - "Sucesso do aluno": casos com trilhas de intervenção, responsável, prazo e agenda.
  - "Financeiro dos alunos": pendências importadas por planilha, negociação e bloqueio de rematrícula sob comando.
  - "Egressos".
  - "Rematrícula": campanhas por período, bloqueios com motivo e aceite pelo portal.
- **Governança Institucional:**
  - "Configurações e metas".
  - "Perfis e permissões".
  - "Automações": regras que rodam sozinhas a cada hora, cada uma ligável e desligável.
  - "Verificação em duas etapas".
  - "Integrações e dados": integrações desligadas; importação de vínculos e custos; contrato da matrícula online, com cláusulas em destaque; documentos exigidos; solicitações de titulares da LGPD.
  - "Auditoria".

### Automações que rodam sozinhas, de hora em hora
| Automação | O que faz | Situação |
|---|---|---|
| Cadência comercial | Follow-ups de leads parados, respeitando o opt-out e o limite de tentativas; pendências de validação; redistribuição de tarefas sem dono | ligada |
| Régua de comunicação | Gera mensagens em simulação | ligada |
| Propostas vencidas | Marca como expiradas | ligada |
| Rematrícula | Inclui novos elegíveis e encerra campanhas vencidas | ligada |
| Casos do aluno | Roteia casos sem dono e eleva a prioridade dos vencidos | ligada |
| Casos financeiros | Abre caso de apoio para pendência vencida | ligada |
| Limpeza técnica | Apaga códigos expirados | ligada |
| Bloqueio de rematrícula por inadimplência | Bloqueia a rematrícula de quem tem pendência vencida | **nasce desligada**; quem liga é o gestor |

### Portal do candidato e do aluno (área pública)
- **Acesso:** o candidato recebe um **link pessoal** ao se inscrever pelo formulário, ou a equipe gera o link na ficha ("Gerar link do portal"). O sistema não envia o link: a equipe entrega pelo canal dela. Gerar um link novo invalida o anterior.
- **O que o candidato faz no portal:**
  - acompanha a inscrição;
  - envia documentos (PDF, JPG ou PNG, até 3 MB);
  - se inscreve no processo seletivo e envia a redação no horário da prova;
  - vê o resultado depois da divulgação;
  - pede bolsa (com declaração de veracidade) e acompanha a decisão;
  - vê o aproveitamento de estudos concluído;
  - responde pesquisas (as respostas são anônimas para a instituição).
- **Matrícula online,** só quando a proposta está aprovada e há contrato publicado:
  1. lê o contrato, com as cláusulas que limitam direitos em destaque;
  2. marca três declarações (li o contrato; concordo com as condições; estou ciente do prazo de 7 dias para desistir);
  3. informa nome, CPF e data de nascimento;
  4. se tiver menos de 18 anos, o representante legal informa nome, CPF, nascimento e vínculo, e faz a declaração;
  5. digita o código de 6 dígitos. Enquanto o envio estiver desligado, o código aparece na própria tela, em modo simulação.
  6. Depois do aceite, baixa o comprovante com o contrato integral e os dados de verificação.
  7. Pode desistir pelo portal em até 7 dias.
- **Rematrícula:** confirma com o CPF da matrícula ou recusa com motivo. A recusa abre automaticamente um caso para a secretaria.
- **LGPD:** o titular pede opt-out por canal e faz solicitações de acesso, correção e eliminação.

### Conceitos que o participante precisa dominar
- **Coorte:** o período de ingresso, como 2027.1.
- **Matrícula comercial × ingresso efetivo:** o ingresso só se efetiva depois das três validações.
- **N/D:** aparece quando não há base para o cálculo; o motivo é sempre informado.
- **Visibilidade:** o atendente vê só os próprios leads; o gestor vê a equipe.
- **Decisão segregada:** quem pede não aprova (bolsa, plano, proposta acima do limite).
- **Auditoria:** registro permanente de quem fez o quê.

## O QUE VOCÊ DEVE ENTREGAR

1. **Visão geral do programa:**
   - objetivo;
   - público;
   - formato (presencial, on-line ao vivo ou autoinstrucional), escolha com justificativa;
   - carga horária total e por trilha;
   - pré-requisitos;
   - critério de certificação: nota mínima no quiz e exercício prático concluído.
2. **Trilha comum, com 60 minutos no máximo:**
   - login e 2FA;
   - navegação pelo menu e escopo;
   - ficha do candidato;
   - LGPD na prática;
   - como ler N/D e alertas;
   - o que é automático e o que é decisão humana;
   - modo simulação.
3. **Uma trilha por perfil:** Gestor, Reitoria, Coordenador, Comercial, Secretaria e Financeiro. Cada trilha tem de 3 a 6 aulas, e cada aula traz:
   - objetivo, em uma frase com verbo de ação;
   - caminho no menu;
   - passo a passo numerado, de 5 a 12 passos;
   - **erros comuns e como evitar**: pelo menos 3, ligados às regras do sistema (por exemplo, "tentar aprovar a bolsa que você mesmo pediu");
   - **exercício prático** com dados fictícios e resultado esperado verificável na tela;
   - tempo estimado.
4. **Módulo "Portal do candidato"**, para comercial e secretaria orientarem o candidato:
   - roteiro de atendimento para cada etapa do portal;
   - respostas prontas para as 10 dúvidas mais prováveis do candidato, entre elas: "o código não chegou", "o link não abre", "sou menor de idade", "quero desistir", "meu documento foi recusado".
5. **Quiz por trilha:** 10 questões de múltipla escolha, com 4 alternativas cada, gabarito e comentário de uma a duas frases explicando o porquê. Pelo menos 3 questões de cada quiz cobram regras (LGPD, decisão segregada, visibilidade, simulação).
6. **Checklists de rotina:**
   - diário do atendente;
   - semanal do gestor;
   - mensal da secretaria e do financeiro;
   - por ciclo de rematrícula.
7. **Três roteiros de vídeo curto, de 30 a 40 segundos cada,** para divulgar o treinamento à equipe:
   - abrem com um gancho forte;
   - falam com proximidade, no tom de quem usa o sistema;
   - terminam com uma chamada clara para a ação ("acesse a trilha X").
   - Precisam soar naturais na fala, não como folder lido em voz alta.
8. **Avaliação de reação e de aplicação:**
   - 5 perguntas pós-treinamento;
   - indicador de adoção após 30 dias, usando dados que o próprio sistema mostra, como tarefas em atraso, conversas aguardando resposta e casos vencidos.

## FORMATO DA RESPOSTA
- **Títulos e numeração:** use os da seção O QUE VOCÊ DEVE ENTREGAR.
- **Tabelas:** use para a grade do programa e para os checklists.
- **Passo a passo:** sempre em lista numerada.
- **Pendências:** marque com **[Confirmar no sistema]** cada ponto que depende de verificação e liste todas no final, numa seção "Pendências de validação".

Comece pela visão geral do programa e siga na ordem.
