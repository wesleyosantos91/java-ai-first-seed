---
name: architecture-guard
description: >-
  Verifica se código novo ou alterado respeita a arquitetura aprovada do projeto (ADRs
  aceitos, convenções de packages e regras de dependência) e identifica quando uma
  mudança exige decisão arquitetural (ADR). Use ao planejar, implementar ou revisar
  código Java. Não use para tomar decisões novas (architecture-decision), aprovar ADRs
  nem alterar padrões aprovados unilateralmente.
---

# Architecture Guard

## Fontes de verdade

- ADRs com status `Aceita` ([índice](../../../docs/architecture/adr/README.md)); enquanto a seção "Revisão neste projeto" de um ADR do kit não estiver decidida, ele é **proposta**, não regra.
- [Convenções de packages](../../../docs/architecture/package-conventions.md) e [regras de dependência](../../../docs/architecture/dependency-rules.md), na medida em que o projeto as adotou.
- O mapa do projeto (`docs/ai/project-map.md`, skill `project-discovery`): a arquitetura real prevalece sobre a proposta do kit até que um ADR decida migrar.

Esta skill resume os pontos de verificação; em divergência, os documentos aceitos prevalecem.

## Verificações

1. **Localização**: o código de negócio está na organização adotada (por feature, por camada ou híbrida, conforme o ADR e o mapa); `shared` ou equivalente contém apenas componentes genuinamente transversais.
2. **Direção das dependências**: conforme as regras adotadas (na proposta do kit: `api → service → domain`, `service → persistence`, `persistence → domain`). Nenhuma dependência no sentido inverso nem ciclo.
3. **Domínio**: regras de negócio sem dependência de transporte (HTTP), mensageria ou detalhes de persistência, na medida decidida pelo ADR.
4. **Controllers finos**: sem SQL, acesso direto a repository, regra de negócio ou coordenação transacional de múltiplas operações.
5. **Persistência**: com a tecnologia aprovada no ADR (JDBC, Spring Data JDBC, JPA ou outra); sem decisão de negócio; sem introduzir outra tecnologia sem decisão.
6. **Entre features ou módulos**: nenhum acesso ao repository de outra feature ou módulo; comunicação por contrato explícito.
7. **YAGNI**: nenhum package vazio, interface com implementação única sem motivo, nem Ports, Use Cases ou Adapters por padrão.

## Verificação prática

```bash
bash scripts/test/architecture.sh
```

As regras estão em `src/test/java/com/example/kitapp/architecture/ArchitectureTest.java` e cobrem as fronteiras da organização Feature-Based proposta pelo kit. Em projetos com outra organização, as regras por feature ficam N/A (não aprovação) até que um ADR decida as regras do projeto. Regras de **tecnologia** (por exemplo, proibir JPA) só existem depois de um ADR aceito que as defina ([referência](../architecture-decision/references/persistence.md)).

Continuam exigindo revisão: a localização (1), a lista completa de dependências permitidas (2), a ausência de regra de negócio e de coordenação transacional em controllers (4), decisões de negócio na persistência (5) e o YAGNI (7). Declare-as como revisão manual, não como validação automática. Ao identificar nova restrição documentada e aceita, siga a [skill quality-gates](../quality-gates/SKILL.md) para adicionar a regra.

## Quando parar

Se a solução exigir violar uma regra aceita, trocar a tecnologia de persistência, introduzir biblioteca estrutural ou mudar fronteiras, pare: descreva a contradição e acione [architecture-decision](../architecture-decision/SKILL.md). Um novo ADR só é redigido com autorização e nunca é aceito pelo agente. Nunca adicione, remova ou afrouxe uma regra ArchUnit para obter PASS.
