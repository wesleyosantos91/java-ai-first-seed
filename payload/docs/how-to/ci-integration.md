# Contrato do harness para consumo pela CI

Contrato técnico das verificações locais do kit, para quem as consome: o pipeline do time de DevOps, agentes e pessoas. **O kit não implementa CI/CD.** Workflows, runners, proteção de branch, deploy e a governança da CI são de responsabilidade exclusiva do time de DevOps ([layout do repositório](../architecture/repository-layout.md)). Este documento descreve só entradas, pré-requisitos, códigos de saída e artefatos; como e quando chamá-los é decisão do DevOps.

## Comandos

| Comando | O que verifica | Rede | Docker |
|---|---|---|---|
| `bash scripts/verify.sh` | Configuração de agentes e limites de qualidade, build, unitários, arquitetura (ArchUnit), integração e cobertura (JaCoCo) | Maven pode baixar dependências | Só se a integração usa Testcontainers |
| `bash scripts/ci.sh` | `verify.sh` mais mutação (PIT) e varredura de segredos da árvore inteira; não interativo | Idem | Idem; e para o gitleaks, se ele não estiver no PATH |
| `bash scripts/quality/mutation.sh` | Só a mutação | Idem | Não |
| `bash scripts/security/scan-secrets.sh` | Só segredos (histórico e árvore) | Imagem do gitleaks, se via Docker | Se o gitleaks não estiver no PATH |

O nome `scripts/ci.sh` é mantido por compatibilidade: ele é a **verificação completa local**, não um pipeline.

| Variável (`ci.sh`) | Efeito |
|---|---|
| `CI_MUTATION=0` | Omite a mutação (registrada como NOT RUN; resultado PARCIAL) |
| `CI_SECRETS=0` | Omite a varredura de segredos (NOT RUN) |
| `CI_REQUIRE_COMPLETE=1` | Resultado PARCIAL vira FAIL (exit 1) |
| `SKIP_INTEGRATION=1` | Repassado ao `verify.sh`; só com justificativa; resultado PARCIAL |

## Pré-requisitos

- Bash 4+ com ferramentas GNU (Linux, ou Windows com Git Bash). O macOS precisa de `coreutils`, `gnu-sed` e `findutils` antes no PATH.
- O Java declarado no `app/pom.xml` (veja `bash scripts/agents/detect-stack.sh`).
- Maven Wrapper em `app/mvnw` (padrão) ou `mvn` no PATH com `MAVEN=system` no `.harness`.
- Docker ativo quando a integração usa Testcontainers; gitleaks no PATH ou Docker para os segredos (sem os dois, a varredura é SKIP).

## Códigos de saída

| Código | Significado |
|---|---|
| `0` | PASS. Ou PARCIAL com `QUALITY_GATES=optional` no `.harness` (adoção gradual), sempre com aviso e `"result": "PARCIAL"` no JSON |
| `3` | PARCIAL com `QUALITY_GATES=required`: alguma etapa SKIP ou NOT RUN. **Não é sucesso** |
| `1` (ou outro ≠ 0 e ≠ 3) | FAIL: alguma etapa falhou, ou PARCIAL com `CI_REQUIRE_COMPLETE=1` |

SKIP e NOT RUN nunca equivalem a PASS. Um consumidor que só olha o código de saída deve tratar `3` como não aprovado.

**Execuções simultâneas:** o harness usa uma trava por repositório (`scripts/lib/lock.sh`). Uma segunda execução no mesmo diretório falha na hora e informa o PID da que está rodando.

## Resumo legível por máquina

O `verify.sh` grava `<APP_DIR>/target/harness/verify-summary.json`, e o `ci.sh` grava `<APP_DIR>/target/harness/ci-summary.json`. Em projetos, `<APP_DIR>` é `app/`.

```json
{
  "schema": 1,
  "result": "PARCIAL",
  "generated_at": "2026-11-21T21:23:20Z",
  "app_dir": "app",
  "quality_gates": "required",
  "kit_version": "2026-11-21.2a48f9b",
  "exit_code": 3,
  "steps": {
    "agents": "PASS", "build": "PASS", "unit": "SKIP", "architecture": "PASS",
    "integration": "PASS", "coverage": "SKIP", "mutation": "SKIP", "secrets": "PASS"
  },
  "reports": ["app/target/architecture-reports", "app/target/failsafe-reports"]
}
```

- `result`: `PASS`, `PARCIAL` ou `FAIL`. Cada etapa em `steps`: `PASS`, `SKIP`, `FAIL` ou `NOT RUN`.
- `exit_code`: código de saída do script que gravou o resumo (campo aditivo; o `schema` continua 1).
- `reports`: diretórios de relatório existentes, relativos à raiz: JUnit XML (`surefire-reports`, `architecture-reports`, `failsafe-reports`), JaCoCo (`site/jacoco`) e PIT (`pit-reports`).
- A chave `schema` muda só se o formato mudar de forma incompatível.

## Artefatos

| Caminho | Conteúdo |
|---|---|
| `app/target/harness/` | Resumos JSON |
| `app/target/surefire-reports/`, `architecture-reports/`, `failsafe-reports/` | JUnit XML das suítes |
| `app/target/site/jacoco/` | Cobertura (XML e HTML) |
| `app/target/pit-reports/` | Mutação (XML e HTML) |

## Limites do kit

- O kit não cria, altera nem sugere workflows, runners, proteção de branch, CODEOWNERS ou deploy. Os agentes também não: `.github/` é do DevOps (AGENTS.md, seção 8). O Claude Code bloqueia `Edit`/`Write` em `.github/**`; no Codex e no Devin valem o AGENTS.md e a revisão de código, e o `pre-commit` só avisa.
- Mudanças neste contrato (códigos, campos do JSON, caminhos) são comunicadas ao time de DevOps antes de entrar.

## Sistemas suportados

O harness roda em Bash com ferramentas GNU: **Linux** (incluindo o `.devcontainer`) e **Windows com Git Bash**. O `bash scripts/harness-tests/linux.sh` executa os testes do harness num contêiner Linux.
