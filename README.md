# Java AI-First Seed

Instalador da configuração AI-First para monorepos Java com agentes de IA (Codex, Claude Code, Devin): instruções e skills dos agentes, harness de verificação, quality gates, PRD guiado e ADRs propostos.

Ele **não cria projeto**. Você aponta o diretório de um monorepo que já existe, com o projeto Maven em `app/`, e o instalador adiciona só a configuração na raiz.

## Uso

```bash
git clone https://github.com/wesleyosantos91/java-ai-first-seed.git
bash java-ai-first-seed/install.sh /caminho/do/monorepo
```

O instalador:

- **detecta** em `app/` (só leitura) a classe `@SpringBootApplication`, o pacote, o Java, o Spring Boot, os starters e o nome do projeto;
- **grava só configuração na raiz:** `AGENTS.md`, `CLAUDE.md`, `.agents/`, `.claude/`, `.codex/`, `docs/`, `scripts/`, `.harness` e arquivos de editor e Git;
- **não altera** `app/`, `infra/`, `tests/`, `.github/` nem o `README.md` do projeto. Se um arquivo de configuração já existe e é diferente, a versão do kit fica ao lado como `<arquivo>.kit`;
- verifica tudo numa área temporária antes de gravar. Se algo falhar, o projeto não é alterado.

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

- **Atualizar um projeto:** rode o `install.sh` de novo, a partir de um clone atualizado. O `.harness` é mesclado (o `QUALITY_GATES` do projeto é preservado, e o `KIT_VERSION` passa a ser o do arquivo `VERSION`). Pelo `.kit-manifest`, arquivo ainda idêntico ao instalado é atualizado no lugar, e só o que o projeto alterou recebe a versão nova ao lado, como `<arquivo>.kit`. A saída mostra a versão anterior e a nova.
- **Verificar o instalador:** `bash selftest.sh` instala num monorepo temporário e confere que só a configuração foi gravada, que ela passa no `check-config` e no harness do projeto e que a reinstalação preserva o `.harness`. Não usa rede, Maven nem Docker.
- **Sistemas:** Linux e Windows com Git Bash. O macOS precisa das ferramentas GNU (`coreutils`, `gnu-sed`, `findutils`).

## Origem

Gerado pelo exportador do kit (`--seed`) do repositório de referência [java-ai-engineering-lab](https://github.com/wesleyosantos91/java-ai-engineering-lab). Correções são feitas lá e chegam aqui por regeneração.

## Licença

[Apache License 2.0](LICENSE).
