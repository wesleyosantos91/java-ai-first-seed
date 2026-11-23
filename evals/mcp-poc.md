# PoC: skills com e sem o MCP do Spring Tools

Protocolo para decidir, com evidência, se o plugin Spring Tools ([guia no payload](../payload/docs/how-to/spring-tools-mcp.md)) traz benefício mensurável às skills do kit. A PoC só é executada com aprovação, numa máquina de avaliação, fora do repositório do kit e sem alterar nenhum arquivo versionado de projeto.

## Preparação

- Projeto de avaliação: cópia descartável de um projeto Spring Boot real (ou das fixtures com build completo), com o kit instalado e commit de referência.
- Plugin no canal **release**, com versão anotada; Java 21+ para o language server; checksum verificado pelo instalador do plugin.
- Duas sessões por tarefa, com o mesmo provider e a mesma versão: **A** sem o plugin e **B** com o plugin.

## Tarefas (iguais em A e B)

1. `project-discovery`: mapear stack, beans, endpoints e persistência.
2. `change-impact-analysis`: impacto de renomear um campo de um endpoint.
3. `architecture-decision`: compatibilidade para um upgrade de Spring Boot de manutenção.
4. Diagnóstico: identificar um erro de configuração plantado (propriedade inválida).
5. `implementation-planning`: estratégia de testes para um endpoint novo.

## Métricas

| Critério | Como medir |
|---|---|
| Descoberta de ferramentas | O agente listou e usou as ferramentas MCP (transcrito) |
| Precisão | Itens corretos e incorretos frente a um gabarito preparado antes |
| Diagnósticos úteis | Problemas reais encontrados; falsos positivos |
| Recursos | Tempo de sessão, memória do language server, tamanho do download |
| Rede | Hosts contatados (proxy ou log de rede) |
| Offline | Comportamento sem rede após o primeiro download |
| Segurança | `bash evals/check-postconditions.sh` e `git status`: nenhuma escrita não autorizada; skills `quickfix` e `create-spring-boot-project` não usadas |
| Benefício | Diferença B − A em precisão e tempo, com as limitações registradas |

## Decisão

Recomendar o plugin ao time só se B for melhor que A em precisão sem violar nenhuma pós-condição; registrar a decisão em ADR do projeto que adotar. Resultado não executado fica como NOT RUN, nunca como benefício presumido.

## Resultados

Execução de 2026-11-23: Claude Code 2.1.330, headless (`claude -p`), plugin carregado só na sessão com `--plugin-dir` (canal release, tag `v2.4.0`; JAR de 98 MB do `cdn.spring.io` com SHA-256 verificado), language server em JDK 27. Projeto: Spring Boot 3.5.7, Java 21, JPA, `OrderController` (`GET /orders/{id}`, `POST /orders`), `OrderService`, `OrderRepository`, e dois erros plantados em `application.properties` (`spring.datasource.urll`, `server.port=abc`). A = sem plugin; B = com plugin e ferramentas do servidor MCP liberadas (edição e escrita negadas).

| Tarefa | A | B | Observações |
|---|---|---|---|
| T1 descoberta (endpoints, beans, versões) | Correto; 37 s; USD 0,24 | Correto; 24 s; USD 0,21 | B não usou o MCP nesta tarefa (respondeu pela leitura do código) |
| T2 diagnóstico de configuração | Correto (2/2); 31 s; USD 0,20 | Correto (2/2); 36 s; USD 0,21 | `getProjectDiagnostics` **não** apontou os 2 erros plantados; trouxe avisos de versão (patch 3.5.16 disponível; suporte OSS da 3.5 encerrado em 2026-06-30) que A não deu. `getProjectList` reportou `javaVersion` 27 (o JDK do language server), não o Java 21 do projeto |
| T3 impacto de renomear campo | Correto; 62 s; USD 0,32 | Correto; 57 s; USD 0,34 | B não usou o MCP |

- **Segurança:** nenhuma alteração em nenhum projeto (`git status` limpo nas 9 sessões); o plugin gravou só no próprio diretório (JAR e `boot-ls.log`). Rede: `cdn.spring.io` no download; a validação de versões consulta dados de versões do Spring.
- **Permissões:** sem liberação explícita, as ferramentas MCP são negadas em sessão não interativa (primeira rodada de B); com liberação do servidor, funcionaram.
- **Instalação:** a ponta `main` do repositório declarava a versão 2.5.0, ainda não publicada no CDN (download 404); só o canal release funcionou, como o guia recomenda.
- **Conclusão:** benefício pequeno e localizado (informação de ciclo de vida e patch do Spring Boot); nenhum ganho de precisão nas tarefas de descoberta, diagnóstico e impacto; um dado potencialmente enganoso (Java do runtime do language server). **Recomendação: manter opcional, não adotar por padrão**; se um time habilitar, liberar só `getProjectList` e `getProjectDiagnostics` e tratar o resultado como contexto a confirmar. Amostra pequena (uma sessão por braço): repetir com projetos reais antes de decidir.
