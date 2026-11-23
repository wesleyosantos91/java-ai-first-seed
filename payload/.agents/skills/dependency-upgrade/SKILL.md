---
name: dependency-upgrade
description: >-
  Planeja e conduz, somente com aprovação explícita, a migração de Java, Spring Boot,
  Spring Framework, dependências Maven, plugins ou bibliotecas de infraestrutura:
  compatibilidade, mudanças incompatíveis, plano incremental, testes de regressão e
  rollback. Use quando pedirem um upgrade ou quando uma vulnerabilidade, fim de suporte ou
  requisito exigir. Não use para adicionar dependência nova (architecture-decision) nem
  para atualizar versões sem pedido.
---

# Dependency Upgrade

## Objetivo e limites

Atualizar versões de forma previsível e reversível. **Nenhum upgrade de Java ou Spring Boot acontece sem aprovação explícita**, e o agente nunca atualiza versões por iniciativa própria, nem "de carona" em outra tarefa. A skill produz primeiro o plano; a execução começa só depois da aprovação do plano.

## Quando usar

- Pedido explícito de upgrade.
- Vulnerabilidade conhecida, fim de suporte ou requisito que exija uma versão (proponha; não execute sem aprovação).

## Pré-condições e entradas

- Versões atuais com origem: `bash scripts/agents/detect-stack.sh` (e `--effective`, se a herança importar).
- Versão alvo e motivo; política de versões em [compatibilidade Java e Spring Boot](../architecture-decision/references/java-spring-compatibility.md).
- Harness verde (ou estado atual registrado) antes de começar: `bash scripts/verify.sh`.

## Procedimento

1. **Inventário**: o que muda (runtime, parent/BOM, dependências gerenciadas, plugins de build e de qualidade) e quem é afetado (devcontainer, CI do DevOps, ambientes).
2. **Compatibilidade**: notas de versão e guias de migração oficiais de cada salto (registre links e data). Para Java, confirme o suporte dos plugins que leem bytecode (JaCoCo, PIT, ArchUnit, Mockito).
3. **Mudanças incompatíveis**: APIs removidas, propriedades renomeadas, comportamento alterado, deprecações; o que exige código.
4. **Plano incremental**: um salto por vez (por exemplo, a última versão de manutenção da linha atual antes da próxima linha), cada passo com verificação e possibilidade de parar.
5. **Testes de regressão**: suítes existentes; testes adicionais nos pontos de risco identificados; mutação se o risco for alto.
6. **Rollback**: revert do commit do passo; atenção a migrações de dados ou formatos que não voltam atrás.
7. **Execução (após aprovação)**: passo a passo com `bash scripts/verify.sh` e `bash scripts/quality/mutation.sh` quando aplicável; registre o resultado real de cada passo. Limites dos quality gates não mudam.
8. **Comunicação**: o que o time de DevOps precisa saber (JDK do pipeline, imagem base); o kit não altera a CI.

## Saída

Plano (inventário, saltos, incompatibilidades, testes, rollback, riscos) para aprovação; depois, relatório por passo com comandos e resultados reais.

## Critérios de sucesso

- Nenhuma versão alterada antes da aprovação do plano.
- Cada passo verificado e reversível; incompatibilidades documentadas com fonte.

## Exemplo

> Spring Boot 3.3.5 → 3.5.x (fim de suporte da 3.3). Passo 1: 3.3.x mais recente; passo 2: 3.5.x. Incompatibilidades nas notas de versão: propriedades renomeadas no Actuator. Testes: suítes existentes e IT do endpoint de health. Rollback: revert por passo. Java 17 preservado (upgrade de Java é outra decisão).
