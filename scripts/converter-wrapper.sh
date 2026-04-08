#!/bin/bash
# Wrapper simples para converter_mp4.sh

CONVERTER_SCRIPT="$(dirname "$0")/converter_mp4.sh"

# Executar o conversor
exec $CONVERTER_SCRIPT "$@"