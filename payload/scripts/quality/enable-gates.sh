#!/usr/bin/env bash
set -Eeuo pipefail

# Aplica no app os blocos prontos de quality gates da seção "Blocos prontos para este projeto" de
# docs/how-to/enable-quality-gates.md (gerada pelo instalador do kit com o pacote do projeto):
# propriedades, dependências de teste e plugins no pom do app, classes de teste e
# QUALITY_GATES=required no .harness. Mudança de build: execute só com autorização.
#
# Uso: bash scripts/quality/enable-gates.sh --dry-run   mostra o que mudaria, sem gravar
#      bash scripts/quality/enable-gates.sh --apply     aplica (exige app/ limpo no Git)
# - Sem banco no app (nenhum starter JDBC/JPA, PostgreSQL ou Flyway), usa o teste de contexto sem
#   Testcontainers e omite as dependências de Testcontainers.
# - Não sobrescreve classes de teste existentes; não renomeia classes *Tests (só avisa).
# Retornos: 0 = aplicado, simulado ou já configurado; 1 = erro (nada gravado).

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
ROOT_DIR="$(cd -- "${SCRIPT_DIR}/../.." && pwd -P)"
source "${SCRIPT_DIR}/../lib/app.sh" || exit 1
source "${SCRIPT_DIR}/../lib/pom.sh"
source "${SCRIPT_DIR}/../lib/lock.sh"

case "${1:-}" in
  --dry-run) apply=0 ;;
  --apply) apply=1 ;;
  *) echo "Uso: bash scripts/quality/enable-gates.sh --dry-run | --apply" >&2; exit 1 ;;
