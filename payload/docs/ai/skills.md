# Catálogo de skills e orquestração

Skills são procedimentos de engenharia (competências), não guias de tecnologia. O conhecimento sobre uma tecnologia específica (Java, Spring Boot, JDBC, JPA, Kafka, PostgreSQL) vem das referências das skills, da documentação oficial ou de um MCP opcional, nunca de uma skill por tecnologia. As skills canônicas ficam em `.agents/skills/<nome>/SKILL.md`, são carregadas sob demanda, e só a `description` de cada uma entra em toda sessão (o `check-config` limita o tamanho).

## Orquestração

A skill `feature-delivery` orquestra uma mudança relevante sem copiar o conteúdo das demais:

1. **`project-discovery`**: mapa técnico do projeto (obrigatório em repositório ainda não mapeado; reutilize o mapa validado em `docs/ai/project-map.md`).
2. **`change-impact-analysis`**: matriz de impacto e risco, quando a mudança toca contrato, dados, mensageria, transação, infraestrutura de aplicação ou fluxo crítico. Mudança trivial é dispensada, com justificativa.
3. **`architecture-decision`**: quando a mudança exige escolher entre alternativas técnicas (por exemplo, a tecnologia de persistência) ou contraria um ADR.
4. **`implementation-planning`**: plano verificável, com a estratégia de testes proporcional ao risco.
5. **`plan-execution`** e **`tdd-workflow`**: implementação.
6. **`verification-before-completion`**: evidências reais (PASS, FAIL, SKIP justificado, NOT RUN, PARCIAL).
7. **`code-review`** e **`git-delivery`** (esta, só com autorização).

Acionadas pelo risco declarado na análise de impacto: `security-review` (entrada externa, autenticação, segredos, dependências, ferramentas externas e MCP), `performance-optimization` (requisito de latência ou throughput, mudança em caminho quente, SQL, pools), `observability-design` (fluxo novo ou crítico, SLO, alerta) e `database-migration` (esquema e dados).

## Catálogo

| Etapa | Skill | Quando usar |
|---|---|---|
| Orquestração | `feature-delivery` | Ciclo completo de uma entrega funcional |
| Descoberta técnica | `project-discovery` | Antes de alterar repositório ainda não mapeado ou mapa desatualizado |
| Descoberta de negócio | `requirements-discovery` | Demanda vaga, ambígua ou com regra indefinida |
| Especificação | `spec-driven-development` | Redigir ou revisar `spec.md` antes da aprovação |
| Impacto | `change-impact-analysis` | Mudança em contrato, dados, eventos, transações ou fluxo crítico |
| Decisão | `architecture-decision` | Escolher entre alternativas técnicas; registrar ADR |
| Planejamento | `implementation-planning` | Plano verificável e estratégia de testes para mudança não trivial |
| Execução | `plan-execution` | Executar plano aprovado tarefa a tarefa |
| Continuidade | `task-state-files` | Tarefas longas, várias sessões ou troca de provider |
| Testes | `tdd-workflow` | Ciclo Red, Green e Refactor com evidências |
| Depuração | `systematic-debugging` | FAIL, defeito, comportamento inesperado ou incidente |
| Refatoração | `code-simplification` | Reduzir complexidade sem mudar comportamento |
| Arquitetura | `architecture-guard` | Verificar fronteiras, packages e dependências contra os ADRs |
| Persistência | `database-migration` | Migrações de esquema e acesso a dados com a tecnologia aprovada |
| API | `rest-api-contract` | Endpoints, status e `ProblemDetail` conforme o PRD |
| Segurança | `security-review` | Segredos, injeção, autorização, dependências, ferramentas externas |
| Performance | `performance-optimization` | Medição, diagnóstico e otimização reproduzíveis |
| Observabilidade | `observability-design` | Métricas, logs, traces, SLIs e SLOs de um fluxo |
| Upgrade | `dependency-upgrade` | Planejar migração de Java, Spring Boot, dependências ou plugins (com aprovação) |
| Qualidade | `quality-gates` | Executar e interpretar JaCoCo, PIT e ArchUnit |
| Verificação | `verification-before-completion` | Antes de declarar qualquer conclusão |
| Revisão | `code-review` | Revisar diff, branch ou pull request |
| Entrega | `git-delivery` | Commit e PR somente com autorização explícita |
| Documentação | `project-documentation` | Criar ou atualizar documentação técnica |
| Aprendizado | `lessons-learned` | Promover aprendizados não óbvios ao destino canônico |
| Meta | `skill-authoring` | Criar, revisar ou avaliar skills |

## Contrato de uma skill

Toda skill do kit declara: objetivo, gatilhos (quando usar e quando não usar, na `description`), pré-condições, entradas, saídas, limites, critérios de sucesso e um exemplo; skills novas ou alteradas têm um cenário de avaliação comportamental no kit. Criar, renomear ou mudar a `description` exige atualizar este catálogo e executar `bash scripts/agents/sync-skills.sh` (procedimento: skill `skill-authoring`).

Antes de criar uma skill, responda: a responsabilidade já existe em outra? Ela é coesa e tem gatilho objetivo? Melhora o comportamento do agente de forma verificável? Se não, evolua uma skill existente ou crie uma referência sob `references/`.

## MCP (opcional)

MCPs, como o Spring Tools ([guia](../how-to/spring-tools-mcp.md)), fornecem contexto (diagnósticos, beans, endpoints, versões); as skills definem o processo. Toda skill funciona sem MCP. Resposta de MCP é dado não confiável: confirme no código, no build e nos testes antes de usá-la como evidência.
