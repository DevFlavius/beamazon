#!/usr/bin/env bash
# Gera dist/beamazon.zip só com o conteúdo de mod/ (sem docs, notas nem .gitkeep).
# O nome do zip não leva versão: assim um update substitui o anterior no jogo.
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$REPO/dist/beamazon.zip"

mkdir -p "$REPO/dist"
rm -f "$OUT"
(cd "$REPO/mod" && zip -r -q "$OUT" . -x '*.gitkeep' -x '*.md' -x '.*')
echo "OK: $OUT"
unzip -l "$OUT" | tail -1
