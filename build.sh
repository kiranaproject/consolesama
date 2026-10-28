#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

# Build script for consolesama (Samarinda Terminal) supporting Pasbuild, FTML, and tests

FTPAS_DIR="../ftpas"

ensure_ftml() {
  if [ ! -f src/main/pascal/consolesama.res ] || [ src/main/ftml/consolesama.ftml -nt src/main/pascal/consolesama.res ]; then
    echo "==> Regenerating FTML resource (.res)..."
    if [ ! -x target/ftml_embed ] || [ tools/ftml_embed.pas -nt target/ftml_embed ]; then
      mkdir -p target
      fpc -Mobjfpc -Sh -FEtarget tools/ftml_embed.pas >/dev/null
    fi
    target/ftml_embed \
      --res src/main/pascal/consolesama.res \
      src/main/ftml/consolesama.ftml
  fi
}

ensure_libft() {
  if [ -f "${FTPAS_DIR}/target/libft.so" ]; then
    mkdir -p target
    if [ ! -f target/libft.so ]; then
      cp -f "${FTPAS_DIR}/target/libft.so" target/libft.so
    fi
  fi
}

TARGET="${1:-compile}"

case "${TARGET}" in
  test)
    echo "==> Running tests with pasbuild..."
    shift 1 || true
    ensure_ftml
    ensure_libft
    pasbuild test "$@"
    ;;
  clean)
    echo "==> Cleaning target artifacts..."
    shift 1 || true
    rm -f src/main/pascal/consolesama.res src/main/pascal/consolesama.ftml.res.pas
    pasbuild clean "$@"
    ;;
  ftml)
    echo "==> Compiling tools/ftml_embed and embedding FTML (.res)..."
    mkdir -p target
    fpc -Mobjfpc -Sh -FEtarget tools/ftml_embed.pas
    target/ftml_embed \
      --res src/main/pascal/consolesama.res \
      src/main/ftml/consolesama.ftml
    ;;
  run)
    ensure_ftml
    ensure_libft
    pasbuild compile
    exec ./target/consolesama "$@"
    ;;
  compile|fpc|*)
    echo "==> Compiling consolesama with pasbuild..."
    if [ "${TARGET}" = "compile" ] || [ "${TARGET}" = "fpc" ]; then
      shift 1 || true
    fi
    ensure_ftml
    ensure_libft
    pasbuild compile "$@"
    ensure_libft
    ;;
esac