esac
(( $# == 1 )) || { echo "Uso: bash scripts/quality/enable-gates.sh --dry-run | --apply" >&2; exit 1; }
acquire_harness_lock || exit 1
require_maven_project || exit 1
POM="${APP_ROOT}/pom.xml"
GUIDE="${ROOT_DIR}/docs/how-to/enable-quality-gates.md"

if pom_has '<id>coverage-check</id>' && pom_has 'pitest-maven'; then
  echo "[PASS] Quality gates já configurados em ${APP_PREFIX}pom.xml; nada a aplicar."
  exit 0
fi
grep -q '^## Blocos prontos para este projeto' "${GUIDE}" 2>/dev/null || {
  echo "[FAIL] Seção \"Blocos prontos para este projeto\" ausente em docs/how-to/enable-quality-gates.md (gerada pelo instalador do kit)." >&2
  exit 1
}

# 1. Extrai os blocos do guia: 3 blocos XML (propriedades, dependências, plugins), as classes de
#    teste rotuladas (`caminho.java`:) e o teste de contexto sem banco (bloco Java sem rótulo).
BLOCKS="$(mktemp -d)"
trap 'rm -rf "${BLOCKS}"; release_harness_lock' EXIT
awk -v out="${BLOCKS}" '
  /^## Blocos prontos para este projeto/ { on = 1; next }
  !on { next }
  /^`[^`]+\.java`:$/ { label = $0; gsub(/^`|`:$/, "", label); next }
  /^```/ {
    if (inblock) { close(file); inblock = 0; label = ""; next }
    inblock = 1
    if ($0 ~ /xml/) { file = out "/xml-" (++xml); next }
    name = (label != "" ? label : "nodb-it"); gsub(/\//, "__", name)
    file = out "/java-" name
    next
  }
  inblock { print > file }' "${GUIDE}"
for part in xml-1 xml-2 xml-3 java-nodb-it; do
  [[ -s "${BLOCKS}/${part}" ]] || { echo "[FAIL] Bloco ${part} não encontrado no guia." >&2; exit 1; }
done

# 2. Variante com ou sem banco, conforme as dependências do app.
if grep -qE 'spring-boot-starter-(jdbc|data-[a-z-]+)|<artifactId>postgresql</artifactId>|flyway' "${POM}"; then
  database=1
else
  database=0
  awk '
    /<dependency>/ { block = ""; on = 1 }
    on { block = block $0 "\n"; if ($0 ~ /testcontainers/) skip = 1 }
    /<\/dependency>/ && on { if (!skip) printf "%s", block; on = 0; skip = 0 }' "${BLOCKS}/xml-2" > "${BLOCKS}/xml-2.nodb"
  mv "${BLOCKS}/xml-2.nodb" "${BLOCKS}/xml-2"
fi

# 3. Classes de teste a criar (caminhos relativos a app/src/test/java/<pacote>/).
package="$(pom_property app.basePackage 2>/dev/null || true)"
[[ -n "${package}" ]] || package="$(sed -n 's#.*<app.basePackage>\([^<]*\)</app.basePackage>.*#\1#p' "${BLOCKS}/xml-1" | head -n 1)"
main="$(sed -n 's#.*<app.mainClass>\([^<]*\)</app.mainClass>.*#\1#p' "${BLOCKS}/xml-1" | head -n 1)"
[[ -n "${package}" && -n "${main}" ]] || { echo "[FAIL] Pacote ou classe principal não encontrados nos blocos." >&2; exit 1; }
test_dir="${APP_ROOT}/src/test/java/${package//.//}"
declare -A classes=()
classes["architecture/ArchitectureTest.java"]="${BLOCKS}/java-architecture__ArchitectureTest.java"
if (( database )); then
  classes["TestcontainersConfiguration.java"]="${BLOCKS}/java-TestcontainersConfiguration.java"
  classes["${main}IT.java"]="${BLOCKS}/java-${main}IT.java"
  classes["Test${main}.java"]="${BLOCKS}/java-Test${main}.java"
else
  classes["${main}IT.java"]="${BLOCKS}/java-nodb-it"
fi
for rel in "${!classes[@]}"; do
  [[ -s "${classes[${rel}]}" ]] || { echo "[FAIL] Classe ${rel} não encontrada nos blocos do guia." >&2; exit 1; }
  [[ ! -e "${test_dir}/${rel}" ]] || { echo "[FAIL] ${APP_PREFIX}src/test/java/${package//.//}/${rel} já existe; nada foi gravado." >&2; exit 1; }
done

# 3b. Preflight estrutural do pom (nada é gravado se falhar). Os pontos de inserção são localizados
#     pela pilha de elementos, fora de comentários: project/properties, project/dependencies e
#     project/build/plugins, nunca dentro de dependencyManagement, pluginManagement ou profiles.
# element_lines <pom> <caminho>: "abertura fechamento ocorrências autofechado" (números de linha).
element_lines() {
  awk -v want="$2" '
    function path(   p, k) { p = st[1]; for (k = 2; k <= d; k++) p = p "/" st[k]; return p }
    {
      line = carry $0; carry = ""; out = ""
      while (length(line)) {
        if (incom) { e = index(line, "-->"); if (!e) { line = ""; break }; line = substr(line, e + 3); incom = 0; continue }
        s = index(line, "<!--"); if (!s) { out = out line; break }
        out = out substr(line, 1, s - 1); line = substr(line, s + 4); incom = 1
      }
      line = out
      while (match(line, /<[^>]*>/)) {
        t = substr(line, RSTART + 1, RLENGTH - 2); line = substr(line, RSTART + RLENGTH)
        if (t ~ /^[?!]/) continue
        if (t ~ /^\//) { if (path() == want) { cl = NR; n++ }; d--; continue }
        self = (t ~ /\/$/); name = t; sub(/[[:space:]\/].*$/, "", name)
        d++; st[d] = name
        if (path() == want) { if (self) { selfc = NR; n++ } else op = NR }
        if (self) d--
      }
      s = index(line, "<"); if (s) carry = substr(line, s) " "
    }
    END { printf "%d %d %d %d\n", op, cl, n, selfc }' "$1"
}
structural=()
check_target() {  # <caminho> <obrigatório 0|1>: 0 = utilizável, 1 = ausente (permitido)
  local open close n self found
  found="$(element_lines "${POM}" "$1")" || { echo "[FAIL] Leitura estrutural de ${APP_PREFIX}pom.xml falhou." >&2; exit 1; }
  read -r open close n self <<<"${found}"
  if (( n == 0 )); then
    (( $2 )) && structural+=("<${1##*/}> ausente em ${1%/*} (adicione a seção vazia e repita)")
    return 1
  fi
  if (( n > 1 )); then structural+=("<${1##*/}> declarado ${n} vezes em ${1%/*}"); return 0; fi
  if (( self > 0 )); then structural+=("<${1##*/}/> autofechado (linha ${self}); troque por <${1##*/}></${1##*/}>"); return 0; fi
  (( open != close )) || structural+=("<${1##*/}> abre e fecha na mesma linha (${open}); separe as tags")
  return 0
}
source "${SCRIPT_DIR}/../lib/detect.sh"
detect_stack "${APP_ROOT}"
[[ "${DETECT_PACKAGING}" != pom ]] ||
  structural+=("projeto multimódulo (packaging pom; módulos: ${DETECT_MODULES:-?}): configure os gates no módulo da aplicação manualmente (docs/how-to/enable-quality-gates.md)")
check_target project/properties 1 || true
check_target project/dependencies 1 || true
if check_target project/build/plugins 0; then plugins_target=project/build/plugins
elif check_target project/build 0; then plugins_target=project/build
else plugins_target=project; fi
leaves="$(pom_leaves "${POM}")"
# Plugins do kit já declarados pelo projeto em build/plugins: nunca duplicar (mescla manual).
for plugin in maven-surefire-plugin maven-failsafe-plugin jacoco-maven-plugin pitest-maven maven-dependency-plugin; do
  awk -F '\t' -v p="${plugin}" '$1 == "project/build/plugins/plugin/artifactId" && $2 == p { found = 1 } END { exit !found }' <<<"${leaves}" &&
    structural+=("plugin ${plugin} já declarado em build/plugins: mescle manualmente o bloco 3 do guia")
done
# Propriedades do bloco já definidas pelo projeto: nunca sobrescrever.
while IFS= read -r prop; do
  [[ -n "${prop}" ]] || continue
  awk -F '\t' -v p="project/properties/${prop}" '$1 == p { found = 1 } END { exit !found }' <<<"${leaves}" &&
    structural+=("propriedade <${prop}> já definida no pom: mescle manualmente o bloco 1 do guia")
done < <(sed -n 's#^[[:space:]]*<\([A-Za-z0-9_.-]*\)[ />].*#\1#p' "${BLOCKS}/xml-1")
if (( ${#structural[@]} > 0 )); then
  printf '  - %s\n' "${structural[@]}" >&2
  echo "[FAIL] ${APP_PREFIX}pom.xml não pode receber os blocos automaticamente; nada foi gravado. Aplique-os à mão seguindo docs/how-to/enable-quality-gates.md." >&2
  exit 1
fi
# Dependências de teste que o projeto já declara: omitidas do bloco (sem duplicar).
existing_deps="$(awk -F '\t' '$1 == "project/dependencies/dependency/artifactId" { print $2 }' <<<"${leaves}")"
awk -v existing="${existing_deps//$'\n'/ }" '
  BEGIN { n = split(existing, e, " "); for (i = 1; i <= n; i++) have[e[i]] = 1 }
  /<dependency>/ { block = ""; on = 1; id = "" }
  on { block = block $0 "\n"; if ($0 ~ /<artifactId>/) { id = $0; gsub(/.*<artifactId>|<\/artifactId>.*/, "", id) } }
  /<\/dependency>/ && on { if (!(id in have)) printf "%s", block; on = 0 }' "${BLOCKS}/xml-2" > "${BLOCKS}/xml-2.dedup"
mv "${BLOCKS}/xml-2.dedup" "${BLOCKS}/xml-2"
if [[ "${DETECT_PARENT}" != org.springframework.boot:spring-boot-starter-parent:* ]]; then
  echo "[AVISO] Parent não é o spring-boot-starter-parent (${DETECT_PARENT:-sem parent}): versões de surefire, failsafe e dependency-plugin precisam vir do seu parent ou BOM; confira com bash scripts/agents/detect-stack.sh --effective."
fi

echo "[INFO] Quality gates para ${package}.${main} ($([[ ${database} == 1 ]] && echo 'com banco: Testcontainers' || echo 'sem banco: teste de contexto')):"
echo "  - ${APP_PREFIX}pom.xml: $(wc -l < "${BLOCKS}/xml-1" | tr -d ' ') linha(s) de propriedades, $(grep -c '<dependency>' "${BLOCKS}/xml-2") dependência(s) de teste, $(grep -c '^			<plugin>' "${BLOCKS}/xml-3") plugin(s)"
for rel in $(printf '%s\n' "${!classes[@]}" | sort); do echo "  - criar ${APP_PREFIX}src/test/java/${package//.//}/${rel}"; done
echo "  - .harness: QUALITY_GATES=required"
tests_files="$(find "${APP_ROOT}/src/test/java" -name '*Tests.java' 2>/dev/null | sed "s#^${ROOT_DIR}/##" || true)"
[[ -z "${tests_files}" ]] || { echo "[AVISO] Classes *Tests não executam pela convenção (*Test, *IT); renomeie-as:"; sed 's/^/  - /' <<<"${tests_files}"; }

if (( ! apply )); then
  echo "[PASS] Simulação concluída; nada foi gravado. Aplique com: bash scripts/quality/enable-gates.sh --apply"
  exit 0
fi

# 4. Aplicação: só com app/ e .harness limpos no Git, para revisar e desfazer.
git -C "${ROOT_DIR}" rev-parse --is-inside-work-tree >/dev/null 2>&1 ||
  { echo "[FAIL] --apply exige repositório Git (para revisar e desfazer a mudança)." >&2; exit 1; }
if [[ -n "$(git -C "${ROOT_DIR}" status --porcelain -- "${APP_DIR}" .harness)" ]]; then
  echo "[FAIL] ${APP_DIR}/ ou .harness com alterações não commitadas; faça commit antes de aplicar." >&2; exit 1
fi
insert_at() {  # <arquivo> <linha> <bloco>: insere o bloco antes da linha indicada
  awk -v at="$2" -v block="$3" '
    BEGIN { while ((getline line < block) > 0) text = text line "\n" }
    NR == at { printf "%s", text }
    { print }' "$1" > "$1.tmp" && mv "$1.tmp" "$1"
}
# Insere antes do fechamento do elemento <caminho> (já validado no preflight, seção 3b).
insert_into() {
  local path="$1" block="$2" open close n self
  read -r open close n self <<<"$(element_lines "${POM}" "${path}")"
  insert_at "${POM}" "${close}" "${block}"
}
cp -p "${POM}" "${BLOCKS}/pom.before"
insert_into project/properties "${BLOCKS}/xml-1"
insert_into project/dependencies "${BLOCKS}/xml-2"
# Sem project/build/plugins, a seção é criada (dentro de <build>, ou um <build> novo).
case "${plugins_target}" in
  project/build/plugins) insert_into project/build/plugins "${BLOCKS}/xml-3" ;;
  project/build)
    { printf '\t\t<plugins>\n'; cat "${BLOCKS}/xml-3"; printf '\t\t</plugins>\n'; } > "${BLOCKS}/plugins-wrapped"
    insert_into project/build "${BLOCKS}/plugins-wrapped" ;;
  project)
    { printf '\t<build>\n\t\t<plugins>\n'; cat "${BLOCKS}/xml-3"; printf '\t\t</plugins>\n\t</build>\n'; } > "${BLOCKS}/plugins-wrapped"
    insert_into project "${BLOCKS}/plugins-wrapped" ;;
esac
# XML bem formado depois da inserção (python ou xmllint, se houver); senão, restaura o pom.
xml_ok=unknown
if command -v xmllint >/dev/null 2>&1; then
  xmllint --noout "${POM}" 2>/dev/null && xml_ok=yes || xml_ok=no
else
  for interpreter in python3 python; do
    command -v "${interpreter}" >/dev/null 2>&1 || continue
    "${interpreter}" -c 'import sys, xml.dom.minidom; xml.dom.minidom.parse(sys.argv[1])' "${POM}" 2>/dev/null && xml_ok=yes || xml_ok=no
    break
  done
fi
if [[ "${xml_ok}" == no ]]; then
  cp -p "${BLOCKS}/pom.before" "${POM}"
  echo "[FAIL] ${APP_PREFIX}pom.xml ficaria mal formado após a inserção; restaurado, nada foi gravado." >&2
  exit 1
fi
[[ "${xml_ok}" == yes ]] || echo "[AVISO] Sem xmllint, python3 ou python: boa formação do pom NÃO VERIFICADA; confira com git diff e bash scripts/verify.sh."
for rel in "${!classes[@]}"; do
  mkdir -p "$(dirname -- "${test_dir}/${rel}")"
  cp "${classes[${rel}]}" "${test_dir}/${rel}"
done
sed -i 's/^QUALITY_GATES=.*/QUALITY_GATES=required/' "${ROOT_DIR}/.harness"
grep -qx 'QUALITY_GATES=required' "${ROOT_DIR}/.harness" || printf 'QUALITY_GATES=required\n' >> "${ROOT_DIR}/.harness"
echo "[PASS] Quality gates aplicados. Próximos passos: git diff; bash scripts/verify.sh; bash scripts/quality/mutation.sh."
echo "       Para desfazer: git checkout -- ${APP_DIR} .harness && git clean -fd ${APP_DIR}/src/test"
