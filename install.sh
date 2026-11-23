#!/usr/bin/env bash
set -Eeuo pipefail

# Instalador do kit AI-First: aplica a configuração (instruções e skills dos agentes, harness,
# PRD guiado, ADRs propostos) na raiz de um monorepo existente, cujo projeto Maven está em app/.
#
# Uso: bash install.sh [--dry-run] [--allow-dirty] [--main <pacote.Classe>] <diretório do projeto>
#      bash install.sh --recover <diretório do projeto>
#   --dry-run      mostra o plano (arquivo a arquivo) sem gravar nada
#   --allow-dirty  permite atualizar no lugar arquivos com alterações não commitadas no Git
#   --main         escolhe a classe @SpringBootApplication quando o app tem mais de uma
#   --recover      desfaz uma instalação interrompida (journal .kit-install.journal)
#
# - Detecta em app/ (só leitura, payload/scripts/lib/detect.sh): classe @SpringBootApplication
#   (também em módulos), pacote, Java efetivo declarado (maven.compiler.release, compiler plugin,
#   java.version), Spring Boot (parent oficial ou BOM), persistência, starters e nome do projeto.
#   Valor herdado e não resolvível no pom fica como campo a preencher, nunca como palpite.
#   Nada é alterado no runtime do app: upgrades de Java ou Spring Boot exigem aprovação.
# - Nunca grava em app/, infra/, tests/, .github/ nem no README.md do projeto. Arquivo do projeto
#   nunca é sobrescrito: só o que o kit gravou e o projeto não alterou é atualizado no lugar
#   (.kit-manifest); o resto recebe a versão do kit como <arquivo>.kit. Um <arquivo>.kit existente
#   e diferente (mescla em andamento) não é tocado.
# - Monta tudo numa área temporária e roda o check-config nela; depois planeja cada arquivo e
#   recusa symlinks e conflitos de tipo antes de gravar. A gravação é atômica por arquivo, com
#   journal: qualquer falha desfaz tudo (rollback). Não executa scripts do projeto.
# - Nada deste instalador (install.sh, payload/, templates/, lib/) é copiado para o projeto.
# Retornos: 0 = configuração aplicada e verificada no projeto; 2 = aplicada, com conflitos .kit
#           pendentes ou verificação do projeto reprovada; 1 = erro (projeto restaurado).

KIT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
PAYLOAD="${KIT_DIR}/payload"
TEMPLATES="${KIT_DIR}/templates"

usage() { echo "Uso: bash install.sh [--dry-run] [--allow-dirty] [--main <pacote.Classe>] <diretório do projeto> | --recover <diretório>" >&2; exit 1; }
dry_run=0 allow_dirty=0 recover=0 target_arg='' main_fqcn=''
while (( $# > 0 )); do
  case "$1" in
    --dry-run) dry_run=1 ;;
    --main)
      (( $# >= 2 )) && [[ "$2" =~ ^[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*)+\.[A-Za-z_][A-Za-z0-9_]*$ ]] || usage
      main_fqcn="$2"; shift ;;
    --allow-dirty) allow_dirty=1 ;;
    --recover) recover=1 ;;
    -*) usage ;;
    *) [[ -z "${target_arg}" ]] || usage; target_arg="$1" ;;
  esac
  shift
done
[[ -n "${target_arg}" ]] || usage
(( ! recover || (dry_run == 0 && allow_dirty == 0) )) || usage

# 0. Pré-requisitos, antes de qualquer leitura do projeto: Bash 4+ (arrays associativos) e
#    ferramentas GNU (sed -i, find -print0, sort -z, sha256sum, tac).
(( BASH_VERSINFO[0] >= 4 )) || { echo "[FAIL] Bash 4 ou superior é necessário (encontrado ${BASH_VERSION})." >&2; exit 1; }
missing_tools=()
for tool in awk cmp cp find grep mkdir mktemp mv sed sha1sum sha256sum sort tac; do
  command -v "${tool}" >/dev/null 2>&1 || missing_tools+=("${tool}")
