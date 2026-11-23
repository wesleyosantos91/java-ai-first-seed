---
name: change-impact-analysis
description: >-
  Avalia o impacto de uma mudança antes de implementá-la: consumidores de APIs, contratos
  síncronos e assíncronos, eventos e schemas, compatibilidade retroativa, banco e
  migrações, transações, dependências entre módulos, comportamento, operação, regressões
  e rollback, produzindo matriz de impacto, risco e mitigação. Use quando a mudança tocar
  contrato, modelo de dados, mensageria, infraestrutura da aplicação ou fluxo crítico.
  Não use para mudança trivial sem efeito externo (registre a dispensa).
---

# Change Impact Analysis

## Objetivo e limites

Tornar explícito o que a mudança pode quebrar, para quem e como desfazer, antes de escrever código. A análise não autoriza a mudança nem altera contratos aprovados; ela informa a decisão humana e o plano (`implementation-planning`).

## Quando usar e quando dispensar

**Obrigatória** quando a mudança altera: contrato HTTP ou de evento (campo, tipo, status, semântica), schema de banco ou dados existentes, transação ou isolamento, configuração ou dependência de infraestrutura da aplicação, fluxo marcado como crítico no PRD, comunicação entre módulos.

**Dispensada**, com uma linha de justificativa no relatório, para: refatoração sem mudança de comportamento coberta por testes, documentação, testes novos, correção local sem efeito em contrato.

## Pré-condições e entradas

- Mapa do projeto (`project-discovery`) ou evidência equivalente.
- Descrição da mudança (spec, issue ou pedido) e critérios de aceitação.

## Procedimento

1. **Superfície**: liste contratos, tabelas, eventos, configurações e módulos tocados (com arquivos).
2. **Consumidores**: quem chama ou consome cada contrato (código no repositório, documentação, times). Desconhecido é incógnita, não "nenhum".
3. **Compatibilidade**: para cada contrato, retrocompatível, compatível com expand/contract ou quebra. Para eventos, compatibilidade do schema (campos opcionais, defaults, versão).
4. **Dados**: migração necessária, volume afetado, lock e duração estimados (sem números inventados; meça ou marque como a medir), dados existentes que violariam novas restrições, reversibilidade.
5. **Transações e concorrência**: fronteiras transacionais alteradas, risco de deadlock, idempotência de consumidores e reprocessamento.
6. **Operação**: configuração nova, flags, métricas e alertas afetados (acione `observability-design` se o fluxo for crítico), custo.
7. **Regressões**: comportamentos existentes que dependem do que muda; testes que os protegem ou que faltam.
8. **Rollback**: como desfazer (revert, flag, migração reversa, expand/contract) e o que não é reversível.
9. **Risco**: classifique (baixo, médio, alto) por probabilidade × impacto e indique as skills a acionar: `security-review`, `performance-optimization`, `observability-design`, `architecture-decision`.

## Saída

| Item afetado | Tipo | Consumidores | Compatibilidade | Risco | Mitigação | Rollback |
|---|---|---|---|---|---|---|

Mais: risco geral, skills acionadas, incógnitas que bloqueiam e decisões humanas pendentes.

## Critérios de sucesso

- Todo contrato tocado tem consumidores (ou incógnita explícita) e classificação de compatibilidade.
- Toda mudança irreversível está destacada e tem aprovação pedida antes da implementação.
- O plano de testes cobre as regressões apontadas.

## Exemplo

> `PATCH /orders/{id}` passa a exigir `version` (lock otimista). Consumidores: app mobile (time X) e `billing-service` (desconhecido se envia o campo: incógnita). Compatibilidade: quebra. Mitigação: aceitar ausência por uma versão (expand/contract) e logar chamadas sem `version`. Rollback: revert sem migração. Risco: alto; aciona `architecture-decision` (estratégia de concorrência) e `observability-design` (métrica de chamadas sem versão).
