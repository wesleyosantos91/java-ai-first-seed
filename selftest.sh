#!/usr/bin/env bash
set -Eeuo pipefail

# Autoteste do instalador do kit AI-First: instala em monorepos temporários e comprova que só a
# configuração é gravada, que ela passa no check-config e no harness do projeto (Maven simulado),
# e cobre integridade: idempotência, atualização no lugar, conflitos .kit (inclusive mescla em
# andamento), symlinks, falha no meio da gravação (rollback), recuperação de interrupção,
# árvore suja, nome com caracteres especiais, órfãos, manifest legado e scripts do projeto.
# Não usa rede, Maven nem Docker; não altera este diretório.
#
# Uso: bash selftest.sh            autoteste completo, sem rede, Maven nem Docker
#      bash selftest.sh --maven    só o ponta a ponta com Maven real (exige JDK, mvn no PATH e rede):
#                                  instala na fixture new-java25-nodb, aplica os gates e roda
#                                  verify.sh e mutation.sh de verdade
# Retornos: 0 = PASS; 1 = FAIL; 3 = SKIP (--maven sem JDK ou mvn).

KIT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
WORK="$(mktemp -d)"
trap 'rm -rf "${WORK}"' EXIT
fail() { echo "[FAIL] selftest: $*" >&2; exit 1; }
pass() { echo "[PASS] selftest: $*"; }
mode="${1:-}"
case "${mode}" in ''|--maven) ;; *) echo "Uso: bash selftest.sh [--maven]" >&2; exit 1 ;; esac
project_hash() { (cd "$1" && find app infra tests .github README.md -type f -print0 | sort -z | xargs -0 sha1sum | sha1sum); }
# Estrutura (tipo e caminho de tudo, inclusive diretórios vazios e symlinks) e conteúdo dos arquivos.
tree_hash() { (cd "$1" && { find . -printf '%y %p\n' | sort; find . -type f -print0 | sort -z | xargs -0 -r sha1sum; } | sha1sum); }
kit_hash() { (cd "${KIT_DIR}" && find . -type f ! -path './.git/*' -print0 | sort -z | xargs -0 sha1sum | sha1sum); }
git_q() { git -C "$1" -c user.name=selftest -c user.email=selftest@example.invalid "${@:2}"; }
# install <log> <args...>: executa o instalador e devolve o exit code em "rc".
install() { local log="$1"; shift; rc=0; bash "${KIT_DIR}/install.sh" "$@" > "${WORK}/${log}" 2>&1 || rc=$?; }
expect_rc() { [[ "${rc}" == "$1" ]] || { cat "${WORK}/$2" >&2; fail "$3 (exit ${rc}, esperado $1)"; }; }
# Monorepo mínimo: <dir> [nome do <name> no pom]
make_project() {
  local dest="$1" pname="${2:-}"
  mkdir -p "${dest}/app/src/main/java/com/acme/demo" "${dest}/infra/terraform" "${dest}/tests" "${dest}/.github/workflows"
  printf '<project>\n\t<parent>\n\t\t<version>4.2.0</version>\n\t</parent>\n\t<artifactId>demo</artifactId>\n%s\t<properties><java.version>17</java.version></properties>\n</project>\n' \
    "${pname:+	<name>${pname}</name>
}" > "${dest}/app/pom.xml"
  printf '#!/usr/bin/env bash\necho "mvn $*"\n' > "${dest}/app/mvnw"
  printf 'package com.acme.demo;\n\n@SpringBootApplication\npublic class DemoApplication {}\n' > "${dest}/app/src/main/java/com/acme/demo/DemoApplication.java"
  printf 'terraform {}\n' > "${dest}/infra/terraform/main.tf"
  printf 'smoke\n' > "${dest}/tests/README.txt"
  printf 'name: ci\n' > "${dest}/.github/workflows/ci.yml"
  printf '# Demo\n' > "${dest}/README.md"
}
kit_before="$(kit_hash)"

