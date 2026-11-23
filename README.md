# Java AI-First Seed

Instalador da configuração AI-First para monorepos Java com agentes de IA (Codex, Claude Code, Devin): instruções e skills dos agentes, harness de verificação, quality gates, PRD guiado e ADRs propostos.

Ele **não cria projeto**. Você aponta o diretório de um monorepo que já existe, com o projeto Maven em `app/`, e o instalador adiciona só a configuração na raiz.

## Uso

```bash
git clone https://github.com/wesleyosantos91/java-ai-first-seed.git
bash java-ai-first-seed/install.sh /caminho/do/monorepo
```

O instalador:

- **detecta** em `app/` (só leitura) a classe `@SpringBootApplication` (também em módulos), o pacote, o Java declarado (`maven.compiler.release`, `<release>` do compiler plugin ou `java.version`), o Spring Boot (parent oficial ou BOM), a persistência, os starters e o nome do projeto. Valor herdado que o pom não resolve vira campo a preencher, nunca palpite; nada muda no runtime do app (upgrade de Java ou Spring Boot exige aprovação);
- **grava só configuração na raiz:** `AGENTS.md`, `CLAUDE.md`, `.agents/`, `.claude/`, `.codex/`, `docs/`, `scripts/`, `.harness` e arquivos de editor e Git;
- **não altera** `app/`, `infra/`, `tests/`, `.github/` nem o `README.md` do projeto, e **nunca sobrescreve** arquivo do projeto: se um arquivo de configuração já existe e é diferente, a versão do kit fica ao lado como `<arquivo>.kit`. Um `<arquivo>.kit` que você já está mesclando não é tocado;
- verifica tudo numa área temporária, planeja cada arquivo e recusa symlinks ou conflitos de tipo **antes** de gravar. A gravação é atômica por arquivo, com journal: se algo falhar, o projeto é restaurado. No fim, valida o projeto com as cópias do kit, sem executar scripts do projeto.

| Opção | Efeito |
|---|---|
| `--dry-run` | Mostra o plano arquivo a arquivo (novo, atualizado, conflito, mescla pendente, órfão), sem gravar |
| `--allow-dirty` | Permite atualizar no lugar arquivo com alterações não commitadas no Git (por padrão, recusa) |
| `--main <pacote.Classe>` | Escolhe a classe principal quando o app tem mais de uma |
| `--recover` | Desfaz uma instalação interrompida (deixada em `.kit-install.journal`) |

Retornos: `0` aplicado e verificado no projeto; `2` aplicado com pendências (conflitos `.kit` ou `check-config` reprovado no projeto); `1` erro, com o projeto restaurado.

Nada deste repositório é copiado para o projeto: ele continua sem depender do seed.

## Estrutura esperada do projeto

```text
<monorepo>/
├── app/        projeto Maven (app/pom.xml), obrigatório
├── infra/      infraestrutura (por exemplo, Terraform), opcional
├── tests/      testes fora do app, opcional
└── .github/    CI do time de DevOps, opcional
```

## Depois de instalar

| Quem | O quê |
|---|---|
| Negócio | PRD em `docs/product/prd.md` (cada seção diz quem preenche) e propósito no `AGENTS.md` §1 |
| Engenharia | Seção "Revisão neste projeto" dos ADRs 0001 a 0003, persistência no `AGENTS.md` §2 e licença no `CONTRIBUTING.md` |
| Engenharia | Quality gates: blocos de pom e testes prontos no fim de `docs/how-to/enable-quality-gates.md` |

```bash
bash scripts/agents/list-pending.sh             # o que falta preencher, por responsável
bash scripts/git/install-hooks.sh               # hooks de commit (exige repositório Git)
bash scripts/verify.sh                          # agentes, build e testes do app/
bash scripts/quality/enable-gates.sh --dry-run  # ativação dos quality gates (--apply com autorização)
bash scripts/ci.sh                              # ponto de entrada para a CI do time de DevOps
```

Até os quality gates serem configurados no `app/pom.xml`, eles aparecem como SKIP com o motivo, e o `verify.sh` termina PARCIAL. É o esperado.

## Atualizar e verificar o instalador

- **Atualizar um projeto:** rode o `install.sh` de novo, a partir de um clone atualizado. O `.harness` é mesclado (o `QUALITY_GATES` do projeto é preservado, e o `KIT_VERSION` passa a ser o do arquivo `VERSION`). Pelo `.kit-manifest` (SHA-256; registros SHA-1 antigos continuam aceitos), arquivo ainda idêntico ao instalado é atualizado no lugar, e só o que o projeto alterou recebe a versão nova ao lado, como `<arquivo>.kit`. Arquivo que o kit deixou de fornecer é listado como órfão e nunca apagado. A saída mostra a versão anterior e a nova. Adicione `*.kit` e `.kit-install.*` ao versionamento ignorado (o `.gitignore` do kit já traz essas linhas).
- **Verificar o instalador:** `bash selftest.sh` (sem rede, Maven nem Docker; cerca de 10 minutos no Git Bash) instala em monorepos temporários e cobre: só configuração gravada, `check-config` e harness no projeto, idempotência, atualização no lugar, conflitos e mescla pendente, symlinks, conflito de tipo, falha no meio da gravação (rollback), `--recover`, árvore suja, nome com caracteres especiais, órfãos, scripts do projeto não executados e a matriz de compatibilidade de `tests/fixtures/` (Java 17/21/25, JPA, Spring JDBC, Spring Data JDBC, BOM, parent corporativo, multimódulo).
- **Ponta a ponta com Maven real:** `bash selftest.sh --maven` (exige JDK, `mvn` no PATH e rede; cerca de 2 minutos) instala na fixture `new-java25-nodb` com `MAVEN=system`, aplica os gates com `enable-gates.sh --apply` e roda `verify.sh` e `mutation.sh` de verdade, além de provar que reduzir um limite no pom reprova o `verify.sh`.
- **Avaliação dos agentes:** `evals/` traz os cenários das skills e os cenários adversariais (reduzir cobertura, alterar ADR aceito, declarar PASS sem execução, alterar `.github/` ou permissões, upgrade de Java, troca de persistência), o verificador determinístico `bash evals/check-postconditions.sh <projeto> <revisão>` e o protocolo da PoC do MCP. A execução nos providers é manual; resultados não executados ficam como NOT RUN.
- **Sistemas:** Linux e Windows com Git Bash. O macOS precisa de Bash 4+ e das ferramentas GNU (`bash`, `coreutils`, `gnu-sed`, `findutils`); o instalador confere antes de ler o projeto.

## Origem

Bootstrap a partir do exportador do kit (`--seed`) do repositório de referência [java-ai-engineering-lab](https://github.com/wesleyosantos91/java-ai-engineering-lab). **Desde o instalador, este repositório é a fonte da verdade** de `install.sh`, `lib/`, `payload/` e `templates/`: correções são feitas aqui. A regeneração automática a partir do lab está suspensa; uma sincronização vinda de lá só entra manualmente, revisada e passando no `selftest.sh`.

## Licença

[Apache License 2.0](LICENSE).
