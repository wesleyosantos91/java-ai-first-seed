#!/usr/bin/env bash
set -Eeuo pipefail

# Mostra a stack detectada do app (Java, Spring Boot, persistência, módulos), com a origem de cada
# valor. Insumo da skill project-discovery; não altera nada.
#
# Uso: bash scripts/agents/detect-stack.sh              detecção textual, sem rede nem Maven
#      bash scripts/agents/detect-stack.sh --effective  também consulta o pom efetivo pelo Maven
#                                                       Wrapper (resolve herança; pode usar rede)
# Retornos: 0 = detectado (valores não resolvidos aparecem com o motivo); 1 = erro.

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
ROOT_DIR="$(cd -- "${SCRIPT_DIR}/../.." && pwd -P)"
source "${SCRIPT_DIR}/../lib/app.sh" || exit 1
source "${SCRIPT_DIR}/../lib/detect.sh"

effective=0
case "${1:-}" in
  '') ;;
  --effective) effective=1 ;;
  *) echo "Uso: bash scripts/agents/detect-stack.sh [--effective]" >&2; exit 1 ;;
esac

detect_stack "${APP_ROOT}" || { echo "[FAIL] ${APP_PREFIX}pom.xml não encontrado." >&2; exit 1; }
echo "[INFO] Stack detectada em ${APP_PREFIX}pom.xml (textual, sem herança remota):"
echo "  - Projeto: ${DETECT_NAME:-${DETECT_ARTIFACT:-?}} (packaging ${DETECT_PACKAGING}${DETECT_MODULES:+; módulos: ${DETECT_MODULES}})"
echo "  - Parent: ${DETECT_PARENT:-nenhum}"
echo "  - Java: ${DETECT_JAVA:-não resolvido} (${DETECT_JAVA_SRC})"
echo "  - Spring Boot: ${DETECT_BOOT:-não resolvido} (${DETECT_BOOT_SRC})"
echo "  - Starters: ${DETECT_STARTERS:-nenhum}"
echo "  - Persistência: ${DETECT_PERSISTENCE:-nenhuma tecnologia detectada}"
for warning in "${DETECT_WARNINGS[@]}"; do echo "[AVISO] ${warning}"; done

if (( effective )); then
  require_maven_project || exit 1
  out="$(mktemp)"
  trap 'rm -f "${out}"' EXIT
  echo "[INFO] Pom efetivo (Maven Wrapper; pode baixar plugins):"
  (cd "${APP_ROOT}" && run_maven --batch-mode --no-transfer-progress -q help:effective-pom -Doutput="${out}") ||
    { echo "[FAIL] help:effective-pom falhou; a detecção textual acima continua válida com suas ressalvas." >&2; exit 1; }
  detect_stack_effective() {
    local tmp; tmp="$(mktemp -d)"; cp "${out}" "${tmp}/pom.xml"; detect_stack "${tmp}"; rm -rf "${tmp}"
  }
  detect_stack_effective
  echo "  - Java efetivo: ${DETECT_JAVA:-não resolvido} (${DETECT_JAVA_SRC})"
  echo "  - Spring Boot efetivo: ${DETECT_BOOT:-não resolvido} (${DETECT_BOOT_SRC})"
fi