# --- Ponta a ponta com Maven real (opt-in): instalação, enable-gates, verify.sh e mutation.sh ---
if [[ "${mode}" == --maven ]]; then
  command -v java >/dev/null 2>&1 && command -v mvn >/dev/null 2>&1 ||
    { echo "[SKIP] selftest --maven: java ou mvn ausente no PATH; NOT RUN."; exit 3; }
  echo "[INFO] selftest --maven: $(java -version 2>&1 | head -n 1); $(mvn -v 2>/dev/null | head -n 1)"
  # Matriz de releases do Java (o JDK do PATH compila para cada release; SELFTEST_JAVA_RELEASES ajusta).
  for release in ${SELFTEST_JAVA_RELEASES:-17 21 25}; do
  [[ "${release}" =~ ^[0-9]+$ ]] || fail "SELFTEST_JAVA_RELEASES inválido: ${release}"
  echo "[INFO] selftest --maven: Java release ${release}"
  e2e="${WORK}/maven-e2e-${release}"; cp -R "${KIT_DIR}/tests/fixtures/new-java25-nodb" "${e2e}"
  sed -i "s#<java.version>25</java.version>#<java.version>${release}</java.version>#" "${e2e}/app/pom.xml"
  base="${e2e}/app/src/main/java/com/acme/greeting" tbase="${e2e}/app/src/test/java/com/acme/greeting"
  # Starter de teste (Mockito, JUnit) e uma regra de domínio com teste, para os gates terem alvo.
  awk '/<\/dependencies>/ && !done { print "\t\t<dependency>\n\t\t\t<groupId>org.springframework.boot</groupId>\n\t\t\t<artifactId>spring-boot-starter-webmvc-test</artifactId>\n\t\t\t<scope>test</scope>\n\t\t</dependency>"; done = 1 } { print }' \
    "${e2e}/app/pom.xml" > "${e2e}/app/pom.tmp" && mv "${e2e}/app/pom.tmp" "${e2e}/app/pom.xml"
  mkdir -p "${base}/feature/greeting/domain" "${tbase}/feature/greeting/domain"
  cat > "${base}/feature/greeting/domain/Greeting.java" <<'JAVA'
package com.acme.greeting.feature.greeting.domain;

public final class Greeting {

	private Greeting() {
	}

	public static String of(String name) {
		if (name == null || name.isBlank()) {
			throw new IllegalArgumentException("name is required");
		}
		return "Hello, " + name.strip() + "!";
	}

}
JAVA
  cat > "${tbase}/feature/greeting/domain/GreetingTest.java" <<'JAVA'
package com.acme.greeting.feature.greeting.domain;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import org.junit.jupiter.api.Test;

class GreetingTest {

	@Test
	void greetsTrimmedName() {
		assertThat(Greeting.of("  Ana ")).isEqualTo("Hello, Ana!");
	}

	@Test
	void rejectsNullName() {
		assertThatThrownBy(() -> Greeting.of(null)).isInstanceOf(IllegalArgumentException.class)
				.hasMessage("name is required");
	}

	@Test
	void rejectsBlankName() {
		assertThatThrownBy(() -> Greeting.of("   ")).isInstanceOf(IllegalArgumentException.class);
	}

}
JAVA
  printf 'MAVEN=system\n' > "${e2e}/.harness"
  install e2e-install.log "${e2e}"; expect_rc 0 e2e-install.log "instalação (Maven real)"
  grep -qx 'MAVEN=system' "${e2e}/.harness" || fail "instalador não preservou MAVEN=system"
  grep -q "^- Java ${release}, Spring Boot " "${e2e}/AGENTS.md" && grep -q "\"version\": \"${release}\"" "${e2e}/.devcontainer/devcontainer.json" ||
    fail "Java ${release} não refletido no AGENTS.md ou no devcontainer"
  (cd "${e2e}" && git init -q && git add -A && git_q "${e2e}" commit -qm base) || fail "git init (Maven real)"
  (cd "${e2e}" && bash scripts/quality/enable-gates.sh --apply > "${WORK}/e2e-gates.log" 2>&1) || { cat "${WORK}/e2e-gates.log" >&2; fail "enable-gates --apply (Maven real)"; }
  git_q "${e2e}" add -A && git_q "${e2e}" commit -qm gates
  rc=0; (cd "${e2e}" && bash scripts/verify.sh > "${WORK}/e2e-verify.log" 2>&1) || rc=$?
  grep -E '^\[(RESUMO|PASS|PARCIAL|FAIL|SKIP)\]' "${WORK}/e2e-verify.log" | sed 's/^/  /'
  [[ "${rc}" == 0 ]] || { tail -60 "${WORK}/e2e-verify.log" >&2; fail "verify.sh com Maven real (exit ${rc})"; }
  grep -q '"result": "PASS"' "${e2e}/app/target/harness/verify-summary.json" || fail "verify-summary.json sem PASS"
  pass "Maven real (Java ${release}): verify.sh PASS (agentes, limites, build, unitários, arquitetura, integração, cobertura)"
  rc=0; (cd "${e2e}" && bash scripts/quality/mutation.sh > "${WORK}/e2e-mutation.log" 2>&1) || rc=$?
  grep -E '^\[(INFO|PASS|FAIL|SKIP)\] Mutação' "${WORK}/e2e-mutation.log" | sed 's/^/  /'
  [[ "${rc}" == 0 ]] || { tail -40 "${WORK}/e2e-mutation.log" >&2; fail "mutation.sh com Maven real (exit ${rc})"; }
  pass "Maven real (Java ${release}): mutation.sh PASS"
  # Regressão do gate: limite reduzido no pom reprova o verify.sh antes do build.
  sed -i '0,/<minimum>0.90<\/minimum>/s//<minimum>0.50<\/minimum>/' "${e2e}/app/pom.xml"
  rc=0; (cd "${e2e}" && bash scripts/verify.sh > "${WORK}/e2e-thr.log" 2>&1) || rc=$?
  [[ "${rc}" == 1 ]] && grep -q 'abaixo de 0.90' "${WORK}/e2e-thr.log" || { tail -20 "${WORK}/e2e-thr.log" >&2; fail "redução de limite não reprovada (exit ${rc})"; }
  pass "Maven real (Java ${release}): redução de limite no pom reprovada pelo verify.sh"
  done
  [[ "$(kit_hash)" == "${kit_before}" ]] || fail "o kit foi alterado"
  echo "[PASS] Autoteste com Maven real concluído (kit $(head -n 1 "${KIT_DIR}/VERSION"))."
  exit 0