done
sed --version >/dev/null 2>&1 || missing_tools+=('sed (GNU)')
printf 'a\0' | sort -z >/dev/null 2>&1 || missing_tools+=('sort -z (GNU)')
(( ${#missing_tools[@]} == 0 )) || {
  echo "[FAIL] Ferramentas ausentes: ${missing_tools[*]}. No macOS, instale coreutils, gnu-sed e findutils." >&2; exit 1; }

[[ -d "${PAYLOAD}" && -d "${TEMPLATES}" && -s "${KIT_DIR}/VERSION" ]] || {
  echo "[FAIL] Kit incompleto em ${KIT_DIR} (payload/, templates/ ou VERSION ausente)." >&2; exit 1; }
source "${KIT_DIR}/lib/rename.sh"
source "${KIT_DIR}/lib/fsafe.sh"
source "${KIT_DIR}/lib/manifest.sh"
KIT_VERSION="$(head -n 1 "${KIT_DIR}/VERSION" | tr -d '[:space:]')"
[[ -d "${target_arg}" ]] || { echo "[FAIL] Diretório do projeto não encontrado: ${target_arg}" >&2; exit 1; }
DEST="$(cd -- "${target_arg}" && pwd -P)"
case "${DEST}/" in
  "${KIT_DIR}/"*) echo "[FAIL] O projeto não pode estar dentro do kit: ${DEST}" >&2; exit 1 ;;
esac

# Estado de instalação no projeto (fora do versionamento pelo .gitignore do kit).
MANIFEST=.kit-manifest
JOURNAL="${DEST}/.kit-install.journal"
BACKUP="${DEST}/.kit-install.backup"
LOCK="${DEST}/.kit-install.lock"
for rel in "${MANIFEST}" .kit-install.journal .kit-install.backup .kit-install.lock; do
  [[ ! -L "${DEST}/${rel}" ]] || { echo "[FAIL] ${rel} é symlink no projeto; remova-o e repita." >&2; exit 1; }
done

STAGE='' APPLYING=0 LOCK_HELD=0
cleanup() {
  local code=$?
  if (( APPLYING )); then
    echo "[FAIL] Instalação interrompida; desfazendo as alterações no projeto..." >&2
    if rollback; then echo "[INFO] Projeto restaurado ao estado anterior." >&2; fi
    code=1
  fi
  [[ -z "${STAGE}" ]] || rm -rf "${STAGE}"
  (( ! LOCK_HELD )) || rm -rf "${LOCK}"
  exit "${code}"
}
trap cleanup EXIT
trap 'exit 130' INT TERM HUP

# Trava: uma instalação por vez no projeto (diretório com o PID do dono; trava órfã é retomada).
acquire_install_lock() {
  local owner attempt
  for attempt in 1 2; do
    if mkdir "${LOCK}" 2>/dev/null; then
      LOCK_HELD=1; printf '%s\n' "$$" > "${LOCK}/pid"; return 0
    fi
    owner="$(cat "${LOCK}/pid" 2>/dev/null || true)"
    if [[ "${owner}" =~ ^[0-9]+$ ]] && kill -0 "${owner}" 2>/dev/null; then
      echo "[FAIL] Outra instalação do kit está em andamento neste projeto (PID ${owner})." >&2; return 1
    fi
    rm -rf "${LOCK}"
  done
  echo "[FAIL] Não foi possível adquirir a trava ${LOCK}." >&2; return 1
}

if (( recover )); then
  acquire_install_lock || exit 1
  [[ -f "${JOURNAL}" ]] || { echo "[PASS] Nenhuma instalação interrompida em ${DEST}; nada a desfazer."; exit 0; }
  rollback || exit 1
  echo "[PASS] Instalação interrompida desfeita; projeto restaurado ao estado anterior a ela."
  exit 0
fi
(( dry_run )) || acquire_install_lock || exit 1
[[ ! -e "${JOURNAL}" ]] || {
  echo "[FAIL] Há uma instalação interrompida (${JOURNAL}). Desfaça-a antes: bash install.sh --recover ${DEST}" >&2; exit 1; }

# Marcadores neutros gravados no payload pelo exportador; trocados pelos valores detectados.
KIT_PACKAGE=com.example.kitapp
KIT_MAIN=KitMainApplication
KIT_NAME='@@PROJECT_NAME@@'
KIT_SLUG='@@PROJECT_SLUG@@'
APP=app

# 1. Projeto existente: app/pom.xml e a classe @SpringBootApplication são obrigatórios.
pom="${DEST}/${APP}/pom.xml"
[[ -f "${pom}" ]] || {
  echo "[FAIL] ${APP}/pom.xml não encontrado em ${DEST}: o kit configura um monorepo existente com o projeto Maven em ${APP}/." >&2
  exit 1
}
# Classe principal: @SpringBootApplication em src/main/java do app ou de seus módulos (fora de target/).
mapfile -t main_files < <(find "${DEST}/${APP}" \( -name target -o -name node_modules -o -name .git \) -prune -o \
  -type f -name '*.java' -path '*/src/main/java/*' -print 2>/dev/null |
  { xargs -r grep -lE '^[[:space:]]*@SpringBootApplication([[:space:](]|$)' 2>/dev/null || true; } | sort)
if [[ -n "${main_fqcn}" ]]; then
  main_file=''
  for candidate in "${main_files[@]}"; do
    [[ "${candidate}" == */src/main/java/"${main_fqcn//.//}".java ]] && main_file="${candidate}"
  done
  [[ -n "${main_file}" ]] || { echo "[FAIL] --main ${main_fqcn}: classe @SpringBootApplication não encontrada em ${APP}/." >&2; exit 1; }
elif (( ${#main_files[@]} == 1 )); then
  main_file="${main_files[0]}"
elif (( ${#main_files[@]} == 0 )); then
  echo "[FAIL] Classe @SpringBootApplication não encontrada em ${APP}/ (src/main/java do app ou dos módulos)." >&2; exit 1
else
  printf '  - %s\n' "${main_files[@]#"${DEST}"/}" >&2
  echo "[FAIL] ${#main_files[@]} classes @SpringBootApplication em ${APP}/; escolha uma com --main <pacote.Classe>." >&2; exit 1
fi
main_class="$(basename -- "${main_file}" .java)"
package="$(sed -n 's/^[[:space:]]*package[[:space:]]\{1,\}\([a-zA-Z0-9_.]*\)[[:space:]]*;.*/\1/p' "${main_file}" | head -n 1)"
[[ "${package}" =~ ^[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*)+$ ]] || {
  echo "[FAIL] Pacote não reconhecido em ${main_file#"${DEST}"/}." >&2; exit 1; }
[[ "${main_class}" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || {
  echo "[FAIL] Nome de classe principal não reconhecido: ${main_class}." >&2; exit 1; }
main_rel="${main_file#"${DEST}/${APP}"/}"
[[ "${main_rel}" == src/main/java/* ]] || echo "[AVISO] Classe principal em módulo (${APP}/${main_rel%%/src/main/java/*}/): o harness roda o build agregado em ${APP}/; quality gates por módulo não são configurados automaticamente." >&2

# Stack por leitura estrutural do pom (payload/scripts/lib/detect.sh, também usado no projeto).
source "${PAYLOAD}/scripts/lib/detect.sh"
detect_stack "${DEST}/${APP}"
java_version="${DETECT_JAVA}" boot_version="${DETECT_BOOT}" starters="${DETECT_STARTERS}"
name="${DETECT_NAME:-${DETECT_ARTIFACT}}"
[[ -n "${name}" ]] || name="$(basename -- "${DEST}")"
# O nome vai para Markdown e JSON: só caracteres imprimíveis, sem aspas nem barra invertida.
if [[ ! "${name}" =~ ^[[:alnum:]][[:alnum:]\ ._-]{0,99}$ ]]; then
  echo "[AVISO] Nome do projeto com caracteres não suportados; usando o artifactId ou o diretório." >&2
  name="${DETECT_ARTIFACT}"
  [[ "${name}" =~ ^[[:alnum:]][[:alnum:]._-]{0,99}$ ]] || name="$(basename -- "${DEST}" | tr -cd '[:alnum:]._-')"
  [[ -n "${name}" ]] || name=app
fi
slug="$(project_slug "${name}")"

STAGE="$(mktemp -d)"
cp -R "${PAYLOAD}/." "${STAGE}/"

# 2. Valores do projeto no lugar dos marcadores neutros (só nos textos da configuração).
rename_package "${STAGE}" "${KIT_PACKAGE}" "${package}"
rename_literal "${STAGE}" "${KIT_MAIN}" "${main_class}"
rename_literal "${STAGE}" "${KIT_NAME}" "${name}"
rename_literal "${STAGE}" "${KIT_SLUG}" "${slug:-app}"

# 3. AGENTS.md §2: stack detectada; a engenharia completa só a persistência.
#    Valor não resolvido no pom (herança) vira campo a preencher, nunca um palpite.
java_text="Java ${java_version}"
[[ -n "${java_version}" ]] || java_text="[PREENCHER-ENGENHARIA: versão do Java (${DETECT_JAVA_SRC})]"
boot_text="Spring Boot ${boot_version}"
[[ -n "${boot_version}" ]] || boot_text="[PREENCHER-ENGENHARIA: versão do Spring Boot (${DETECT_BOOT_SRC})]"
stack="- ${java_text}, ${boot_text}, Maven via Wrapper em \`${APP}/\` (detectados em \`${APP}/pom.xml\`; starters: ${starters:-nenhum}). Upgrade de Java ou Spring Boot exige aprovação."
if [[ -n "${DETECT_PERSISTENCE}" ]]; then
  persistence="- Persistência detectada: ${DETECT_PERSISTENCE}. Preserve-a; trocar de tecnologia exige decisão registrada em ADR (skill \`architecture-decision\`)."
else
  persistence='- Persistência: nenhuma tecnologia detectada em `app/pom.xml`. Introduzir uma exige decisão registrada em ADR (skill `architecture-decision`).'
fi
KIT_STACK="${stack}" KIT_PERSISTENCE="${persistence}" awk '
  /^- Java [0-9]+, Spring Boot / { print ENVIRON["KIT_STACK"]; next }
  /^- Persistência: \[PREENCHER-ENGENHARIA: tecnologia de persistência adotada/ { print ENVIRON["KIT_PERSISTENCE"]; next }
  { print }' "${STAGE}/AGENTS.md" > "${STAGE}/AGENTS.md.tmp" && mv "${STAGE}/AGENTS.md.tmp" "${STAGE}/AGENTS.md"

# 3b. Devcontainer com o Java do app (a feature aceita a versão principal, como "17").
if [[ "${java_version}" =~ ^[0-9]+$ ]]; then
  sed -i -e "/features\/java:/,/}/ s/\"version\": \"[^\"]*\"/\"version\": \"${java_version}\"/" \
    -e "s/Java [0-9][0-9]* (Temurin, LTS; baseline de projetos novos;/Java ${java_version} (Temurin; versão detectada no app\/pom.xml;/" \
    -e "s#^// Patch fixado (SDKMAN [^)]*)\(.*\)#// Versão principal do app; a feature instala o patch Temurin mais recente dela (fixe um patch, se precisar)#" \
    "${STAGE}/.devcontainer/devcontainer.json"
fi

# 4. Guia de quality gates com os blocos prontos para o pacote e a classe do projeto.
path="${package//.//}"
adapt() { sed -e "s#${KIT_PACKAGE//./\\.}#${package}#g" -e "s#${KIT_PACKAGE//.//}#${path}#g" -e "s#${KIT_MAIN}#${main_class}#g"; }
code() { printf '\n```%s\n' "$1"; cat; printf '```\n'; }
deps='archunit|junit-platform-launcher|spring-boot-testcontainers|testcontainers-junit-jupiter|testcontainers-postgresql'
{
  printf '\n## Blocos prontos para este projeto\n\n'
  printf 'Gerados para o pacote `%s` e a classe `%s`. Copie cada bloco para o lugar indicado e ajuste só o que o projeto não usar.\n' "${package}" "${main_class}"
  printf '\n### 1. `app/pom.xml`: propriedades (dentro de `<properties>`)\n'
  awk '/<properties>/ { on = 1; next } /<\/properties>/ { on = 0 } on && !/<java.version>/' "${TEMPLATES}/pom.xml" | adapt | code xml
  printf '\n### 2. `app/pom.xml`: dependências de teste (dentro de `<dependencies>`)\n\nSe o app não usa banco, omita as três dependências de Testcontainers.\n'
  awk -v deps="^(${deps})$" '
    /<dependency>/ { block = ""; on = 1 }
    on { block = block $0 "\n" }
    on && /<artifactId>/ { id = $0; gsub(/.*<artifactId>|<\/artifactId>.*/, "", id) }
    /<\/dependency>/ && on { if (id ~ deps) printf "%s", block; on = 0 }' "${TEMPLATES}/pom.xml" | code xml
  printf '\n### 3. `app/pom.xml`: plugins (dentro de `<build><plugins>`)\n'
  awk '
    /<plugin>/ && depth == 0 { block = ""; on = 1 }
    on { block = block $0 "\n" }
    on && /<artifactId>spring-boot-maven-plugin<\/artifactId>/ { skip = 1 }
    /<plugin>/ { depth++ } /<\/plugin>/ { depth-- }
    on && depth == 0 { if (!skip) printf "%s", block; on = 0; skip = 0 }' "${TEMPLATES}/pom.xml" | adapt | code xml
  printf '\n### 4. Classes de teste em `app/src/test/java/%s/`\n' "${path}"
  for file in architecture/ArchitectureTest.java TestcontainersConfiguration.java "${KIT_MAIN}IT.java" "Test${KIT_MAIN}.java"; do
    [[ -f "${TEMPLATES}/test/${file}" ]] || continue
    printf '\n`%s`:\n' "$(adapt <<<"${file}")"
    adapt < "${TEMPLATES}/test/${file}" | code java
  done
  printf '\nSem banco, troque `%sIT` por um teste de contexto sem Testcontainers e não crie `TestcontainersConfiguration` nem `Test%s`:\n' "${main_class}" "${main_class}"
  printf 'package %s;\n\nimport org.junit.jupiter.api.Test;\nimport org.springframework.boot.test.context.SpringBootTest;\n\n@SpringBootTest\nclass %sIT {\n\n\t@Test\n\tvoid contextLoads() {\n\t}\n\n}\n' \
    "${package}" "${main_class}" | code java
  printf '\n### 5. Ativar\n\nCom os blocos aplicados e `bash scripts/verify.sh` verde, troque `QUALITY_GATES=optional` por `QUALITY_GATES=required` no `.harness`.\n'
} >> "${STAGE}/docs/how-to/enable-quality-gates.md"

# 5. .harness do projeto: Maven em app/, gates opcionais até o app/pom.xml ser configurado. Numa
#    reinstalação, o QUALITY_GATES escolhido pelo projeto é preservado e só a versão do kit muda.
harness_value() { [[ -f "${DEST}/.harness" ]] && sed -n "s/^[[:space:]]*$1[[:space:]]*=[[:space:]]*\([^[:space:]#]*\).*/\1/p" "${DEST}/.harness" | tail -n 1; }
previous_version="$(harness_value KIT_VERSION || true)"
gates="$(harness_value QUALITY_GATES || true)"
[[ "${gates}" == required ]] || gates=optional
maven="$(harness_value MAVEN || true)"
[[ "${maven}" == system ]] || maven=wrapper
cat > "${STAGE}/.harness" <<EOF
# Configuração do harness (scripts/lib/app.sh); chave=valor, sem execução de código.
# APP_DIR: projeto Maven, sempre app/ (docs/architecture/repository-layout.md).
# QUALITY_GATES: optional = gate não configurado em app/pom.xml é SKIP; required = FAIL.
#   Para ativar, veja docs/how-to/enable-quality-gates.md ou bash scripts/quality/enable-gates.sh.
# REPOSITORY_ROLE: project exige APP_DIR=app (verificado por scripts/agents/check-config.sh).
# KIT_VERSION: versão do kit AI-First aplicada; o instalador a atualiza a cada reinstalação.
# MAVEN: wrapper (app/mvnw, versão fixada pelo projeto) ou system (mvn do PATH, sem Wrapper).
APP_DIR=${APP}
QUALITY_GATES=${gates}
REPOSITORY_ROLE=project
KIT_VERSION=${KIT_VERSION}
MAVEN=${maven}
EOF

# 6. Só configuração: nada sob app/, infra/, tests/ ou .github/, e o README.md é do projeto.
forbidden="$(cd "${STAGE}" && find "${APP}" infra tests .github README.md -type f 2>/dev/null | head -n 5 || true)"
if [[ -n "${forbidden}" ]]; then
  printf '%s\n' "${forbidden}" >&2
  echo "[FAIL] O kit só grava configuração; não pode gravar em ${APP}/, infra/, tests/, .github/ ou README.md." >&2
  exit 1
fi

# 7. Stubs do Claude Code e verificação na área temporária. O app/ vazio só satisfaz a validação
#    do .harness (diretórios vazios não são copiados). O README.md do projeto entra só para validar
#    o link do AGENTS.md (não é copiado de volta); sem README, a linha que aponta para ele sai.
bash "${STAGE}/scripts/agents/sync-skills.sh" >/dev/null
mkdir -p "${STAGE}/${APP}"
if [[ -f "${DEST}/README.md" && ! -L "${DEST}/README.md" ]]; then
  cp -p "${DEST}/README.md" "${STAGE}/README.md"
else
  sed -i '/^| Navegação geral | \[README.md\](README.md) |$/d' "${STAGE}/AGENTS.md"
fi
if ! check_output="$(cd "${STAGE}" && bash scripts/agents/check-config.sh 2>&1)"; then
  printf '%s\n' "${check_output}" >&2
  echo "[FAIL] A configuração gerada não passou em agents/check-config.sh; projeto não alterado." >&2
  exit 1
fi

# 8. Plano, arquivo a arquivo, antes de qualquer gravação:
#    new       não existe no projeto            -> gravado
#    same      idêntico ao do kit               -> nada (registrado como do kit)
#    refresh   o kit o gravou e o projeto não o alterou (.kit-manifest) -> atualizado no lugar
#    harness   .harness mesclado (QUALITY_GATES preservado)             -> atualizado no lugar
#    conflict  alterado pelo projeto ou sem registro -> versão do kit em <arquivo>.kit
#    pending   como conflict, mas <arquivo>.kit já existe e difere (mescla em andamento) -> intocado
declare -A installed=()
manifest_load "${DEST}/${MANIFEST}"
plan_rel=() plan_action=() unsafe=() overwrite=()
declare -A in_stage=()
while IFS= read -r -d '' file; do
  rel="${file#"${STAGE}"/}"
  [[ "${rel}" != README.md ]] || continue
  in_stage["${rel}"]=1
  target="${DEST}/${rel}"
  reason="$(safe_path "${DEST}" "${rel}")" || { unsafe+=("${rel}: ${reason}"); continue; }
  if [[ ! -e "${target}" ]]; then action=new
  elif cmp -s "${file}" "${target}"; then action=same
  elif [[ "${rel}" == .harness ]]; then action=harness
  elif [[ -n "${installed[${rel}]:-}" ]] && matches_recorded "${target}" "${installed[${rel}]}"; then action=refresh
  else
    reason="$(safe_path "${DEST}" "${rel}.kit")" || { unsafe+=("${rel}.kit: ${reason}"); continue; }
    if [[ ! -e "${target}.kit" ]] || cmp -s "${file}" "${target}.kit"; then action=conflict; else action=pending; fi
  fi
  case "${action}" in refresh|harness) overwrite+=("${rel}") ;; esac
  plan_rel+=("${rel}") plan_action+=("${action}")
done < <(find "${STAGE}" -type f -print0 | sort -z)
reason="$(safe_path "${DEST}" "${MANIFEST}")" || unsafe+=("${MANIFEST}: ${reason}")
if (( ${#unsafe[@]} > 0 )); then
  printf '  - %s\n' "${unsafe[@]}" >&2
  echo "[FAIL] Caminhos inseguros no projeto (symlink ou conflito de tipo); nada foi gravado." >&2
  exit 1
fi
# Registros de arquivos que o kit deixou de fornecer: mantidos enquanto o arquivo existir.
orphans=()
for rel in "${!installed[@]}"; do
  [[ -z "${in_stage[${rel}]:-}" && -f "${DEST}/${rel}" && ! -L "${DEST}/${rel}" ]] && orphans+=("${rel}")
done
count() { local a n=0; for a in "${plan_action[@]}"; do [[ "${a}" == "$1" ]] && n=$((n + 1)); done; echo "${n}"; }

if (( dry_run )); then
  echo "[INFO] Plano (nada gravado) para ${DEST}, kit ${KIT_VERSION}:"
  for i in "${!plan_rel[@]}"; do
    [[ "${plan_action[i]}" == same ]] || printf '  %-8s %s\n' "${plan_action[i]}" "${plan_rel[i]}"
  done
  for rel in "${orphans[@]}"; do printf '  %-8s %s\n' orphan "${rel}"; done
  echo "[PASS] Simulação: $(count new) novo(s), $(count refresh) atualizado(s), $(count conflict) conflito(s), $(count pending) mescla(s) pendente(s), $(count same) idêntico(s)."
  exit 0
fi

# Atualização no lugar só sobre arquivos sem alterações não commitadas (o Git é a rede de segurança).
if (( ${#overwrite[@]} > 0 && ! allow_dirty )) && git -C "${DEST}" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  dirty="$(git -C "${DEST}" status --porcelain -- "${overwrite[@]}" 2>/dev/null || true)"
  if [[ -n "${dirty}" ]]; then
    printf '%s\n' "${dirty}" >&2
    echo "[FAIL] Arquivos a atualizar no lugar têm alterações não commitadas; faça commit ou use --allow-dirty. Nada foi gravado." >&2
    exit 1
  fi
fi

# 9. Gravação com journal (rollback automático em qualquer falha ou interrupção).
NEW_MANIFEST="${STAGE}/.kit-manifest.new"  # fora do plano: a área temporária já foi enumerada
conflicts=() pending=() manifest_lines=()
apply_plan() {
  local i rel action src
  : > "${JOURNAL}" || return 1
  for i in "${!plan_rel[@]}"; do
    rel="${plan_rel[i]}" action="${plan_action[i]}" src="${STAGE}/${plan_rel[i]}"
    case "${action}" in
      new|refresh|harness) write_file "${src}" "${rel}" || return 1 ;;
      conflict)
        [[ -e "${DEST}/${rel}.kit" ]] || write_file "${src}" "${rel}.kit" || return 1
        conflicts+=("${rel}") ;;
      pending) pending+=("${rel}") ;;
    esac
    # Registro: só o que está no projeto com o conteúdo do kit; conflito mantém o registro anterior.
    case "${action}" in
      new|same|refresh) [[ "${rel}" == .harness ]] || manifest_lines+=("$(hash_file "${src}") ${rel}") ;;
      conflict|pending) [[ -z "${installed[${rel}]:-}" ]] || manifest_lines+=("${installed[${rel}]} ${rel}") ;;
    esac
  done
  for rel in "${orphans[@]}"; do manifest_lines+=("${installed[${rel}]} ${rel}"); done
  {
    echo "${MANIFEST_HEADER_FORMAT}"
    echo "# Arquivos instalados pelo kit AI-First ${KIT_VERSION} (hash e caminho). Não edite: o instalador"
    echo "# usa este registro para atualizar só o que o projeto não alterou. Versione junto com o projeto."
    printf '%s\n' "${manifest_lines[@]}" | sort -k2
  } > "${NEW_MANIFEST}" || return 1
  if [[ -f "${DEST}/${MANIFEST}" ]] && cmp -s "${NEW_MANIFEST}" "${DEST}/${MANIFEST}"; then return 0; fi
  write_file "${NEW_MANIFEST}" "${MANIFEST}" || return 1
}
APPLYING=1
if ! apply_plan; then
  echo "[FAIL] Falha ao gravar no projeto; desfazendo..." >&2
  APPLYING=0
  if rollback; then echo "[INFO] Projeto restaurado ao estado anterior." >&2; fi
  exit 1
fi
APPLYING=0
rm -rf "${BACKUP}"; rm -f "${JOURNAL}"

# 10. Verificação no projeto, com as cópias do kit (não executa scripts do projeto).
dest_check=PASS
if ! dest_output="$(cd "${DEST}" && HARNESS_ROOT_DIR="${DEST}" bash "${STAGE}/scripts/agents/check-config.sh" 2>&1)"; then
  dest_check=FAIL
fi

echo "[INFO] Configuração AI-First gravada em ${DEST}: $(count new) arquivo(s) novo(s), $(count refresh) atualizado(s), $(count same) já idêntico(s)."
echo "[INFO] check-config: área temporária PASS; projeto ${dest_check}."
if [[ -n "${previous_version}" || "$(count harness)" != 0 ]]; then
  echo "[INFO] Atualização do kit: ${previous_version:-versão não registrada} -> ${KIT_VERSION}; .harness atualizado com QUALITY_GATES=${gates} preservado."
else
  echo "[INFO] Kit ${KIT_VERSION} (registrado em .harness, KIT_VERSION)."
fi
if (( ${#conflicts[@]} > 0 )); then
  echo "[AVISO] ${#conflicts[@]} arquivo(s) alterado(s) no projeto (ou sem registro no .kit-manifest); a versão nova do kit está em <arquivo>.kit para mesclar:"
  printf '  - %s\n' "${conflicts[@]}"
fi
if (( ${#pending[@]} > 0 )); then
  echo "[AVISO] ${#pending[@]} arquivo(s) com <arquivo>.kit já existente e diferente (mescla em andamento): nada foi tocado. Conclua a mescla e apague o .kit para receber a versão nova:"
  printf '  - %s\n' "${pending[@]}"
fi
if (( ${#orphans[@]} > 0 )); then
  echo "[AVISO] ${#orphans[@]} arquivo(s) instalado(s) por versão anterior do kit e que ele não fornece mais; revise e remova se não usar (o kit nunca apaga):"
  printf '  - %s\n' "${orphans[@]}"
fi
if [[ "${dest_check}" == FAIL ]]; then
  printf '%s\n' "${dest_output}" | grep -E '^\[FAIL\]' | sed 's/^/  /' >&2 || true
  echo "[AVISO] check-config reprovado no projeto: resolva os itens acima (ou os conflitos .kit) e rode bash scripts/agents/check-config.sh." >&2
fi
echo "[INFO] Detectado em ${APP}/: projeto \"${name}\"; classe ${main_class} em ${package}; starters: ${starters:-nenhum}."
echo "  - Java ${java_version:-não resolvido} (${DETECT_JAVA_SRC}); Spring Boot ${boot_version:-não resolvido} (${DETECT_BOOT_SRC})."
echo "  - Persistência: ${DETECT_PERSISTENCE:-nenhuma detectada}. Nada foi alterado no runtime do app; upgrades exigem aprovação."
for warning in "${DETECT_WARNINGS[@]}"; do echo "[AVISO] ${warning}"; done
[[ "${maven}" == system || -f "${DEST}/${APP}/mvnw" ]] ||
  echo "[AVISO] ${APP}/mvnw ausente: o harness exige o Maven Wrapper. Gere-o (mvn wrapper:wrapper, com aprovação) ou defina MAVEN=system no .harness."
[[ -n "${java_version}" && -n "${boot_version}" ]] ||
  echo "[INFO] Para resolver a herança: bash scripts/agents/detect-stack.sh --effective (Maven Wrapper; pode usar rede)."
echo "[INFO] Nada foi gravado em ${APP}/, infra/, tests/, .github/ nem no README.md."
echo "[INFO] Próximos passos (seções prontas; só os campos [PREENCHER-...] ficam para preencher):"
echo "  - Negócio: docs/product/prd.md (bash scripts/product/check-prd.sh) e propósito no AGENTS.md §1."
echo "  - Engenharia: seção \"Revisão neste projeto\" dos ADRs 0001 a 0003, AGENTS.md §2 (persistência) e licença no CONTRIBUTING.md."
echo "  - Quality gates: blocos prontos no fim de docs/how-to/enable-quality-gates.md; depois QUALITY_GATES=required no .harness."
echo "  - Harness: git init (se preciso), bash scripts/git/install-hooks.sh e bash scripts/verify.sh."
pending_fields="$( (cd "${DEST}" && HARNESS_ROOT_DIR="${DEST}" bash "${STAGE}/scripts/agents/list-pending.sh") | grep -E '^  [^ ]' || true)"
[[ -z "${pending_fields}" ]] || { echo "  - Campos por responsável (lista completa: bash scripts/agents/list-pending.sh):"; sed 's/^/  /' <<<"${pending_fields}"; }

if (( ${#conflicts[@]} + ${#pending[@]} > 0 )) || [[ "${dest_check}" == FAIL ]]; then
  echo "[PARCIAL] Configuração aplicada com pendências (conflitos .kit ou verificação do projeto); exit 2."
  exit 2
fi
echo "[PASS] Configuração AI-First aplicada e verificada no projeto."
