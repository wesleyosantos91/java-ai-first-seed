---
name: performance-optimization
description: >-
  Conduz engenharia de desempenho com medição antes e depois, protocolo reproduzível e
  análise de trade-offs conforme o workload: throughput, latência p95/p99, CPU, memória,
  GC, Virtual Threads, contenção, pools, SQL, índices, lotes, I/O, round-trips e
  backpressure. Use quando houver problema ou requisito de desempenho, mudança em caminho
  quente ou decisão técnica que dependa de desempenho. Não use para otimizar sem medição
  nem para declarar metas não definidas no PRD.
---

# Performance Optimization

## Princípios

- Medir antes de otimizar; registrar ambiente e metodologia (ADR-0001).
- Nenhuma tecnologia é "mais rápida" sem o workload: a resposta depende de volume, concorrência, padrão de acesso e gargalo real. Uma decisão técnica baseada em desempenho exige baseline e evidência ([architecture-decision](../architecture-decision/SKILL.md)).
- O [PRD](../../../docs/product/prd.md) só admite metas absolutas definidas por protocolo reproduzível. A [DoD, seção 6](../../../docs/engineering/definition-of-done.md) define as evidências.

## Ferramentas do harness

- `bash scripts/performance/smoke.sh`: smoke k6 **opcional** de disponibilidade contra uma aplicação já em execução (`BASE_URL`). Exige um cenário em `tests/performance/k6/smoke.js`, que o kit não cria: sem ele, o script reporta SKIP. Valida só status e health; os números do k6 **não** são medição de desempenho aprovada ([guia](../../../docs/how-to/run-tests.md#performance)).
- Cenários de carga, quando houver protocolo escrito: `tests/performance/k6/<cenário>.js` parametrizado por `BASE_URL`, com thresholds derivados do protocolo (nunca inventados), e um script em `scripts/performance/` com o contrato do harness (`0` PASS, `3` SKIP, `1` FAIL) e relatório bruto em `target/performance/`. Criar esses arquivos e qualquer infraestrutura de carga exige autorização.
- Profiling e diagnóstico: JFR, `jcmd`, logs de GC, métricas do Micrometer existentes, planos de execução do banco (`EXPLAIN ANALYZE` no PostgreSQL ou equivalente).

## Critérios por área

| Área | O que avaliar |
|---|---|
| JVM e GC | Heap, alocação, pausas, coletor e flags efetivas; versão do Java |
| Concorrência | Virtual Threads (pinning, `synchronized` em I/O, ThreadLocal), contenção de locks, tamanho de pools (HTTP, conexões, executores) |
| Banco | Round-trips, N+1, índices, planos, tamanho de resultado, lotes, UPSERT, locks e isolamento |
| I/O e integração | Timeouts, retries, backpressure, tamanho de payload, conexões persistentes |
| Escala | Comportamento sob concorrência crescente; ponto de saturação; custo |

## Procedimento

1. **Pergunta**: indicador (p95, p99, throughput, CPU, memória, alocação), cenário, workload e critério de sucesso.
2. **Ambiente**: hardware, SO, versão do Java, flags da JVM, versão da aplicação, banco e dados de carga.
3. **Baseline**: meça antes de alterar, com aquecimento e várias repetições; registre dispersão, não só a média.
4. **Diagnóstico**: profiling e planos de execução para localizar o gargalo real.
5. **Uma variável por vez**: uma otimização por medição.
6. **Nova medição**: mesmas condições do baseline.
7. **Trade-offs**: ganho versus complexidade, memória, legibilidade, operação e riscos de concorrência.
8. **Correção preservada**: `bash scripts/verify.sh` após a mudança.

## Regras de relato

- Diferencie medição observada de estimativa; não invente números nem extrapole de execuções únicas.
- Inclua comandos, scripts de carga e dados brutos ou sua localização.
- Registre o protocolo (pergunta, ambiente, baseline, repetições, critério) junto da feature, em `design.md`, antes de executar.