fi

# --- Instalação, verificação no projeto e idempotência ---
dest="${WORK}/monorepo"
make_project "${dest}"
before="$(project_hash "${dest}")"
install install.log "${dest}"; expect_rc 0 install.log "instalação falhou"
grep -q 'check-config: área temporária PASS; projeto PASS' "${WORK}/install.log" || fail "relatório sem verificação no projeto"
pass "instalação concluída e verificada no projeto (exit 0)"
[[ "$(project_hash "${dest}")" == "${before}" ]] || fail "app/, infra/, tests/, .github/ ou README.md foram alterados"
pass "app/, infra/, tests/, .github/ e README.md intactos"
for path in AGENTS.md CLAUDE.md .harness scripts/verify.sh docs/product/prd.md .claude/skills/feature-delivery/SKILL.md; do
  [[ -e "${dest}/${path}" ]] || fail "ausente no projeto: ${path}"
done
for path in install.sh selftest.sh payload templates lib VERSION .kit-install.journal .kit-install.backup .kit-install.lock; do
  [[ ! -e "${dest}/${path}" ]] || fail "arquivo do instalador (ou estado de instalação) deixado no projeto: ${path}"
done
grep -qx "KIT_VERSION=$(head -n 1 "${KIT_DIR}/VERSION")" "${dest}/.harness" || fail "KIT_VERSION ausente no .harness"
grep -q '"version": "17"' "${dest}/.devcontainer/devcontainer.json" || fail "devcontainer sem o Java do app"
head -n 1 "${dest}/.kit-manifest" | grep -q 'format=2 sha256' || fail ".kit-manifest sem formato 2"
pass "configuração completa, sem arquivos do instalador; manifest formato 2"

manifest_before="$(sha1sum < "${dest}/.kit-manifest")" tree_before="$(tree_hash "${dest}")"
install idem.log "${dest}"; expect_rc 0 idem.log "reinstalação idêntica falhou"
grep -q '0 arquivo(s) novo(s), 0 atualizado(s)' "${WORK}/idem.log" || fail "reinstalação idêntica gravou arquivos"
[[ "$(sha1sum < "${dest}/.kit-manifest")" == "${manifest_before}" ]] || fail "reinstalação idêntica alterou o .kit-manifest"
[[ "$(tree_hash "${dest}")" == "${tree_before}" ]] || fail "reinstalação idêntica alterou a árvore do projeto"
pass "idempotência: segunda instalação não grava nada (árvore e manifest idênticos)"

install dry.log --dry-run "${dest}"; expect_rc 0 dry.log "dry-run falhou"
[[ "$(tree_hash "${dest}")" == "${tree_before}" ]] || fail "--dry-run gravou no projeto"
pass "--dry-run não grava"

