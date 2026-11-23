# Análise de incidentes

Referência da skill `systematic-debugging` para investigações técnicas de incidentes. O objetivo é aprender e prevenir, não atribuir culpa. O agente analisa evidências fornecidas ou acessíveis com autorização; não acessa ambientes de produção, não executa ações de mitigação e não altera configuração sem autorização explícita.

## Estrutura

1. **Resumo**: o que aconteceu, impacto e estado atual (mitigado, resolvido, em andamento).
2. **Linha do tempo**: eventos com horário (com fuso), fonte de cada um (log, métrica, deploy, alerta, relato humano) e o que se sabia em cada momento.
3. **Evidências**: logs, métricas, traces, diffs e deploys, com referência verificável. Marque lacunas (sinal ausente, retenção expirada).
4. **Hipóteses**: cada uma falsificável, com evidência a favor e contra e o teste que a confirmaria ou refutaria.
5. **Causa raiz**: só a hipótese **demonstrada** (reprodução, teste, evidência causal). Coincidência temporal ou correlação em gráfico não bastam; sem demonstração, declare "causa provável" com o grau de confiança.
6. **Fatores contribuintes**: condições que permitiram ou ampliaram o impacto (falta de alerta, timeout ausente, teste inexistente, processo).
7. **Impacto**: usuários, dados, duração, SLO consumido; números só de fonte verificável.
8. **Mitigação e correção**: o que foi feito e o que falta; a correção de código segue o fluxo normal (teste de regressão, `verify.sh`).
9. **Prevenção**: ações com responsável sugerido e prioridade; lacunas de observabilidade acionam `observability-design`.

## Regras

- Diferencie fato, hipótese e causa demonstrada em todo o relatório.
- Não invente horários, métricas ou impacto.
- Dados pessoais e segredos não entram no relatório.
