# Estratégia de testes proporcional ao risco

Referência da skill `implementation-planning`. A estratégia diz **o que** testar e **por quê**; a execução é comprovada por `verification-before-completion`. Testes existem para detectar regressões reais, não para elevar números: um teste criado só para cobrir linhas, sem asserção sobre comportamento, não é aceito (o PIT o denuncia).

## Do risco ao tipo de teste

| Risco da mudança (análise de impacto) | Testes esperados |
|---|---|
| Regra de negócio nova ou alterada | Unitários (`*Test`) com casos de sucesso, falha e limites; BDD dos critérios de aceitação |
| Contrato HTTP ou de evento | Testes de contrato ou de integração da borda (status, corpo, `ProblemDetail`, schema); compatibilidade retroativa quando exigida |
| Persistência, migração, transação | Integração (`*IT`) contra o banco real; restrições, concorrência e rollback de transação |
| Fronteira arquitetural | ArchUnit (`*ArchitectureTest`) conforme regras de ADR aceito |
| Concorrência e idempotência | Testes com execução concorrente controlada; reprocessamento de mensagens |
| Falhas de dependência | Testes negativos: timeout, erro do serviço externo, dado inválido, retry e circuito |
| Desempenho declarado no PRD | Protocolo de medição (`performance-optimization`), não teste unitário |
| Correção de defeito | Teste de regressão que falha antes da correção (Red) |
| Refatoração | Testes existentes verdes antes e depois; caracterização se faltarem |

## Regras

- Comece pelo nível mais barato que comprova o comportamento; suba de nível só quando o risco exigir (integração para SQL e transações, não para regra pura).
- Cada critério de aceitação aponta para ao menos um teste nomeado no plano.
- Declare o que **não** será testado e por quê (fora do escopo, coberto por outro teste, risco aceito).
- Siga as convenções do ADR-0003 (`*Test`, `*IT`, `*ArchitectureTest`); os limites de cobertura e mutação não mudam por causa da tarefa.
