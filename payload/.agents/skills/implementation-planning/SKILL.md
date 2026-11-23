---
name: implementation-planning
description: >-
  Converte uma especificação aprovada em plano técnico com tarefas pequenas, ordenadas
  e verificáveis e uma estratégia de testes proporcional ao risco, antes de editar
  código. Use para mudanças não triviais, features novas, correções em vários arquivos
  ou refatorações. Não use para mudanças triviais nem para decidir regras de produto.
---

# Implementation Planning

## Objetivo e limites

Detalhar a fase 4 do [workflow de entrega](../feature-delivery/references/workflow.md) sem substituí-la. O plano obedece ao [ADR-0001](../../../docs/architecture/adr/0001-architecture-principles.md), às [convenções de packages](../../../docs/architecture/package-conventions.md) e às [regras de dependência](../../../docs/architecture/dependency-rules.md). Planejar não autoriza implementar.

## Procedimento

1. Leia a especificação, o mapa do projeto (`project-discovery`), a análise de impacto (`change-impact-analysis`, quando houver) e os arquivos envolvidos; não planeje sobre suposições do código.
2. Mapeie cada critério BDD para os componentes afetados (na organização adotada pelo projeto) e para o teste que o comprovará, seguindo a [estratégia de testes](references/testing-strategy.md).
3. Liste somente arquivos e packages necessários, sem packages vazios ou abstrações especulativas.
4. Quebre o trabalho em tarefas pequenas, cada uma com:
   - objetivo e arquivos;
   - teste a escrever primeiro, quando TDD se aplicar;
   - comando de verificação e resultado esperado.
5. Ordene por dependência: migração e domínio antes de service; service antes de api.
6. Identifique riscos (transações, concorrência, migração de dados, contrato HTTP) e decisões que exigem ADR ou aprovação humana.
7. Apresente o plano de forma breve antes de editar.

## Formato sugerido

```markdown
## Plano — FEAT-XXXX
- [ ] T1 — <objetivo> · arquivos: ... · teste: ... · verificação: bash scripts/test/unit.sh
- [ ] T2 — ...
Estratégia de testes: <tipos por risco, com o que fica de fora e por quê>
Riscos: ...
Decisões pendentes: ...
```

A estratégia define o que testar; a execução e seus resultados são comprovados por [verification-before-completion](../verification-before-completion/SKILL.md).

Para trabalho que atravessa sessões ou providers, persista o plano com a [skill task-state-files](../task-state-files/SKILL.md). Execute com a [skill plan-execution](../plan-execution/SKILL.md).
