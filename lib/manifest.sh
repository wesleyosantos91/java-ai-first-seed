#!/usr/bin/env bash
# Biblioteca do instalador do kit AI-First; não deve ser executada diretamente.
# .kit-manifest: registro dos arquivos que o kit gravou no projeto ("<hash> <caminho>" por linha).
# Formato 2: SHA-256. Linhas antigas com SHA-1 (40 hexadecimais) continuam válidas para comparar.

MANIFEST_HEADER_FORMAT='# kit-manifest format=2 sha256'

hash_file() { sha256sum < "$1" | cut -d' ' -f1; }

# Indica se <arquivo> tem o conteúdo registrado em <hash> (SHA-256 ou SHA-1 legado).
matches_recorded() {
  local file="$1" recorded="$2" actual
  case "${#recorded}" in
    64) actual="$(sha256sum < "${file}" | cut -d' ' -f1)" ;;
    40) actual="$(sha1sum < "${file}" | cut -d' ' -f1)" ;;
    *) return 1 ;;
  esac
  [[ "${actual}" == "${recorded}" ]]
}

# Carrega <manifest> no array associativo global "installed" (caminho -> hash).
# Linhas inválidas são ignoradas: o registro só concede atualização no lugar, nunca grava caminhos.
manifest_load() {
  local file="$1" hash path
  [[ -f "${file}" ]] || return 0
  while IFS=' ' read -r hash path || [[ -n "${hash}" ]]; do
    hash="${hash%$'\r'}" path="${path%$'\r'}"
    [[ "${hash}" =~ ^([0-9a-f]{40}|[0-9a-f]{64})$ && -n "${path}" ]] || continue
    installed["${path}"]="${hash}"
  done < "${file}"
}
