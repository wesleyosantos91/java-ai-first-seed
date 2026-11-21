# Java AI-First Seed

Chassi de contexto para projetos Java desenvolvidos com agentes de IA (Codex, Claude Code, Devin). Não contém regra de negócio: traz as instruções dos agentes, as skills, o harness de verificação, os quality gates e um PRD guiado para o time de negócio preencher.

## Estrutura

| Diretório | Conteúdo |
|---|---|
| Raiz: [AGENTS.md](AGENTS.md), `.agents/`, `.claude/`, `.codex/`, `docs/`, `scripts/`, `.harness` | Configuração AI-First, que vale para o repositório inteiro |
| `app/` | Projeto Maven: Spring Boot 4, Java 27, Spring JDBC, PostgreSQL, Flyway, Testcontainers; sem endpoints |
| `infra/` | Infraestrutura como código e configuração de ambiente |
| `tests/` | Testes fora do app (smoke k6 em `tests/performance/k6/`) |
| `.github/` | Não vem no seed: workflows, CODEOWNERS e templates são configurados pelo time de DevOps, e agentes não os alteram |

Detalhes e regras por diretório: [layout do repositório](docs/architecture/repository-layout.md).

## Como começar

1. **Criar o repositório:** botão *Use this template* no GitHub e clone do novo repositório.
2. **Dar nome ao projeto** (pacote, classe principal, identidade Maven em `app/pom.xml` e este README):

   ```bash
   bash scripts/agents/init-project.sh --base-package com.acme.orders \
     --main-class OrdersApplication --project-name "Orders Service"
   ```

3. **Time de negócio: preencher o PRD** em [docs/product/prd.md](docs/product/prd.md). Cada seção diz quem a preenche (`Negócio`, `Engenharia` ou `Ambos`) e se é obrigatória; os campos pendentes aparecem como `[PREENCHER-NEGÓCIO: ...]` e `[PREENCHER-ENGENHARIA: ...]`. Para ver o que falta, por responsável:

   ```bash
   bash scripts/product/check-prd.sh
   ```

   O PRD só pode ser marcado como **Aprovado** sem pendências; a verificação dos agentes falha caso contrário.

4. **Engenharia:** complete as seções técnicas do PRD, ajuste o `AGENTS.md` (§1 propósito, §2 stack), revise os ADRs herdados e a licença.
5. **Ativar o harness:**

   ```bash
   bash scripts/git/install-hooks.sh
   bash scripts/setup.sh
   bash scripts/verify.sh
   ```

   Sem código de negócio, unitários e cobertura retornam SKIP e o resultado é PARCIAL. É o esperado até a primeira feature.

6. **Primeira feature:** com o PRD aprovado, peça ao agente a skill `feature-delivery`.

## Origem

Este template é gerado pelo exportador do kit (modo `--seed`) do repositório de referência [java-ai-engineering-lab](https://github.com/wesleyosantos91/java-ai-engineering-lab). Correções no chassi são feitas lá e chegam aqui por regeneração. O projeto criado pelo `init-project.sh` não depende deste template nem do repositório de referência.

## Licença

[Apache License 2.0](LICENSE). Projetos criados a partir deste template escolhem a própria licença.
