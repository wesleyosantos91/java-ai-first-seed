#!/usr/bin/env bash
# Biblioteca do instalador do kit AI-First; não deve ser executada diretamente.
# Escrita segura no projeto de destino: caminhos sem symlink, escrita atômica por arquivo,
# journal de cada ação e rollback. Exige DEST, JOURNAL e BACKUP definidos pelo instalador.
#
# Journal (uma ação por linha, gravada ANTES da ação): "dir<TAB>rel", "new<TAB>rel" ou
# "replace<TAB>rel" (com a cópia anterior em BACKUP/rel). O rollback percorre o journal ao contrário.

# Verifica <rel> sob <raiz>: relativo, sem '.' ou '..', nenhum componente symlink, componentes
# intermediários são diretórios (ou não existem) e o último não é diretório. Imprime o motivo.
safe_path() {
  local root="$1" rel="$2" acc='' i n
  local -a parts
  case "${rel}" in
    ''|/*|*//*) echo "caminho inválido: '${rel}'"; return 1 ;;
  esac
  IFS='/' read -r -a parts <<<"${rel}"
  n=${#parts[@]}
  for (( i = 0; i < n; i++ )); do
    case "${parts[i]}" in
      .|..|'') echo "caminho inválido: '${rel}'"; return 1 ;;
    esac
    acc="${acc:+${acc}/}${parts[i]}"
    if [[ -L "${root}/${acc}" ]]; then
      echo "symlink no caminho: ${acc}"; return 1
    fi
    if (( i < n - 1 )); then
      [[ ! -e "${root}/${acc}" || -d "${root}/${acc}" ]] || { echo "não é diretório: ${acc}"; return 1; }
    else
      [[ ! -d "${root}/${acc}" ]] || { echo "é diretório: ${acc}"; return 1; }
    fi
  done
}

# Cria os diretórios ausentes de <rel_dir> sob DEST, registrando cada um no journal.
ensure_dirs() {
  local rel_dir="$1" acc='' part
  [[ "${rel_dir}" != . && -n "${rel_dir}" ]] || return 0
  local -a parts
  IFS='/' read -r -a parts <<<"${rel_dir}"
  for part in "${parts[@]}"; do
    acc="${acc:+${acc}/}${part}"
    [[ ! -L "${DEST}/${acc}" ]] || { echo "[FAIL] symlink surgiu durante a instalação: ${acc}" >&2; return 1; }
    if [[ ! -d "${DEST}/${acc}" ]]; then
      printf 'dir\t%s\n' "${acc}" >> "${JOURNAL}" || return 1
      mkdir "${DEST}/${acc}" || return 1
    fi
  done
}

# KIT_TEST_FAULT_AFTER=N (somente testes do instalador): a escrita N+1 falha, para provar o rollback.
KIT_WRITES=0

# Grava <origem> em DEST/<rel> de forma atômica (cópia temporária + mv), com journal e backup.
write_file() {
  local src="$1" rel="$2" target="${DEST}/${2}" tmp
  tmp="${target}.kit-tmp.$$"
  if [[ -n "${KIT_TEST_FAULT_AFTER:-}" ]] && (( KIT_WRITES >= KIT_TEST_FAULT_AFTER )); then
    echo "[FAIL] Falha simulada (KIT_TEST_FAULT_AFTER=${KIT_TEST_FAULT_AFTER}) ao gravar ${rel}." >&2
    return 1
  fi
  ensure_dirs "$(dirname -- "${rel}")" || return 1
  [[ ! -L "${target}" && ! -e "${tmp}" && ! -L "${tmp}" ]] ||
    { echo "[FAIL] ${rel}: alvo virou symlink ou temporário já existe." >&2; return 1; }
  if [[ -e "${target}" ]]; then
    mkdir -p "$(dirname -- "${BACKUP}/${rel}")" && cp -p "${target}" "${BACKUP}/${rel}" || return 1
    printf 'replace\t%s\n' "${rel}" >> "${JOURNAL}" || return 1
  else
    printf 'new\t%s\n' "${rel}" >> "${JOURNAL}" || return 1
  fi
  cp -p "${src}" "${tmp}" && mv -f "${tmp}" "${target}" || { rm -f "${tmp}"; return 1; }
  KIT_WRITES=$((KIT_WRITES + 1))
}

# Desfaz as ações do journal (ordem inversa) e remove journal e backup. Retorna 1 se algo não
# pôde ser restaurado (o journal e o backup são mantidos para nova tentativa).
rollback() {
  [[ -f "${JOURNAL}" ]] || return 0
  local kind rel problems=0
  while IFS=$'\t' read -r kind rel; do
    [[ -n "${rel}" ]] || continue
    case "${kind}" in
      new) rm -f "${DEST}/${rel}" "${DEST}/${rel}.kit-tmp."* || problems=1 ;;
      replace)
        if [[ -f "${BACKUP}/${rel}" ]]; then
          cp -p "${BACKUP}/${rel}" "${DEST}/${rel}.kit-tmp.rb" && mv -f "${DEST}/${rel}.kit-tmp.rb" "${DEST}/${rel}" || problems=1
        fi
        rm -f "${DEST}/${rel}.kit-tmp."* ;;
      dir) rmdir "${DEST}/${rel}" 2>/dev/null || true ;;
    esac
  done < <(tac "${JOURNAL}")
  if (( problems )); then
    echo "[FAIL] Rollback incompleto; journal mantido em ${JOURNAL} (backup em ${BACKUP})." >&2
    return 1
  fi
  rm -rf "${BACKUP}"
  rm -f "${JOURNAL}"
}
