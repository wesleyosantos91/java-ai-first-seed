---
name: architecture-decision
description: >-
  Conduz decisões técnicas fundamentadas: alternativas, requisitos funcionais e não
  funcionais, trade-offs, restrições, custo operacional, segurança, reversibilidade,
  evidências e critérios de aprovação, com ADR quando necessário (por exemplo, JDBC x
  Spring Data JDBC x JPA, Virtual Threads x WebFlux, Kafka x SQS, cache). Use quando uma
  mudança exigir escolher entre alternativas ou contrariar um ADR. Não use para verificar
  conformidade com decisões já aceitas (architecture-guard).
---

# Architecture Decision

## Objetivo e limites

Chegar a uma decisão contextual, justificada por requisitos e evidências, nunca por preferência tecnológica. O agente **propõe**; a decisão é aceita por uma pessoa responsável, registrada em ADR com status `Aceita`. O agente nunca marca um ADR como aceito nem altera um ADR aceito: mudar uma decisão é registrar um novo ADR que a substitui.

## Quando usar

- A mudança exige escolher tecnologia, padrão ou estrutura sem decisão vigente.
- A solução contraria um ADR aceito ou uma regra arquitetural (`architecture-guard` mandou parar).
- `change-impact-analysis` classificou o risco como alto por causa de uma escolha técnica.

Não use para escolhas locais e reversíveis sem efeito fora de uma classe (nome de método, estrutura interna de um teste).

## Pré-condições e entradas

- Mapa do projeto (`project-discovery`): a tecnologia já existente é uma alternativa obrigatória e o ponto de partida.
- Requisitos: PRD, spec, metas não funcionais (latência, throughput, volume, disponibilidade), restrições (time, plataforma, licença, operação).
- ADRs vigentes ([índice](../../../docs/architecture/adr/README.md)).

## Procedimento

1. **Pergunta de decisão**: uma frase com o que precisa ser decidido e por quê agora.
2. **Critérios**: derivados dos requisitos, com peso. Inclua sempre: aderência ao que o projeto já usa, custo de migração, operação, segurança, testabilidade, manutenção, reversibilidade.
3. **Alternativas**: no mínimo a situação atual (manter) e duas opções viáveis. Descarte explícito do que for inviável, com motivo.
4. **Avaliação**: cada alternativa contra cada critério, com evidência (documentação oficial com data, medição, PoC, experiência registrada no projeto). Sem evidência, marque como hipótese.
5. **Reversibilidade**: decisão reversível (barata de desfazer) admite experimento; irreversível ou cara exige evidência mais forte e aprovação explícita.
6. **Evidência adicional**: quando a decisão depende de desempenho ou de comportamento não documentado, proponha PoC ou benchmark com protocolo (pergunta, ambiente, carga, critério de aceite) antes da decisão definitiva (`performance-optimization`).
7. **Recomendação**: alternativa recomendada, riscos residuais, condições para revisitar e o que muda nas regras automatizadas (por exemplo, uma regra ArchUnit que só entra depois do ADR aceito).
8. **Registro**: com autorização, redija um ADR a partir do [template](../../../docs/architecture/adr/TEMPLATE.md) com status `Proposta`, e peça a aprovação.

## Referências sob demanda

- [Persistência: JDBC, Spring Data JDBC e Spring Data JPA](references/persistence.md).
- [Compatibilidade Java e Spring Boot](references/java-spring-compatibility.md).

## Saída

Pergunta, critérios com peso, matriz alternativas × critérios com evidências, recomendação, alternativas rejeitadas e por quê, riscos, reversibilidade, evidência pendente (PoC) e o ADR proposto (ou o motivo para não haver ADR).

## Critérios de sucesso

- A tecnologia existente foi avaliada como alternativa, não ignorada.
- Cada afirmação de vantagem tem evidência ou está marcada como hipótese.
- Nada foi implementado com base em decisão ainda não aceita.

## Exemplo

> Pergunta: como persistir o agregado `Pedido` (5 tabelas, escrita em lote de 10 mil itens por minuto)? Atual: Spring Data JPA no restante do projeto. Alternativas: manter JPA com batch e `@BatchSize`; Spring Data JDBC; JdbcClient com SQL explícito e UPSERT. Hipótese: JdbcClient reduz round-trips no lote; exige PoC com o volume real antes da decisão. Recomendação provisória: manter JPA no CRUD e avaliar JdbcClient só no lote, com ADR proposto após a PoC.
