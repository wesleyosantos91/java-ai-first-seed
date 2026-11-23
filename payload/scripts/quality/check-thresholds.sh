#!/usr/bin/env bash
set -Eeuo pipefail

# Protege os limites aprovados dos quality gates (ADR-0003; AGENTS.md, seção 6) contra redução no
# pom do app: JaCoCo LINE e BRANCH >= 0.90 com haltOnFailure ativo e PIT mutationThreshold >= 90.
# Lê o pom por estrutura (lib/detect.sh; comentários ignorados), sem Maven. Executado pelo verify.sh.
# Reduzir um limite exige decisão registrada em novo ADR e alteração deliberada deste script.
#
# Uso: bash scripts/quality/check-thresholds.sh
# Retornos: 0 = limites preservados; 3 = gates ainda não configurados no pom (nada a proteger);
#           1 = limite reduzido, desativado ou ilegível.

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
ROOT_DIR="$(cd -- "${SCRIPT_DIR}/../.." && pwd -P)"
source "${SCRIPT_DIR}/../lib/app.sh" || exit 1
source "${SCRIPT_DIR}/../lib/detect.sh"

# Mínimos aprovados. Não altere para obter PASS (AGENTS.md, seção 6).
COVERAGE_MIN=0.90
MUTATION_MIN=90

POM="${APP_ROOT}/pom.xml"
[[ -f "${POM}" ]] || { echo "[SKIP] Limites: ${APP_PREFIX}pom.xml ausente."; exit 3; }
leaves="$(pom_leaves "${POM}")"
plugin_leaves() {  # <artifactId>: folhas dentro de build/plugins/plugin com esse artifactId
  awk -F '\t' -v id="$1" '
    $1 ~ /^project\/build\/plugins\/plugin\// && $1 !~ /dependencies/ { block = block $0 "\n" }
    $1 == "project/build/plugins/plugin/artifactId" { art = $2 }
    $1 == "plugin" { if (art == id) printf "%s", block; block = ""; art = "" }' <<<"${leaves}"
}
jacoco="$(plugin_leaves jacoco-maven-plugin)"
pit="$(plugin_leaves pitest-maven)"
if [[ -z "${jacoco}" && -z "${pit}" ]]; then
  echo "[SKIP] Limites: JaCoCo e PIT não configurados em ${APP_PREFIX}pom.xml; nada a proteger."
  exit 3
fi

problems=()
ge() { awk -v a="$1" -v b="$2" 'BEGIN { exit !(a + 0 >= b + 0) }'; }
if [[ -n "${jacoco}" ]]; then
  mins="$(awk -F '\t' '$1 ~ /\/limit\/minimum$/ { print $2 }' <<<"${jacoco}")"
  if [[ -z "${mins}" ]]; then
    problems+=("JaCoCo configurado sem <minimum> nas regras de cobertura")
  fi
  while IFS= read -r value; do
    [[ -n "${value}" ]] || continue
    if [[ ! "${value}" =~ ^[0-9]*\.?[0-9]+$ ]]; then problems+=("JaCoCo <minimum> não numérico: ${value}")
    elif ! ge "${value}" "${COVERAGE_MIN}"; then problems+=("JaCoCo <minimum> ${value} abaixo de ${COVERAGE_MIN}"); fi
  done <<<"${mins}"
  awk -F '\t' '$1 ~ /\/haltOnFailure$/ && $2 == "false" { found = 1 } END { exit !found }' <<<"${jacoco}" &&
    problems+=("JaCoCo com <haltOnFailure>false</haltOnFailure>")
  awk -F '\t' '$1 ~ /\/configuration\/skip$/ && $2 == "true" { found = 1 } END { exit !found }' <<<"${jacoco}" &&
    problems+=("JaCoCo com <skip>true</skip>")
fi
if [[ -n "${pit}" ]]; then
  threshold="$(awk -F '\t' '$1 ~ /\/configuration\/mutationThreshold$/ { print $2; exit }' <<<"${pit}")"
  if [[ -z "${threshold}" ]]; then problems+=("PIT sem <mutationThreshold>")
  elif [[ ! "${threshold}" =~ ^[0-9]+$ ]]; then problems+=("PIT <mutationThreshold> não numérico: ${threshold}")
  elif (( threshold < MUTATION_MIN )); then problems+=("PIT <mutationThreshold> ${threshold} abaixo de ${MUTATION_MIN}"); fi
  awk -F '\t' '$1 ~ /\/configuration\/skip$/ && $2 == "true" { found = 1 } END { exit !found }' <<<"${pit}" &&
    problems+=("PIT com <skip>true</skip>")
fi

if (( ${#problems[@]} > 0 )); then
  printf '  - %s\n' "${problems[@]}" >&2
  echo "[FAIL] Limites de qualidade reduzidos ou desativados em ${APP_PREFIX}pom.xml; reverta ou registre a decisão em novo ADR aprovado." >&2
  exit 1
fi
echo "[PASS] Limites de qualidade preservados (JaCoCo >= ${COVERAGE_MIN}, PIT >= ${MUTATION_MIN})."
