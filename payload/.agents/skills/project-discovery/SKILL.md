---
name: project-discovery
description: >-
  Mapeia o projeto existente antes de qualquer mudança relevante: Java e Spring Boot
  efetivos, módulos, packages, arquitetura real, persistência, mensageria, APIs,
  configuração, testes, convenções, ADRs e restrições, separando fatos, inferências,
  incógnitas e restrições. Use no início de uma mudança relevante em repositório ainda
  não mapeado ou com mapa desatualizado. Não use para requisitos de negócio
  (requirements-discovery) nem para tarefas triviais já cobertas por um mapa válido.
---

# Project Discovery

## Objetivo e limites

Entender o projeto como ele é, não como os documentos do kit sugerem. Não presuma Feature-Based, DDD ou arquitetura hexagonal: registre o que o código mostra. A skill é só leitura: não altera código, build nem configuração, e não autoriza decisões (elas seguem `architecture-decision`).

## Quando usar

- Primeira mudança relevante num repositório sem `docs/ai/project-map.md`.
- Mapa existente desatualizado: `KIT_VERSION`, `app/pom.xml` ou estrutura de módulos mudaram desde a data registrada no mapa.
- Pedido explícito de diagnóstico técnico do projeto.

**Reutilize** um mapa validado (data, revisão Git e autor registrados) em vez de refazê-lo; atualize só as seções afetadas.

## Pré-condições e entradas

- Acesso de leitura ao repositório; `bash scripts/agents/detect-stack.sh` disponível.
- Opcional: `bash scripts/agents/detect-stack.sh --effective` (Maven; pode usar rede, peça autorização em ambiente restrito) e um MCP do Spring, se habilitado ([guia](../../../docs/how-to/spring-tools-mcp.md)). O MCP fornece contexto; o código e o build prevalecem.

## Procedimento

1. **Stack efetiva**: execute `bash scripts/agents/detect-stack.sh` e registre Java, Spring Boot, parent/BOM, toolchains e a origem de cada valor. Valor não resolvido fica como incógnita, nunca como palpite.
2. **Módulos e packages**: `app/pom.xml` (`<modules>`), árvore de `src/main/java`, classe `@SpringBootApplication`, organização de packages (por feature, por camada técnica, híbrida) com exemplos de caminhos.
3. **Persistência e integração**: starters e drivers (JPA, Spring JDBC, Spring Data JDBC, R2DBC, MongoDB, MyBatis, jOOQ), migrações (Flyway, Liquibase), mensageria (Kafka, RabbitMQ, SQS), clientes HTTP, cache.
4. **Contratos**: controllers e rotas, OpenAPI, schemas de eventos, consumidores conhecidos.
5. **Configuração**: `application*.yml|properties`, perfis, variáveis de ambiente esperadas (sem copiar valores sensíveis).
6. **Testes**: suítes existentes, convenções de nome, Testcontainers, cobertura atual se houver relatório; compare com as convenções do kit (ADR-0003).
7. **Decisões e restrições**: ADRs existentes e seu status, restrições organizacionais (DevOps, segurança, plataforma), dívidas conhecidas.
8. **Divergências com o kit**: liste onde o projeto difere dos documentos propostos do kit (ADR-0001, package-conventions, regras ArchUnit). Divergência é insumo para decisão, não defeito a corrigir.

## Saída

Grave ou atualize `docs/ai/project-map.md` (ou apresente no relatório, se a tarefa não autorizar escrita) com:

| Seção | Conteúdo |
|---|---|
| Cabeçalho | Data, revisão Git (`git rev-parse --short HEAD`), `KIT_VERSION`, quem validou |
| Fatos observados | Cada item com a evidência (arquivo e linha, comando e saída) |
| Inferências | O que se deduz, com o raciocínio e o grau de confiança |
| Incógnitas | O que não foi possível determinar e como resolver |
| Restrições | Técnicas e organizacionais que limitam a mudança |
| Divergências com o kit | Itens que pedem decisão (`architecture-decision`) |

## Critérios de sucesso

- Nenhuma afirmação sem evidência ou sem marcação como inferência.
- Java e Spring Boot com origem declarada; persistência e arquitetura descritas como existem.
- Incógnitas acompanhadas de próximo passo.

## Exemplo

> Fato: Java 21 (`app/pom.xml`, propriedade `java.version`, `detect-stack.sh`). Fato: Spring Data JPA (`spring-boot-starter-data-jpa`). Inferência (média): organização por camada técnica (`controller/`, `service/`, `repository/` em `com.acme.orders`). Incógnita: consumidores do endpoint `/orders`; resolver com o time de integração. Divergência: o kit propõe Feature-Based e regras ArchUnit por feature; as regras de feature ficarão N/A até decisão.