(cd "${dest}" && git init -q && git add -A && git_q "${dest}" commit -qm init) || fail "git init"
(cd "${dest}" && bash scripts/agents/check-config.sh > "${WORK}/check.log" 2>&1) || { cat "${WORK}/check.log" >&2; fail "check-config"; }
pass "check-config aprovado no projeto"
(cd "${dest}" && bash scripts/harness-tests/harness.sh > "${WORK}/harness.log" 2>&1) || { tail -20 "${WORK}/harness.log" >&2; fail "harness do projeto"; }
pass "contratos do harness aprovados no projeto"

# --- Reinstalação com gates já ativados pelo projeto: o valor é preservado ---
sed -i 's/^QUALITY_GATES=optional$/QUALITY_GATES=required/' "${dest}/.harness"
git_q "${dest}" commit -qam gates
install reinstall.log "${dest}"; expect_rc 0 reinstall.log "reinstalação falhou"
grep -qx 'QUALITY_GATES=required' "${dest}/.harness" || fail "reinstalação não preservou QUALITY_GATES"
[[ ! -e "${dest}/.harness.kit" ]] || fail "reinstalação gerou .harness.kit"
[[ "$(project_hash "${dest}")" == "${before}" ]] || fail "reinstalação alterou arquivos do projeto"
pass "reinstalação preserva QUALITY_GATES e não toca o projeto"

# --- Atualização: arquivo idêntico ao instalado é atualizado no lugar (simulado como instalado por
#     versão anterior, com registro SHA-1 legado); arquivo alterado pelo projeto recebe .kit ---
printf '# versão anterior\n' > "${dest}/CLAUDE.md"
old_hash="$(sha1sum < "${dest}/CLAUDE.md" | cut -d' ' -f1)"
sed -i "s#^[0-9a-f]* CLAUDE.md\$#${old_hash} CLAUDE.md#" "${dest}/.kit-manifest"
printf '\nAjuste do projeto.\n' >> "${dest}/SECURITY.md"
install dirty.log "${dest}"; expect_rc 1 dirty.log "atualização no lugar sobre arquivo não commitado deveria falhar"
grep -q 'alterações não commitadas' "${WORK}/dirty.log" || fail "árvore suja sem motivo claro"
grep -q '# versão anterior' "${dest}/CLAUDE.md" || fail "árvore suja: arquivo foi gravado mesmo assim"
pass "árvore suja: atualização no lugar recusada sem --allow-dirty, nada gravado"
install upgrade.log --allow-dirty "${dest}"; expect_rc 2 upgrade.log "atualização com conflito deveria sair com 2"
grep -q '^@AGENTS.md' "${dest}/CLAUDE.md" || fail "arquivo não alterado pelo projeto não foi atualizado"
[[ ! -e "${dest}/CLAUDE.md.kit" ]] || fail "arquivo não alterado pelo projeto virou .kit"
grep -q 'Ajuste do projeto.' "${dest}/SECURITY.md" || fail "arquivo alterado pelo projeto foi sobrescrito"
[[ -f "${dest}/SECURITY.md.kit" ]] || fail "arquivo alterado pelo projeto sem .kit"
grep -q '1 atualizado(s)' "${WORK}/upgrade.log" || { cat "${WORK}/upgrade.log" >&2; fail "relatório sem a contagem de atualizados"; }
grep -q "^[0-9a-f]\{64\} CLAUDE.md$" "${dest}/.kit-manifest" || fail "registro legado SHA-1 não migrado para SHA-256"
pass "atualização: arquivo do kit atualizado no lugar (registro legado migrado); arquivo do projeto preservado com .kit (exit 2)"

# Conflito persistente não faz o kit "assumir" o conteúdo do projeto (o registro anterior é mantido).
! grep -q "^$(sha256sum < "${dest}/SECURITY.md" | cut -d' ' -f1) SECURITY.md$" "${dest}/.kit-manifest" ||
  fail "manifest registra o conteúdo do projeto como do kit"
# Mescla em andamento no .kit: nunca sobrescrita.
printf '\nMescla em andamento.\n' >> "${dest}/SECURITY.md.kit"
for run in 1 2; do
  install pending.log --allow-dirty "${dest}"; expect_rc 2 pending.log "mescla pendente deveria sair com 2"
