#!/usr/bin/env bash
# Downloads all-MiniLM-L6-v2 (INT8, ARM64 ONNX) and its tokenizer: the same
# files mobile_rag_engine's own download_models.sh uses. ~23 MB, git-ignored.
set -euo pipefail
DIR="$(cd "$(dirname "$0")/.." && pwd)/assets/models/minilm"
BASE="https://huggingface.co/sentence-transformers/all-MiniLM-L6-v2/resolve/main"
mkdir -p "$DIR"
[ -s "$DIR/model.onnx" ] || curl -fL -o "$DIR/model.onnx" "$BASE/onnx/model_qint8_arm64.onnx"
[ -s "$DIR/tokenizer.json" ] || curl -fL -o "$DIR/tokenizer.json" "$BASE/tokenizer.json"
ls -l "$DIR"
