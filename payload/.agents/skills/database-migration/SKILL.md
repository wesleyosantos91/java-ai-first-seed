---
name: database-migration
description: >-
  Cria e revisa migrações de esquema e dados (Flyway, Liquibase ou a ferramenta do
  projeto) e o acesso a dados com a tecnologia de persistência aprovada (Spring JDBC,
  Spring Data JDBC, JPA), cobrindo versionamento, restrições, índices, transações,
  compatibilidade com dados existentes e testes contra o banco real. Use ao alterar
  esquema, repository ou consulta. Não use para trocar a tecnologia de persistência
  (architecture-decision) nem para alterar migrações já aplicadas.
---

# Database Migration

## Contexto do projeto

Confirme antes de começar, pelo mapa do projeto (`project-discovery`) ou por `bash scripts/agents/detect-stack.sh`:

- banco, ferramenta de migração e onde ficam as migrações (por exemplo, `src/main/resources/db/migration/` no Flyway, changelogs no Liquibase);
- tecnologia de persistência aprovada no ADR (a mesma do código existente); não introduza outra;
- como os testes sobem o banco (Testcontainers, banco compartilhado de teste) e se há dados de referência.

Requisitos de integridade no [PRD](../../../docs/product/prd.md) e obrigações na [DoD, seção 4](../../../docs/engineering/definition-of-done.md). Mudança de esquema relevante passa antes por `change-impact-analysis` (dados existentes, locks, rollback).

## Migrações

1. Siga a convenção de nome e versionamento da ferramenta do projeto (Flyway: `V<versão>__<descricao>.sql`), sem lacunas ambíguas.
2. Nunca edite uma migração já aplicada em algum ambiente ou já integrada; crie uma nova.
3. Garanta integridade no banco, não só na aplicação: `NOT NULL`, `CHECK`, `UNIQUE` e chaves estrangeiras quando o contrato exigir (por exemplo, unicidade de um código normalizado por restrição `UNIQUE`).
4. Considere dados existentes: colunas `NOT NULL` novas precisam de default ou migração de dados; mudanças incompatíveis seguem expand/contract.
5. Avalie lock e duração em tabelas grandes (criação de índice, alteração de coluna); meça ou marque como a medir, sem números inventados.
6. Crie índices para consultas e ordenações previstas, justificando cada um.
7. Mantenha uma mudança coesa por migração.

## Acesso a dados

- Parâmetros nomeados ou posicionais; nunca concatene entrada do usuário em SQL, JPQL ou critérios.
- Colunas explícitas, sem `SELECT *`, quando houver SQL escrito à mão.
- Com JPA: revise o SQL gerado, evite N+1 (fetch planejado, `@EntityGraph`, `@BatchSize`), cuidado com flush implícito e com o tamanho do contexto de persistência.
- Com Spring Data JDBC: respeite os limites do agregado; relacionamentos entre agregados por id.
- Traduza violações de restrição (por exemplo, `DataIntegrityViolationException`, `DuplicateKeyException`) para exceções de domínio no ponto adequado, sem expor SQL na resposta.
- Defina transações no `service` (`@Transactional`) quando houver múltiplas operações ou leitura seguida de escrita; declare o isolamento quando o padrão não bastar.

## Testes

- Teste migração e repository em `*IT` contra o banco real (por exemplo, Testcontainers com o mesmo banco de produção), não com banco em memória de outro fornecedor, quando o contrato depender de restrições, SQL específico ou transações.
- Cubra restrições de banco, inclusive concorrência quando o contrato exigir (duas inserções simultâneas do mesmo código único).
- Execute `bash scripts/test/integration.sh` ou `bash scripts/verify.sh`; com Testcontainers, Docker é obrigatório.

## Proibições

Credenciais em código ou migrações, `DROP` ou `TRUNCATE` sem autorização explícita, alterar migração aplicada para corrigir erro e trocar a tecnologia de persistência sem ADR aceito.