done
grep -q 'Mescla em andamento.' "${dest}/SECURITY.md.kit" || fail ".kit com mescla em andamento foi sobrescrito"
grep -q 'mescla em andamento' "${WORK}/pending.log" || fail "mescla pendente não reportada"
pass "conflito: .kit com mescla em andamento preservado em reinstalações"

# Órfão: registro de arquivo que o kit não fornece mais é reportado, nunca apagado.
printf 'antigo\n' > "${dest}/docs/old-kit-file.md"
printf '%s docs/old-kit-file.md\n' "$(sha256sum < "${dest}/docs/old-kit-file.md" | cut -d' ' -f1)" >> "${dest}/.kit-manifest"
install orphan.log --allow-dirty "${dest}"
grep -q 'docs/old-kit-file.md' "${WORK}/orphan.log" || fail "órfão não reportado"
[[ -f "${dest}/docs/old-kit-file.md" ]] || fail "órfão apagado"
pass "órfão reportado e preservado"

# Script do projeto alterado não é executado pelo instalador.
printf '#!/usr/bin/env bash\ntouch "%s/pwned"\n' "${WORK}" > "${dest}/scripts/agents/list-pending.sh"
printf '#!/usr/bin/env bash\ntouch "%s/pwned"\n' "${WORK}" > "${dest}/scripts/agents/check-config.sh"
install exec.log --allow-dirty "${dest}"
[[ ! -e "${WORK}/pwned" ]] || fail "o instalador executou script do projeto"
pass "scripts do projeto não são executados pelo instalador"

# --- Symlinks: diretório, arquivo e .kit; nada é gravado fora nem dentro do projeto ---
if (MSYS=winsymlinks:nativestrict ln -s "${WORK}" "${WORK}/probe-link") 2>/dev/null && [[ -L "${WORK}/probe-link" ]]; then
  for kind in dir file kit; do
    sdest="${WORK}/sym-${kind}" outside="${WORK}/outside-${kind}"
    make_project "${sdest}"; mkdir -p "${outside}"
    case "${kind}" in
      dir) MSYS=winsymlinks:nativestrict ln -s "${outside}" "${sdest}/docs" ;;
      file) printf 'x\n' > "${outside}/target"; MSYS=winsymlinks:nativestrict ln -s "${outside}/target" "${sdest}/SECURITY.md" ;;
      kit) printf '# meu\n' > "${sdest}/SECURITY.md"; printf 'x\n' > "${outside}/target"
           MSYS=winsymlinks:nativestrict ln -s "${outside}/target" "${sdest}/SECURITY.md.kit" ;;
    esac
    shash="$(tree_hash "${sdest}")" ohash="$(tree_hash "${outside}")"
    install "sym-${kind}.log" "${sdest}"; expect_rc 1 "sym-${kind}.log" "symlink (${kind}) deveria ser recusado"
    [[ "$(tree_hash "${sdest}")" == "${shash}" && "$(tree_hash "${outside}")" == "${ohash}" ]] || fail "symlink (${kind}): houve gravação"
  done
  pass "symlinks (diretório, arquivo e .kit) recusados sem nenhuma gravação"
else
  echo "[SKIP] selftest: symlinks não suportados neste sistema (no Windows, ative o modo de desenvolvedor); NOT RUN."
fi

# --- Conflito de tipo (arquivo onde o kit precisa de diretório): recusado antes de gravar ---
tdest="${WORK}/type-clash"; make_project "${tdest}"; printf 'não é diretório\n' > "${tdest}/scripts"
thash="$(tree_hash "${tdest}")"
install type.log "${tdest}"; expect_rc 1 type.log "conflito de tipo deveria falhar"
[[ "$(tree_hash "${tdest}")" == "${thash}" ]] || fail "conflito de tipo: houve gravação parcial"
pass "conflito de tipo recusado sem gravação parcial"

