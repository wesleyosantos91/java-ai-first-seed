# Persistência: JDBC, Spring Data JDBC e Spring Data JPA

Referência da skill `architecture-decision` para decisões de acesso a dados relacionais. Não há tecnologia padrão do kit: a escolha é contextual, parte do que o projeto já usa e é registrada em ADR. Confirme detalhes de versão na documentação oficial do Spring da versão em uso (`bash scripts/agents/detect-stack.sh`).

## Alternativas

| Alternativa | Modelo | Bom encaixe | Cuidados |
|---|---|---|---|
| Spring JDBC (`JdbcClient`, `JdbcTemplate`, `NamedParameterJdbcTemplate`) | SQL explícito, mapeamento manual | SQL especializado (UPSERT, CTE, window functions), lotes, relatórios, controle fino de round-trips e locks | Mais código de mapeamento; disciplina de SQL e testes de integração |
| Spring Data JDBC | Agregados DDD simples, repositórios derivados, sem lazy loading nem cache de primeiro nível | Agregados pequenos e bem delimitados, gravação do agregado inteiro | Sem lazy loading: carrega o agregado inteiro; relacionamentos entre agregados por id; atualizações de coleções podem regravar filhos |
| Spring Data JPA / Hibernate | ORM com contexto de persistência, dirty checking, lazy loading | Modelos ricos com muitos relacionamentos, CRUD extenso, produtividade em times experientes em JPA | N+1, `LazyInitializationException`, flush implícito, consumo de memória do contexto, SQL gerado a revisar |
| Tecnologia já existente | — | Coerência, conhecimento do time, menor custo de mudança | Avalie sempre como alternativa "manter" |

## Critérios mínimos

Avalie cada alternativa contra os critérios abaixo, com evidência ou marcação de hipótese:

- **Modelo de domínio**: agregados, relacionamentos, cardinalidade, profundidade do grafo carregado por operação.
- **Carga**: volume, throughput, latência p95/p99 exigida, concorrência, operações em lote, UPSERT.
- **SQL**: necessidade de SQL especializado ou dependente do banco; revisão e testes do SQL gerado.
- **Transações**: fronteiras, isolamento, locks (otimista com versão, pessimista), duração.
- **Eficiência**: N+1, round-trips, tamanho do resultado, memória do contexto de persistência.
- **Operação**: observabilidade das queries (métricas, logs com cardinalidade controlada), diagnóstico de lentidão.
- **Engenharia**: produtividade, curva de aprendizado do time, testabilidade (Testcontainers com o banco real), manutenção.
- **Legado**: compatibilidade com o que existe, custo e risco de migração, convivência de duas tecnologias.

## Quando pedir PoC ou benchmark

- A justificativa principal é desempenho (latência, throughput, memória).
- O volume ou o padrão de acesso é incomum (lotes grandes, grafos profundos, alta concorrência na mesma linha).
- A alternativa não é usada hoje no projeto.

Protocolo mínimo: pergunta, dados representativos, ambiente registrado, aquecimento, repetições, métricas (p95, p99, throughput, CPU, memória, número de queries) e critério de aceite definido antes. Não extrapole de execução única.

## Convivência e regras automatizadas

- Duas tecnologias no mesmo projeto são aceitáveis quando cada uma tem escopo claro (por exemplo, JPA no CRUD e JdbcClient em relatórios), registrado no ADR.
- Regras ArchUnit que **proíbem** uma tecnologia só entram depois do ADR aceito e refletem exatamente o escopo decidido. Exemplo, a aplicar com autorização em `ArchitectureTest`, depois de um ADR que adote só JDBC:

```java
@Test
void persistenceFollowsAdr00NN() {
	noClasses().that().resideInAPackage(BASE + "..")
			.should().dependOnClassesThat().resideInAnyPackage(
					"jakarta.persistence..", "org.springframework.data.jpa..", "org.hibernate..")
			.because("ADR-00NN: persistência com Spring JDBC")
			.check(CLASSES);
}
```

- Nunca adicione, remova ou afrouxe uma regra arquitetural para obter PASS.
