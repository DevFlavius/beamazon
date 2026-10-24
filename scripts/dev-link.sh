#!/usr/bin/env bash
# Liga mod/ deste repo à pasta de mods do jogo, para o BeamNG carregar o mod direto do repo.
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
UNPACKED="${BEAMNG_USER:-$HOME/.local/share/BeamNG/BeamNG.drive/current}/mods/unpacked"
LINK="$UNPACKED/beamazon"

mkdir -p "$UNPACKED"
if [ -L "$LINK" ]; then
  echo "Link já existe: $LINK -> $(readlink "$LINK")"
  exit 0
fi
if [ -d "$LINK" ]; then
  # Só substitui pasta vazia; conteúdo de verdade nunca é apagado.
  rmdir "$LINK" 2>/dev/null || { echo "ERRO: $LINK tem arquivos. Mova para mod/ e rode de novo."; exit 1; }
fi
ln -s "$REPO/mod" "$LINK"
echo "OK: $LINK -> $REPO/mod"