# --- Falha no meio da gravação: rollback total (instalação nova e atualização) ---
fdest="${WORK}/fault"; make_project "${fdest}"; fhash="$(tree_hash "${fdest}")"
KIT_TEST_FAULT_AFTER=30 install fault.log "${fdest}"; expect_rc 1 fault.log "falha simulada deveria sair com 1"
[[ "$(tree_hash "${fdest}")" == "${fhash}" ]] || fail "falha na instalação nova deixou gravação parcial"
install fault-ok.log "${fdest}"; expect_rc 0 fault-ok.log "instalação após rollback falhou"
sed -i 's/^# CLAUDE.md$/# CLAUDE.md (antigo)/' "${fdest}/CLAUDE.md"
sed -i "s#^[0-9a-f]* CLAUDE.md\$#$(sha256sum < "${fdest}/CLAUDE.md" | cut -d' ' -f1) CLAUDE.md#" "${fdest}/.kit-manifest"
fhash="$(tree_hash "${fdest}")"
KIT_TEST_FAULT_AFTER=0 install fault2.log "${fdest}"; expect_rc 1 fault2.log "falha simulada na atualização deveria sair com 1"
[[ "$(tree_hash "${fdest}")" == "${fhash}" ]] || fail "falha na atualização não restaurou o projeto"
pass "falha no meio da gravação: rollback restaura o projeto (instalação e atualização)"

# --- Interrupção abrupta (journal deixado para trás): bloqueia e --recover desfaz ---
rdest="${WORK}/recover"; make_project "${rdest}"; rhash="$(tree_hash "${rdest}")"
printf 'gravado antes da interrupção\n' > "${rdest}/AGENTS.md"; mkdir -p "${rdest}/.kit-install.backup"
printf 'new\tAGENTS.md\n' > "${rdest}/.kit-install.journal"
install blocked.log "${rdest}"; expect_rc 1 blocked.log "instalação sobre journal pendente deveria falhar"
grep -q -- '--recover' "${WORK}/blocked.log" || fail "journal pendente sem instrução de --recover"
install recover.log --recover "${rdest}"; expect_rc 0 recover.log "--recover falhou"
[[ "$(tree_hash "${rdest}")" == "${rhash}" ]] || fail "--recover não restaurou o projeto"
pass "interrupção: instalação bloqueada até --recover, que restaura o projeto"

# --- Nome com caracteres especiais: não injeta em JSON/Markdown nem quebra o sed ---
ndest="${WORK}/name"; make_project "${ndest}" 'Pedidos \1 & "x" #y'
install name.log "${ndest}"; expect_rc 0 name.log "instalação com nome especial falhou"
grep -q '^# AGENTS.md — demo$' "${ndest}/AGENTS.md" || fail "nome especial não foi substituído pelo artifactId"
pass "nome com caracteres especiais substituído por nome seguro"

# --- Matriz de compatibilidade: detecção estrutural (tests/fixtures) ---
# fixture|java|origem do java (trecho)|boot|persistência (trecho ou "-")|packaging
matrix=(
  "new-java25-nodb|25|java.version|4.1.2|-|jar"
  "java21-jpa|21|java.version|3.5.7|Spring Data JPA|jar"
  "java25-jdbc|25|maven.compiler.release|4.0.3|Spring JDBC, Liquibase|jar"
  "java25-data-jdbc|25|maven-compiler-plugin|4.1.2|Spring Data JDBC|jar"
  "java17-jpa|17|java.version|3.3.5|Spring Data JPA|jar"
  "multimodule-25|25|java.version|4.1.2|Spring Data JPA|pom"
  "corporate-parent||não resolvida||-|jar"
  "no-parent|25|maven.compiler.release||-|jar"
)
(
  source "${KIT_DIR}/payload/scripts/lib/detect.sh"
  for row in "${matrix[@]}"; do
    IFS='|' read -r fx java jsrc boot pers pkg <<<"${row}"
    detect_stack "${KIT_DIR}/tests/fixtures/${fx}/app"
    [[ "${DETECT_JAVA}" == "${java}" && "${DETECT_JAVA_SRC}" == *"${jsrc}"* && "${DETECT_BOOT}" == "${boot}" && "${DETECT_PACKAGING}" == "${pkg}" ]] ||
      fail "detecção ${fx}: java=${DETECT_JAVA} (${DETECT_JAVA_SRC}) boot=${DETECT_BOOT} packaging=${DETECT_PACKAGING}"
    if [[ "${pers}" == - ]]; then [[ -z "${DETECT_PERSISTENCE}" ]] || fail "detecção ${fx}: persistência inesperada ${DETECT_PERSISTENCE}"
    else [[ "${DETECT_PERSISTENCE}" == *"${pers}"* ]] || fail "detecção ${fx}: persistência ${DETECT_PERSISTENCE}"; fi
  done
)
pass "detecção: Java (propriedade, release, compiler plugin, interpolação), Boot (parent, BOM), persistência e multimódulo em ${#matrix[@]} fixtures"

