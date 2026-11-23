#!/usr/bin/env bash
# Compartilhado pelo instalador do kit e por scripts/agents/detect-stack.sh; não deve ser executado
# diretamente. Detecção textual da stack de um projeto Maven, sem rede e sem executar o Maven.
#
# Lê o pom por pilha de elementos (comentários ignorados), sem regex sobre o arquivo inteiro, e
# resolve ${propriedades} declaradas no próprio pom. O que depende de herança remota (parent
# corporativo, BOM sem versão local) é reportado como não resolvido, nunca adivinhado; a resposta
# autoritativa é o pom efetivo (bash scripts/agents/detect-stack.sh --effective).
#
# detect_stack <diretório do projeto Maven> define:
#   DETECT_NAME, DETECT_ARTIFACT, DETECT_PACKAGING, DETECT_MODULES (separados por espaço)
#   DETECT_JAVA (major, ex. 21) e DETECT_JAVA_SRC (origem ou motivo de não resolução)
#   DETECT_BOOT (ex. 3.5.0) e DETECT_BOOT_SRC
#   DETECT_PARENT (groupId:artifactId:version do parent, se houver)
#   DETECT_STARTERS (lista "web, jdbc"), DETECT_PERSISTENCE (lista legível), DETECT_TOOLCHAINS (0|1)
#   DETECT_WARNINGS (array de avisos de compatibilidade e política de versões)

# Emite "caminho<TAB>valor" para cada elemento folha e "plugin<TAB>artifactId<TAB>release<TAB>source"
# para cada plugin, a partir de um pom.
pom_leaves() {
  awk '
    BEGIN { RS = "\001" }
    { doc = doc $0 }
    function trim(s) { gsub(/^[[:space:]]+|[[:space:]]+$/, "", s); return s }
    function path(   p, k) { p = stack[1]; for (k = 2; k <= depth; k++) p = p "/" stack[k]; return p }
    END {
      while ((s = index(doc, "<!--")) > 0) {
        e = index(substr(doc, s + 4), "-->")
        if (!e) { doc = substr(doc, 1, s - 1); break }
        doc = substr(doc, 1, s - 1) substr(doc, s + 4 + e + 2)
      }
      gsub(/<!\[CDATA\[[^]]*\]\]>/, "", doc)
      n = split(doc, parts, "<")
      depth = 0
      for (i = 2; i <= n; i++) {
        tok = parts[i]; gt = index(tok, ">"); if (!gt) continue
        head = substr(tok, 1, gt - 1); text = substr(tok, gt + 1)
        if (head ~ /^[?!]/) continue
        if (head ~ /^\//) {
          if (depth == 0) continue
          p = path(); name = stack[depth]
          if (leaf[depth]) {
            v = trim(buf[depth]); print p "\t" v
            if (p ~ /\/plugins\/plugin\/artifactId$/) pa = v
            if (p ~ /\/plugins\/plugin\/configuration\/release$/) pr = v
            if (p ~ /\/plugins\/plugin\/configuration\/source$/) ps = v
          }
          if (name == "plugin") { print "plugin\t" pa "\t" pr "\t" ps; pa = pr = ps = "" }
          depth--
          continue
        }
        self = head ~ /\/$/
        sub(/\/$/, "", head); split(head, w, /[[:space:]]+/)
        if (depth > 0) leaf[depth] = 0
        depth++; stack[depth] = w[1]; leaf[depth] = 1; buf[depth] = text
        if (w[1] == "plugin") pa = pr = ps = ""
        if (self) { print path() "\t"; depth-- }
      }
    }' "$1"
}

# Valor da primeira folha com o caminho exato.
leaf_value() { awk -F '\t' -v p="$2" '$1 == p { print $2; exit }' <<<"$1"; }

# Resolve ${prop} com as propriedades do próprio pom (até 5 níveis). Saída vazia = não resolvido.
resolve_value() {
  local leaves="$1" value="$2" name replacement depth
  for depth in 1 2 3 4 5; do
    [[ "${value}" =~ \$\{([^}]+)\} ]] || { printf '%s' "${value}"; return 0; }
    name="${BASH_REMATCH[1]}"
    case "${name}" in
      project.version) replacement="$(leaf_value "${leaves}" project/version)" ;;
      project.parent.version) replacement="$(leaf_value "${leaves}" project/parent/version)" ;;
      *) replacement="$(leaf_value "${leaves}" "project/properties/${name}")" ;;
    esac
    [[ -n "${replacement}" ]] || return 0
    value="${value//\$\{${name}\}/${replacement}}"
  done
}

# Major de uma versão Java ("1.8" -> 8, "21" -> 21, "25.0.1" -> 25); vazio se inválida.
java_major() {
  local v="$1"
  [[ "${v}" =~ ^1\.([0-9]+)$ ]] && { printf '%s' "${BASH_REMATCH[1]}"; return; }
  [[ "${v}" =~ ^([0-9]+)(\..*)?$ ]] && printf '%s' "${BASH_REMATCH[1]}"
}

