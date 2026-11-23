# Compatibilidade Java e Spring Boot

Referência das skills `architecture-decision`, `project-discovery` e `dependency-upgrade`. Os valores abaixo são um ponto de partida para a conversa, **não** a fonte da verdade: confirme na página oficial de requisitos de sistema da versão exata do Spring Boot (documentação de referência, seção "System Requirements") e nas notas de versão, registrando a data da consulta.

## Política do kit

| Situação | Conduta |
|---|---|
| Projeto novo | Java 25 (LTS) como baseline |
| Projeto existente com Java 25 | Preservar |
| Projeto existente com Java 17 ou 21 (LTS) | Preservar; avaliar migração com `dependency-upgrade`, só com aprovação |
| Projeto com Java não LTS | Identificar o risco (suporte curto) e recomendar avaliação; não alterar |
| Upgrade de Java ou de Spring Boot | Sempre com aprovação explícita, plano e testes de regressão |

O instalador e o harness nunca alteram o runtime do app: `detect-stack.sh` e `setup.sh` só informam e avisam.

## Pontos de atenção (confirmar na documentação oficial)

- Spring Boot 3.x e 4.x exigem no mínimo Java 17; o suporte às versões mais novas de Java depende da versão de manutenção do Boot.
- Plugins de build e ferramentas leem o class file do Java alvo: confira o suporte de JaCoCo, PIT, ArchUnit, Mockito e Byte Buddy à versão de Java do app antes de declarar compatibilidade.
- Toolchains Maven: o JDK que compila pode diferir do JDK no PATH; use `detect-stack.sh --effective` e `mvn -v` para registrar o efetivo.
- Virtual Threads (Java 21+) e outras capacidades da plataforma são decisões arquiteturais (`architecture-decision`), não efeitos automáticos do upgrade.