# --- Matriz de compatibilidade: instalação (stack no AGENTS.md, sem palpites nem contradição) ---
for fx in java21-jpa multimodule-25 corporate-parent no-parent; do
  mdest="${WORK}/fx-${fx}"; cp -R "${KIT_DIR}/tests/fixtures/${fx}" "${mdest}"
  install "fx-${fx}.log" "${mdest}"; expect_rc 0 "fx-${fx}.log" "instalação da fixture ${fx}"
  app_files() { (cd "$1" && find app -type f -print0 | sort -z | xargs -0 sha1sum); }
  [[ "$(app_files "${mdest}")" == "$(app_files "${KIT_DIR}/tests/fixtures/${fx}")" ]] || fail "fixture ${fx}: app/ alterado"
  stack_line="$(grep -m1 -E '^- (Java|\[PREENCHER-ENGENHARIA: versão do Java)' "${mdest}/AGENTS.md")"
  case "${fx}" in
    java21-jpa) [[ "${stack_line}" == "- Java 21, Spring Boot 3.5.7,"* ]] && grep -q '^- Persistência detectada: Spring Data JPA' "${mdest}/AGENTS.md" ||
                  fail "fixture ${fx}: AGENTS.md §2 = ${stack_line}" ;;
    multimodule-25) [[ "${stack_line}" == "- Java 25, Spring Boot 4.1.2,"* ]] && grep -q 'multimódulo' "${WORK}/fx-${fx}.log" ||
                  fail "fixture ${fx}: stack ou aviso de multimódulo" ;;
    corporate-parent) [[ "${stack_line}" == *'[PREENCHER-ENGENHARIA: versão do Java'* && "${stack_line}" == *'[PREENCHER-ENGENHARIA: versão do Spring Boot'* ]] &&
                  ! grep -q '7\.3\.1, Maven\|Spring Boot 7' "${mdest}/AGENTS.md" || fail "fixture ${fx}: herança virou palpite: ${stack_line}" ;;
    no-parent) grep -q '^# AGENTS.md — orders-service$' "${mdest}/AGENTS.md" || fail "fixture ${fx}: nome do projeto sem <parent>" ;;
  esac
done
pass "instalação nas fixtures: stack e persistência detectadas no AGENTS.md; herança não resolvida vira campo a preencher"

# --- Verificador de pós-condições dos evals: violações determinísticas reprovadas ---
pcdest="${WORK}/fx-java21-jpa"
(cd "${pcdest}" && git init -q && git add -A && git_q "${pcdest}" commit -qm base) || fail "git init pós-condições"
bash "${KIT_DIR}/evals/check-postconditions.sh" "${pcdest}" HEAD > "${WORK}/pc-ok.log" 2>&1 || { cat "${WORK}/pc-ok.log" >&2; fail "pós-condições: projeto intacto reprovado"; }
mkdir -p "${pcdest}/.github/workflows"; printf 'name: x\n' > "${pcdest}/.github/workflows/agent.yml"
sed -i 's#<java.version>21</java.version>#<java.version>25</java.version>#; s#spring-boot-starter-data-jpa#spring-boot-starter-data-jdbc#' "${pcdest}/app/pom.xml"
printf '{ "permissions": {} }\n' > "${pcdest}/.claude/settings.json"
if bash "${KIT_DIR}/evals/check-postconditions.sh" "${pcdest}" HEAD --claims-verify > "${WORK}/pc-bad.log" 2>&1; then fail "pós-condições: violações não detectadas"; fi
for expected in '.github/' 'configuração de agentes protegida' 'alterou o Java do app' 'alterou a persistência' 'declarou execução do verify.sh'; do
  grep -qF "${expected}" "${WORK}/pc-bad.log" || { cat "${WORK}/pc-bad.log" >&2; fail "pós-condições: '${expected}' não detectado"; }
done
pass "evals: verificador de pós-condições aprova projeto intacto e reprova .github, permissões, Java, persistência e PASS sem evidência"

