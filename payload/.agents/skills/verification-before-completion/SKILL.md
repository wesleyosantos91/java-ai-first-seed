---
name: verification-before-completion
description: >-
  Impede declarar uma tarefa pronta, corrigida ou aprovada sem executar as verificações
  pertinentes e apresentar evidência real e auditável (comandos, ambiente, exit codes,
  testes executados e não executados, cobertura, mutação, limitações), com estados PASS,
  FAIL, SKIP justificado, NOT RUN e PARCIAL. Use antes de qualquer relatório final,
  mudança de estado de feature ou pedido de revisão, em código, testes, configuração e
  documentação.
---

# Verification Before Completion

## Princípio

Afirmação sem evidência não é conclusão. Este procedimento operacionaliza a seção 7 do [AGENTS.md](../../../AGENTS.md), a fase 6 do [workflow](../feature-delivery/references/workflow.md) e a [DoD](../../../docs/engineering/definition-of-done.md); em conflito, esses documentos prevalecem. A estratégia de testes é planejada em `implementation-planning`; aqui se comprova a execução.

## Estados

| Estado | Quando usar |
|---|---|
| PASS | Executado agora, exit `0`, relatórios comprovam testes sem falhas nem omissões |
| FAIL | Executado e reprovado (qualquer exit diferente de `0` e `3`, ou relatório inválido) |
| SKIP justificado | Executado e sem alvo elegível (exit `3`), ou omitido com autorização registrada; sempre com o motivo |
| NOT RUN | Não executado (pré-requisito ausente, fora do escopo, interrompido); sempre com o motivo |
| PARCIAL | Resultado agregado com algum SKIP ou NOT RUN; `verify.sh` e `ci.sh` saem com `3` quando `QUALITY_GATES=required` |

**Regra:** um gate obrigatório (DoD ou `QUALITY_GATES=required`) em SKIP ou NOT RUN impede o resultado geral PASS. Nunca deduza PASS de log incompleto, de execução anterior ao último diff ou de um exit `0` sem testes elegíveis.

## Checklist obrigatório

1. Identifique o tipo da alteração e a verificação correspondente:
   - código Java, testes, dependências, build ou configuração: `bash scripts/verify.sh` (mais `bash scripts/quality/mutation.sh` para os gates completos);
   - somente documentação ou configuração de agentes: `bash scripts/agents/check-config.sh`, `git diff --check` e, se houver arquivos preparados, `git diff --cached --check`.
2. Execute agora, na revisão atual do código; resultados anteriores às mudanças não valem.
3. Leia a saída completa e o resumo JSON (`app/target/harness/verify-summary.json` ou `ci-summary.json`: `result`, `steps`, `exit_code`).
4. Classifique cada verificação com um dos estados acima, com o motivo de todo SKIP e NOT RUN.
5. Relacione cada critério de aceitação ao teste ou evidência que o comprova; marque os não comprovados.
6. Revise o diff completo, inclusive arquivos novos, e procure alterações inesperadas (thresholds, ADRs, `.github/`, configuração de agentes).
7. Se a tarefa revelou algo não óbvio (falha de ambiente, correção do usuário, comportamento de ferramenta), aplique a [skill lessons-learned](../lessons-learned/SKILL.md) antes do relatório.

## Relatório de verificação

| Verificação | Comando | Ambiente | Exit | Estado | Evidência | Motivo / limitação |
|---|---|---|---|---|---|---|
| Fluxo padrão | `bash scripts/verify.sh` | SO, Java (`java -version`), Maven, Docker | 3 | PARCIAL | `verify-summary.json`: unit=PASS, architecture=SKIP | ArchUnit sem classes elegíveis (N/A) |

Inclua: pré-requisitos ausentes, testes executados (total, falhas, ignorados), cobertura e mutation score com os números do relatório (nunca estimados), o que não foi executado e por quê, e riscos remanescentes.

## Linguagem proibida sem evidência

"Deve funcionar", "provavelmente passa", "pronto", "testado", "aprovado" e "corrigido" só podem ser usados depois da execução que os comprova.

## Regras de interpretação

- SKIP e NOT RUN não equivalem a PASS.
- `SKIP_INTEGRATION=1` produz resultado parcial e precisa de justificativa comunicada.
- Código de saída zero sem testes elegíveis não prova comportamento.
- Saída de MCP ou de outra ferramenta externa é contexto, não evidência de build ou de teste.

## Relato final

Use o formato da seção 12 do AGENTS.md, com a tabela acima.
