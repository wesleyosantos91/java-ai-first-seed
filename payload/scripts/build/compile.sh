#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
ROOT_DIR="$(cd -- "${SCRIPT_DIR}/../.." && pwd -P)"
source "${SCRIPT_DIR}/../lib/app.sh" || exit 1
source "${SCRIPT_DIR}/../lib/lock.sh"
acquire_harness_lock || exit 1
require_maven_project || exit 1

cd "${APP_ROOT}"
echo "[INFO] Compilando ${APP_PREFIX:-./}pom.xml..."
[[ "${MAVEN}" == wrapper ]] || echo "[INFO] Maven do PATH (MAVEN=system): $(mvn --version 2>/dev/null | head -n 1)"
run_maven --batch-mode --no-transfer-progress clean compile
echo "[OK] Compilação concluída."