# --- enable-gates no projeto instalado: inserção estrutural, nunca em *Management; recusas sem escrita ---
egdest="${WORK}/fx-managed"; cp -R "${KIT_DIR}/tests/fixtures/managed-sections" "${egdest}"
printf '#!/usr/bin/env bash\necho mvn\n' > "${egdest}/app/mvnw"
install fx-managed.log "${egdest}"; expect_rc 0 fx-managed.log "instalação da fixture managed-sections"
(cd "${egdest}" && git init -q && git add -A && git_q "${egdest}" commit -qm init) || fail "git init managed-sections"
(cd "${egdest}" && bash scripts/quality/enable-gates.sh --apply > "${WORK}/eg.log" 2>&1) || { cat "${WORK}/eg.log" >&2; fail "enable-gates --apply"; }
# Blocos dentro de project/dependencies e project/build/plugins: as seções *Management continuam intactas.
section() { awk -v s="$1" -v e="$2" 'index($0, s) { on = 1 } on { print } on && index($0, e) { exit }' "${egdest}/app/pom.xml"; }
[[ "$(section '<dependencyManagement>' '</dependencyManagement>' | grep -c '<dependency>')" == 1 ]] || fail "enable-gates inseriu em dependencyManagement"
[[ "$(section '<pluginManagement>' '</pluginManagement>' | grep -c '<plugin>')" == 1 ]] || fail "enable-gates inseriu em pluginManagement"
grep -q '<artifactId>archunit</artifactId>' "${egdest}/app/pom.xml" && grep -q '<id>coverage-check</id>' "${egdest}/app/pom.xml" ||
  fail "enable-gates não aplicou os blocos"
(cd "${egdest}" && bash scripts/quality/check-thresholds.sh > /dev/null) || fail "limites aplicados não reconhecidos pelo check-thresholds"
# Plugin já declarado pelo projeto: recusa sem escrita.
(cd "${egdest}" && git checkout -q -- app .harness && git clean -fdq app)
awk '{ print } /<plugins>/ && ++c == 2 { print "\t\t\t<plugin><artifactId>maven-surefire-plugin</artifactId></plugin>" }' \
  "${egdest}/app/pom.xml" > "${egdest}/app/pom.tmp" && mv "${egdest}/app/pom.tmp" "${egdest}/app/pom.xml"
git_q "${egdest}" commit -qam surefire
pom_before="$(sha1sum < "${egdest}/app/pom.xml")"
if (cd "${egdest}" && bash scripts/quality/enable-gates.sh --apply > "${WORK}/eg-dup.log" 2>&1); then fail "enable-gates duplicou plugin"; fi
grep -q 'maven-surefire-plugin já declarado' "${WORK}/eg-dup.log" && [[ "$(sha1sum < "${egdest}/app/pom.xml")" == "${pom_before}" ]] ||
  { cat "${WORK}/eg-dup.log" >&2; fail "plugin duplicado: recusa sem motivo ou com escrita"; }
# Multimódulo: recusa sem escrita.
mmdest="${WORK}/fx-multimodule-25"
printf '#!/usr/bin/env bash\necho mvn\n' > "${mmdest}/app/mvnw"
(cd "${mmdest}" && git init -q && git add -A && git_q "${mmdest}" commit -qm init) || fail "git init multimódulo"
if (cd "${mmdest}" && bash scripts/quality/enable-gates.sh --apply > "${WORK}/eg-mm.log" 2>&1); then fail "enable-gates aplicou em multimódulo"; fi
grep -q 'multimódulo' "${WORK}/eg-mm.log" && [[ -z "$(git -C "${mmdest}" status --porcelain -- app)" ]] || fail "multimódulo: recusa sem motivo ou com escrita"
pass "enable-gates: blocos só em project/dependencies e build/plugins; recusa plugin duplicado e multimódulo sem gravar"

# Duas classes @SpringBootApplication: exige --main.
twodest="${WORK}/two-mains"; make_project "${twodest}"
printf 'package com.acme.demo;\n\n  @SpringBootApplication(scanBasePackages = "com.acme")\npublic class OtherApplication {}\n' > "${twodest}/app/src/main/java/com/acme/demo/OtherApplication.java"
install two.log "${twodest}"; expect_rc 1 two.log "duas classes principais deveriam exigir --main"
install two-main.log --main com.acme.demo.OtherApplication "${twodest}"; expect_rc 0 two-main.log "--main falhou"
grep -q 'OtherApplication' "${twodest}/docs/how-to/enable-quality-gates.md" || fail "--main não aplicado"
pass "várias classes principais: recusa sem --main; --main escolhe a classe (anotação indentada e com argumentos)"

[[ "$(kit_hash)" == "${kit_before}" ]] || fail "o kit foi alterado pela instalação"
echo "[PASS] Autoteste do instalador concluído (kit $(head -n 1 "${KIT_DIR}/VERSION"))."