detect_stack() {
  local dir="$1" pom="$1/pom.xml" leaves raw candidate source value module mpom all_deps=''
  DETECT_NAME='' DETECT_ARTIFACT='' DETECT_PACKAGING=jar DETECT_MODULES='' DETECT_JAVA='' DETECT_JAVA_SRC=''
  DETECT_BOOT='' DETECT_BOOT_SRC='' DETECT_PARENT='' DETECT_STARTERS='' DETECT_PERSISTENCE='' DETECT_TOOLCHAINS=0
  DETECT_WARNINGS=()
  [[ -f "${pom}" ]] || { DETECT_JAVA_SRC="pom.xml ausente"; DETECT_BOOT_SRC="pom.xml ausente"; return 1; }
  leaves="$(pom_leaves "${pom}")"

  DETECT_NAME="$(leaf_value "${leaves}" project/name)"
  DETECT_ARTIFACT="$(leaf_value "${leaves}" project/artifactId)"
  DETECT_PACKAGING="$(leaf_value "${leaves}" project/packaging)"; DETECT_PACKAGING="${DETECT_PACKAGING:-jar}"
  DETECT_MODULES="$(awk -F '\t' '$1 == "project/modules/module" { printf "%s ", $2 }' <<<"${leaves}")"
  DETECT_MODULES="${DETECT_MODULES% }"
  local pg pa pv
  pg="$(leaf_value "${leaves}" project/parent/groupId)" pa="$(leaf_value "${leaves}" project/parent/artifactId)"
  pv="$(leaf_value "${leaves}" project/parent/version)"
  [[ -z "${pa}" ]] || DETECT_PARENT="${pg}:${pa}:${pv}"

  # Java: release explícito > release do compiler plugin > java.version (parent Spring Boot) > source.
  for candidate in \
    "project/properties/maven.compiler.release|propriedade maven.compiler.release" \
    "plugin-release|<release> do maven-compiler-plugin" \
    "project/properties/java.version|propriedade java.version" \
    "project/properties/maven.compiler.source|propriedade maven.compiler.source" \
    "plugin-source|<source> do maven-compiler-plugin"; do
    source="${candidate#*|}"
    case "${candidate%%|*}" in
      plugin-release) raw="$(awk -F '\t' '$1 == "plugin" && $2 == "maven-compiler-plugin" && $3 != "" { print $3; exit }' <<<"${leaves}")" ;;
      plugin-source) raw="$(awk -F '\t' '$1 == "plugin" && $2 == "maven-compiler-plugin" && $4 != "" { print $4; exit }' <<<"${leaves}")" ;;
      *) raw="$(leaf_value "${leaves}" "${candidate%%|*}")" ;;
    esac
    [[ -n "${raw}" ]] || continue
    value="$(resolve_value "${leaves}" "${raw}")"
    if [[ -z "${value}" ]]; then DETECT_JAVA_SRC="${source} = ${raw}, não resolvida no pom (herança)"; break; fi
    DETECT_JAVA="$(java_major "${value}")"
    if [[ -n "${DETECT_JAVA}" ]]; then DETECT_JAVA_SRC="${source}"; else DETECT_JAVA_SRC="${source} = ${value}, valor não reconhecido"; fi
    break
  done
  [[ -n "${DETECT_JAVA_SRC}" ]] || DETECT_JAVA_SRC="não declarado no pom (herdado do parent ou padrão do Maven)"
  grep -qE 'maven-toolchains-plugin|<toolchains>' "${pom}" && DETECT_TOOLCHAINS=1

  # Spring Boot: parent oficial > BOM spring-boot-dependencies > versão do spring-boot-maven-plugin.
  if [[ "${pg}:${pa}" == org.springframework.boot:spring-boot-starter-parent ]]; then
    DETECT_BOOT="$(resolve_value "${leaves}" "${pv}")"; DETECT_BOOT_SRC="parent spring-boot-starter-parent"
  else
    raw="$(awk -F '\t' '
      $1 == "project/dependencyManagement/dependencies/dependency/artifactId" { a = $2 }
      $1 == "project/dependencyManagement/dependencies/dependency/version" { v = $2 }
      $1 == "project/dependencyManagement/dependencies/dependency/scope" && $2 == "import" && a == "spring-boot-dependencies" { print v; exit }
      ' <<<"${leaves}")"
    if [[ -n "${raw}" ]]; then
      DETECT_BOOT="$(resolve_value "${leaves}" "${raw}")"; DETECT_BOOT_SRC="BOM spring-boot-dependencies"
    else
      raw="$(awk -F '\t' '$1 ~ /plugins\/plugin\/artifactId$/ { a = $2 } $1 ~ /plugins\/plugin\/version$/ && a == "spring-boot-maven-plugin" { print $2; exit }' <<<"${leaves}")"
      if [[ -n "${raw}" ]]; then DETECT_BOOT="$(resolve_value "${leaves}" "${raw}")"; DETECT_BOOT_SRC="versão do spring-boot-maven-plugin"; fi
    fi
  fi
  [[ "${DETECT_BOOT}" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?([.-][A-Za-z0-9.-]+)?$ ]] || DETECT_BOOT=''
  if [[ -z "${DETECT_BOOT}" ]]; then
    if [[ -n "${DETECT_PARENT}" && -z "${DETECT_BOOT_SRC}" ]]; then
      DETECT_BOOT_SRC="não resolvido: parent ${DETECT_PARENT} (herança; use --effective)"
    else
      DETECT_BOOT_SRC="${DETECT_BOOT_SRC:+${DETECT_BOOT_SRC} sem versão resolvível}"
      DETECT_BOOT_SRC="${DETECT_BOOT_SRC:-não declarado no pom}"
    fi
  fi

  # Dependências do pom e dos módulos (multimódulo): starters e tecnologias de persistência.
  all_deps="$(awk -F '\t' '$1 == "project/dependencies/dependency/artifactId" { print $2 }' <<<"${leaves}")"
  for module in ${DETECT_MODULES}; do
    mpom="${dir}/${module}/pom.xml"
    [[ "${module}" != *..* && -f "${mpom}" && ! -L "${mpom}" ]] || continue
    all_deps+=$'\n'"$(pom_leaves "${mpom}" | awk -F '\t' '$1 == "project/dependencies/dependency/artifactId" { print $2 }')"
  done
  DETECT_STARTERS="$(sed -n 's/^spring-boot-starter-\([a-z0-9-]*\)$/\1/p' <<<"${all_deps}" |
    grep -v -e '-test$' -e '^parent$' -e '^test$' | sort -u | paste -sd, - | sed 's/,/, /g' || true)"
  local -a tech=()
  grep -qxE 'spring-boot-starter-data-jpa|hibernate-core|jakarta\.persistence-api' <<<"${all_deps}" && tech+=("Spring Data JPA/Hibernate")
  grep -qx 'spring-boot-starter-data-jdbc' <<<"${all_deps}" && tech+=("Spring Data JDBC")
  grep -qxE 'spring-boot-starter-jdbc|spring-jdbc' <<<"${all_deps}" && tech+=("Spring JDBC")
  grep -qxE 'spring-boot-starter-data-r2dbc' <<<"${all_deps}" && tech+=("R2DBC")
  grep -qxE 'spring-boot-starter-data-mongodb(-reactive)?' <<<"${all_deps}" && tech+=("MongoDB")
  grep -qxE 'mybatis-spring-boot-starter|mybatis' <<<"${all_deps}" && tech+=("MyBatis")
  grep -qxE 'jooq|spring-boot-starter-jooq' <<<"${all_deps}" && tech+=("jOOQ")
  grep -qxE 'flyway-core|spring-boot-starter-flyway' <<<"${all_deps}" && tech+=("Flyway")
  grep -qxE 'liquibase-core|spring-boot-starter-liquibase' <<<"${all_deps}" && tech+=("Liquibase")
  grep -qx 'postgresql' <<<"${all_deps}" && tech+=("PostgreSQL")
  grep -qxE 'mysql-connector-j|mysql-connector-java' <<<"${all_deps}" && tech+=("MySQL")
  grep -qE '^ojdbc' <<<"${all_deps}" && tech+=("Oracle")
  grep -qx 'mssql-jdbc' <<<"${all_deps}" && tech+=("SQL Server")
  grep -qx 'h2' <<<"${all_deps}" && tech+=("H2")
  DETECT_PERSISTENCE="$(IFS=,; printf '%s' "${tech[*]}" | sed 's/,/, /g')"

  # Política de versões (só avisos; nada é alterado no app).
  if [[ -n "${DETECT_JAVA}" ]]; then
    case "${DETECT_JAVA}" in
      8|11|17|21|25) ;;
      *) DETECT_WARNINGS+=("Java ${DETECT_JAVA} não é LTS: suporte curto; avalie migrar para a LTS 25 (exige aprovação).") ;;
    esac
    (( DETECT_JAVA >= 17 )) || DETECT_WARNINGS+=("Java ${DETECT_JAVA}: os scripts e templates do kit assumem Java 17 ou superior.")
    local boot_major="${DETECT_BOOT%%.*}"
    if [[ "${boot_major}" =~ ^[0-9]+$ ]] && (( boot_major >= 3 && DETECT_JAVA < 17 )); then
      DETECT_WARNINGS+=("Spring Boot ${DETECT_BOOT} exige Java 17 ou superior; declarado ${DETECT_JAVA}.")
    fi
  fi
  [[ "${DETECT_PACKAGING}" != pom ]] ||
    DETECT_WARNINGS+=("Projeto multimódulo (packaging pom; módulos: ${DETECT_MODULES:-nenhum declarado}): quality gates por módulo não são configurados automaticamente.")
  (( ! DETECT_TOOLCHAINS )) || DETECT_WARNINGS+=("Maven Toolchains em uso: o JDK efetivo vem do toolchains.xml de cada máquina; confirme com --effective.")
  return 0
}
