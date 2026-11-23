# ADR-0001: Princípios de arquitetura

## Status

Proposta — decidir na seção "Revisão neste projeto"

## Contexto

O kit AI-First é instalado em aplicações Java existentes, com stacks, arquiteturas e tecnologias de persistência diferentes. Os agentes de IA precisam de princípios explícitos para não impor preferências tecnológicas nem decidir sem evidência. Este ADR propõe princípios gerais; as escolhas tecnológicas do projeto são registradas na revisão abaixo e em ADRs próprios.

## Decisão

### Linguagem e framework

- Preservar a versão de Java e de Spring Boot do projeto (detectadas no `app/pom.xml`; `bash scripts/agents/detect-stack.sh`). Projetos novos adotam Java 25 (LTS).
- Upgrade de Java ou de Spring Boot só com aprovação explícita, plano e testes de regressão (skill `dependency-upgrade`).
- Priorizar recursos nativos da plataforma; introduzir bibliotecas somente com justificativa técnica registrada.

### Arquitetura

- Manter regras de negócio independentes de transporte e de detalhes de persistência.
- Organização de packages: Feature-Based é a proposta do kit ([convenções](../package-conventions.md)); um projeto com outra organização a registra aqui e pode migrar só por decisão explícita.
- Evitar abstrações especulativas e complexidade acidental; aplicar SOLID, KISS e YAGNI conforme o contexto.
- Registrar decisões relevantes em ADRs, conduzidas pela skill `architecture-decision`.

### Persistência

- Usar a tecnologia de persistência já adotada pelo projeto (JDBC, Spring Data JDBC, Spring Data JPA ou outra). Trocá-la ou introduzir uma segunda exige decisão registrada em ADR, com alternativas, trade-offs e evidências ([referência](../../../.agents/skills/architecture-decision/references/persistence.md)).
- Versionar alterações de esquema com a ferramenta de migração do projeto.
- Testar a persistência contra o banco real (por exemplo, com Testcontainers) quando o contrato depender de restrições, transações ou SQL específico.
- Avaliar transações, isolamento e índices com evidências.

### Qualidade

- Desenvolver testes automatizados para comportamentos relevantes, com estratégia proporcional ao risco.
- Aplicar TDD quando adequado e BDD para cenários de negócio.
- Quality gates: JaCoCo, PIT e testes arquiteturais ([ADR-0003](0003-test-suites-and-quality-gates.md)).
- Não confundir cobertura de código com qualidade dos testes.

### Observabilidade

- Preservar a solução de observabilidade já adotada (backend, agentes, bibliotecas); nenhum fornecedor é dependência universal do kit.
- Adotar logs estruturados com correlação de traces e métricas de tráfego, erros, latência e saturação para os fluxos críticos (skill `observability-design`).

### Performance

- Medir antes de otimizar; registrar ambiente e metodologia.
- Avaliar throughput, p95, p99, CPU e memória conforme o workload; capacidades como Virtual Threads, JFR, Spring AOT e CDS/AOT cache são objetos de decisão com evidência, não padrões.

### AI-First

- Manter instruções versionadas para agentes.
- Definir limites de autonomia e critérios de aceitação.
- Exigir revisão humana para decisões arquiteturais relevantes.
- Não aceitar resultados declarados sem evidências verificáveis.

## Alternativas consideradas

- Impor uma stack única (por exemplo, Spring JDBC e um fornecedor de observabilidade) a todos os projetos: rejeitada; ignora o legado e o contexto de cada aplicação.
- Não registrar princípios: rejeitada; os agentes decidiriam por preferência.

## Consequências positivas

- Decisões contextuais e rastreáveis; o kit se adapta a projetos existentes.
- Agentes param e pedem decisão em vez de impor tecnologia.

## Consequências negativas

- Cada projeto precisa registrar suas escolhas (revisão abaixo e ADRs próprios).
- Regras automatizadas de tecnologia só existem depois dessas decisões.

## Validação

Revisão de código, testes automatizados, testes arquiteturais derivados de ADRs aceitos, benchmarks quando a decisão depender de desempenho e análise de trade-offs.

## Revisão da decisão

Este ADR deverá ser revisado quando novas evidências justificarem alterações. Mudanças relevantes deverão ser documentadas em novos ADRs, preservando o histórico.

## Revisão neste projeto

> **Quem preenche:** Engenharia · **Obrigatória** antes da primeira feature. Registre a decisão aqui e no [índice](README.md). Para mudar o conteúdo da decisão, registre um novo ADR que a substitua.

| Campo | Valor |
|---|---|
| Decisão | [PREENCHER-ENGENHARIA: Aceita, Rejeitada ou Substituída por ADR-NNNN] |
| Responsável | [PREENCHER-ENGENHARIA: nome e papel] |
| Data | [PREENCHER-ENGENHARIA: AAAA-MM-DD] |
| Ajustes para este projeto | [PREENCHER-ENGENHARIA: Java, Spring Boot, organização de packages, persistência e observabilidade adotadas, ou "Nenhum"] |
