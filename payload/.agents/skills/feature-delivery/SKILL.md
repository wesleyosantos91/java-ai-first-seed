---
name: feature-delivery
description: >-
  Orienta o ciclo de entrega funcional deste repositório, do contrato e da
  autorização às evidências e à revisão humana. Use para criar uma nova feature,
  evoluir uma funcionalidade existente, implementar um requisito do PRD, corrigir
  comportamento de uma feature, planejar e executar uma entrega funcional ou
  validar seus critérios de aceitação. Para tarefas exclusivamente documentais,
  utilize project-documentation.
---

# Feature Delivery

## Objetivo e limites

Coordenar entregas reproduzíveis e auditáveis conforme o [AGENTS.md](../../../AGENTS.md), que permanece a instrução global do repositório. A skill orienta o processo; sua leitura não autoriza implementar, modificar contratos ou executar operações Git de entrega.

O [catálogo](../../../docs/features/README.md) mantém identificação, estados, aprovações e governança. Use a especificação existente e a autorização vigente da solicitação; não exija nova confirmação para ações já autorizadas. Se houver ambiguidade material ou conflito com o contrato, esclareça a decisão pendente antes da ação dependente.

## Fluxo principal

Cada etapa aciona a skill responsável, sem copiar o conteúdo dela ([catálogo e orquestração](../../../docs/ai/skills.md)):

1. Classifique a demanda e localize contrato, especificação, restrições e dependências. Confirme o escopo autorizado; aprovação do PRD geral não autoriza toda implementação.
2. **Descoberta**: [project-discovery](../project-discovery/SKILL.md) se o repositório não tem mapa válido; senão, reutilize `docs/ai/project-map.md`.
3. **Impacto**: [change-impact-analysis](../change-impact-analysis/SKILL.md) quando a mudança toca contrato, dados, eventos, transações, infraestrutura da aplicação ou fluxo crítico; para mudança trivial, registre a dispensa em uma linha.
4. **Decisão**: [architecture-decision](../architecture-decision/SKILL.md) quando houver escolha técnica sem decisão vigente ou conflito com ADR. Não implemente com base em decisão não aceita.
5. **Plano**: [implementation-planning](../implementation-planning/SKILL.md), com a estratégia de testes proporcional ao risco. Riscos apontados na análise de impacto acionam [security-review](../security-review/SKILL.md), [performance-optimization](../performance-optimization/SKILL.md) ou [observability-design](../observability-design/SKILL.md).
6. **Implementação**: execute somente o trabalho autorizado ([plan-execution](../plan-execution/SKILL.md), [tdd-workflow](../tdd-workflow/SKILL.md)), conforme os documentos arquiteturais e os critérios BDD. Não crie especificações, packages ou decisões especulativas.
7. **Verificação**: [verification-before-completion](../verification-before-completion/SKILL.md) com o harness real, registrando PASS, FAIL, SKIP justificado, NOT RUN ou PARCIAL. Acione [project-documentation](../project-documentation/SKILL.md) para documentação impactada; se ausente, informe e use as regras locais.
8. **Revisão e entrega**: relacione evidências aos critérios de aceitação e à DoD, revise o diff ([code-review](../code-review/SKILL.md)) e prepare a revisão humana. Atualize especificação e catálogo somente nas condições permitidas; Concluída exige revisão humana favorável verificável. Commit e push exigem autorização explícita.

## Referência sob demanda

Consulte o [workflow operacional](references/workflow.md) apenas nas fases pertinentes à solicitação:

- Fases 1–3: intake, contrato, especificação e aprovação.
- Fases 4–6: planejamento, implementação e verificação.
- Fases 7–9: documentação, revisão e transições de estado.

Carregue PRD, ADRs, documentos de engenharia e referências especializadas conforme a necessidade de cada fase, sem ler todo o repositório automaticamente. A saída esperada é um relato do escopo realizado, arquivos envolvidos, critérios atendidos, comandos e resultados reais, limitações e decisões humanas pendentes.

## Compatibilidade

A localização canônica é `.agents/skills/feature-delivery/SKILL.md`, lida nativamente por Codex e Devin. O Claude Code usa o stub gerado em `.claude/skills/` ([ADR-0002](../../../docs/architecture/adr/0002-multi-provider-agent-context.md)). A descoberta depende do cliente e não garante ativação automática; se necessário, leia o arquivo explicitamente. Não duplique o conteúdo da skill em diretórios de provedores.

O formato segue a [especificação Agent Skills](https://agentskills.io/specification). Nenhum comando específico de provedor é necessário para executar este fluxo.
