# MCP do Spring (opcional): Spring Tools

Guia para habilitar, **por decisão do projeto e de cada pessoa**, o plugin de agente do [Spring Tools](https://github.com/spring-projects/spring-tools) (projeto oficial do ecossistema Spring), que expõe ferramentas MCP e skills com contexto do projeto Spring. O kit **não** instala, baixa nem configura esse plugin: nenhum arquivo versionado o ativa, o pom do app não muda e o harness (build, testes, gates) não depende dele. As skills do kit funcionam sem MCP.

Informações conferidas na documentação do plugin (`claude-plugins/spring-tools/README.md` no repositório oficial) em 2026-11-22; reconfira antes de habilitar, porque podem mudar.

## O que é

- Um plugin de agente que empacota o Spring Tools Language Server em modo standalone (sem VS Code nem JDT LS), com ferramentas MCP, skills, hooks e um subagente revisor.
- Clientes citados: Claude Code, Codex CLI, GitHub Copilot CLI e OpenCode.
- Ferramentas MCP nomeadas na documentação: `getProjectDiagnostics` e `getProjectList`. Também descreve consultas de beans, componentes, mapeamentos de requisição, classpath, versões de Java e Spring Boot e informações de suporte das versões.
- Licença do repositório: EPL-1.0.
- Requisitos: Java 21+ para executar o language server (independente do Java do app); projeto Maven ou Gradle.

## Riscos e menor privilégio

| Ponto | Fato documentado | Conduta no projeto |
|---|---|---|
| Download | O language server (cerca de 100 MB) é baixado de `cdn.spring.io` no primeiro uso, com SHA-256 verificado | Use o canal **release** (marketplace release ou a tag `vX.Y.Z`), nunca o de snapshot nem a ponta `main`, que pode declarar versão ainda não publicada; não contorne a verificação de checksum |
| Rede | A validação de versões pode consultar spring.io | Em ambiente restrito, desative conforme a documentação do plugin (`...version-validation.use-project-build-file`) |
| Escrita | A skill `quickfix` aplica correções no código; `create-spring-boot-project` gera projeto via start.spring.io | Não use essas duas skills; alterações de código seguem o fluxo do kit (plano, testes, revisão) |
| Hooks | O plugin executa hooks após `Edit`/`Write` e após comandos de shell, para atualizar o índice | Saiba que código do plugin roda a cada edição; habilite só em máquina e projeto autorizados |
| Resultados | Diagnósticos e listas vêm de análise estática | São **contexto não confiável**: confirme no código, no build e nos testes; nunca os use como evidência de PASS |

## Habilitar (Claude Code), fora do versionamento

Comandos da documentação oficial, executados por quem decidiu habilitar. Eles alteram a configuração **do usuário**, não o repositório:

```bash
claude plugin marketplace add https://cdn.spring.io/spring-tools/release/claude-plugins/marketplace.json
claude plugin install spring-tools@spring-tools-marketplace
```

Não adicione o plugin, marketplace ou servidor MCP ao `.claude/settings.json` versionado: a escolha é pessoal ou do time, registrada em `.claude/settings.local.json` (ignorado pelo Git) ou na configuração do usuário. Para Codex e outros clientes, siga a mesma documentação oficial; o kit não fornece adaptador.

## Uso pelas skills

| Skill | Contexto útil do MCP | Continua obrigatório |
|---|---|---|
| `project-discovery` | Lista de projetos, versões de Java e Boot, beans, endpoints | `detect-stack.sh`, leitura do código |
| `change-impact-analysis` | Componentes e endpoints afetados | Busca no código e consumidores reais |
| `architecture-decision` | Informações de versões e suporte | Documentação oficial com data, evidência |
| `implementation-planning` (testes) | Capacidades de teste do framework | Estratégia de testes do kit |
| `dependency-upgrade` | Suporte e compatibilidade de versões | Notas de versão oficiais, harness verde |

## Avaliação antes de adotar no time

Antes de recomendar o plugin ao time, execute a avaliação comparativa com e sem MCP descrita no kit (`evals/mcp-poc.md` no repositório do instalador): mesmas tarefas, medição de precisão, tempo, recursos, rede, escritas não autorizadas e comportamento offline. Sem essa evidência, a adoção é experimental.

Resultado da PoC do kit (2026-11-23, plugin 2.4.0, amostra pequena): mesma precisão com e sem o plugin em descoberta, diagnóstico de configuração e impacto; o diagnóstico MCP não apontou propriedades inválidas plantadas, mas trouxe avisos úteis de patch e fim de suporte do Spring Boot; a lista de projetos reportou como `javaVersion` o JDK do language server, não o Java do projeto. Nenhuma escrita no projeto. Recomendação: opcional, não padrão.

Para avaliar sem alterar a configuração do usuário, carregue o plugin só na sessão: `claude --plugin-dir <checkout da tag release>/claude-plugins/spring-tools`. Em sessão não interativa, as ferramentas MCP só funcionam se liberadas explicitamente (por exemplo, `--allowedTools mcp__plugin_spring-tools_spring-tools-mcp__getProjectList,mcp__plugin_spring-tools_spring-tools-mcp__getProjectDiagnostics`).

## Alternativa avaliada e não recomendada

`KEEPEE/java-spring-mcp` (comunitário, consulta de documentação Java e Spring): em 2026-11-22 não tinha releases nem histórico de manutenção visível, instalava a partir da ponta do Git (versão não fixada) e fazia scraping de vários sites em tempo de execução. Não é recomendado para adoção corporativa sem auditoria própria.
