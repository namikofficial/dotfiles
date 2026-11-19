#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
CAPTURE="$ROOT/shell/noxflow/surfaces/capture/Capture.qml"
SETTINGS="$ROOT/shell/noxflow/surfaces/capture/QuickSnipSettings.qml"
OCR_TEXT="$ROOT/shell/noxflow/surfaces/capture/OcrText.js"

has() {
  local needle="$1" file="$2"
  if ! grep -Fq -- "$needle" "$file"; then
    printf 'missing %s in %s\n' "$needle" "$file" >&2
    exit 1
  fi
}

has 'ocrCaptureProcess.run(["grim", "-g", region, ocrCaptureFile])' "$CAPTURE"
has 'root.ocrProcess.run(["tesseract", root.ocrCaptureFile, "stdout"' "$CAPTURE"
has 'tsvProcess.run(["tesseract", root.ocrCaptureFile, "stdout"' "$CAPTURE"
has 'OcrText.validLanguage(root.ocrLanguage)' "$CAPTURE"
has 'OcrText.normalize(root.ocrProcess.output' "$CAPTURE"
has 'notifyProcess.run(["notify-send", "OCR ready", "Select the result to copy it"' "$CAPTURE"
has '|| "eng"' "$SETTINGS"
if grep -Fq 'ocrProcess.runShell' "$CAPTURE" || grep -Fq 'tsvProcess.runShell' "$CAPTURE"; then
  printf 'OCR commands must use argument arrays, not shell strings\n' >&2
  exit 1
fi
test -f "$OCR_TEXT"

printf 'noxflow capture OCR contract checks passed\n'
