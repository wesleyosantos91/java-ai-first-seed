---
name: observability-design
description: >-
  Projeta a observabilidade de um fluxo de negócio ou técnico: métricas (RED, USE, sinais
  de ouro), logs estruturados, traces e correlação (Micrometer, OpenTelemetry), SLIs e
  SLOs, alertas, cardinalidade e custo de telemetria, preservando a solução já usada no
  projeto. Use ao criar ou alterar fluxo crítico, definir SLO ou alerta, ou diagnosticar
  degradação sem sinal suficiente. Não use para medir desempenho (performance-optimization).
---

# Observability Design

## Objetivo e limites

Garantir que um fluxo possa ser operado: saber se está saudável, por que degradou e quem foi afetado. A skill é neutra quanto a fornecedor: **preserve o backend e a instrumentação que o projeto já usa** (registre-os com `project-discovery`). Não introduza Datadog, Prometheus, Grafana, um agente ou uma biblioteca nova como dependência universal; uma ferramenta nova é decisão de `architecture-decision`.

## Quando usar

- Fluxo novo ou alterado marcado como crítico (PRD ou `change-impact-analysis`).
- Definição ou revisão de SLI, SLO ou alerta.
- Incidente ou degradação em que faltou sinal para diagnosticar (`systematic-debugging`).

## Pré-condições e entradas

- Mapa do projeto: Actuator, Micrometer, OpenTelemetry, formato de log e backend existentes.
- Descrição do fluxo e dos seus usuários; metas de negócio (PRD) quando houver.

## Procedimento

1. **Pergunta operacional**: o que alguém de plantão precisa responder sobre este fluxo.
2. **Sinais**: para serviços, RED (taxa, erros, duração); para recursos (pools, filas, threads), USE (utilização, saturação, erros); sintetize nos sinais de ouro (latência, tráfego, erros, saturação).
3. **Métricas**: nome, tipo (contador, timer, gauge, distribution summary), unidade e tags. Cardinalidade: nunca tags com ids, e-mails ou valores livres; estime o número de séries.
4. **Logs**: estruturados, com correlação (trace id, span id), nível adequado, sem dados pessoais ou segredos; eventos de negócio relevantes como log ou métrica, não ambos sem motivo.
5. **Traces**: spans nas fronteiras (HTTP, mensageria, banco, chamadas externas), propagação de contexto em execução assíncrona e Virtual Threads, amostragem.
6. **SLI e SLO**: SLI calculável a partir de um sinal existente; SLO com janela e meta acordadas com o negócio (nunca inventadas); orçamento de erro.
7. **Alertas**: sobre sintomas do SLO (burn rate), não sobre causas isoladas; cada alerta com ação esperada e runbook.
8. **Custo**: volume de séries, logs e spans; retenção; o que pode ser amostrado.
9. **Verificação**: teste que comprova a emissão das métricas e da correlação (por exemplo, `MeterRegistry` simples em teste de integração) e o resultado do harness.

## Saída

Tabela de sinais (nome, tipo, tags, cardinalidade estimada, origem), SLIs e SLOs propostos (com aprovação pendente), alertas com ação, impactos de custo e testes que comprovam a instrumentação.

## Critérios de sucesso

- Instrumentação usa a solução existente do projeto.
- Nenhuma tag de alta cardinalidade nem dado sensível em telemetria.
- SLOs sem meta inventada; alertas acionáveis.

## Exemplo

> Fluxo: confirmação de pagamento. RED via `http.server.requests` (já existente) filtrado por rota; métrica nova `payment.confirmations` (contador, tags `outcome` e `method`, cerca de 12 séries). Log estruturado no erro do gateway com trace id. SLI: proporção de confirmações sem erro em 5 min; SLO a definir com o negócio. Alerta por burn rate do SLO, com runbook.
