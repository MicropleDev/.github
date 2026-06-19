#!/usr/bin/env bash
# Canonical example of a per-repo scripts/build-bundle.sh that the
# reusable Python release workflows (python-tarball-release.yml /
# python-tarball-dev-release.yml) delegate to.
#
# Copy this into your consumer repo as scripts/build-bundle.sh, edit the
# marked sections, and `chmod +x` it.
#
# Env vars supplied by the reusable workflow:
#   PACKAGE_NAME  - e.g. "superdog"
#   VERSION       - e.g. "0.2.0" or "0.2.1-dev.20260619.abc1234"
#   BUNDLE_DIR    - staging dir to populate, e.g. dist/superdog-0.2.0
#   ASSET_PATH    - the tar.zst path you must produce
#
# What you MUST produce:
#   - $ASSET_PATH         (the tar.zst bundle)
#   - $ASSET_PATH.sha256  (sha256 sidecar)
#
# The reusable workflow then signs $ASSET_PATH with minisign and publishes.

set -euo pipefail

# === 1. Apt build deps (edit per repo) ===
sudo apt-get update
sudo apt-get install -y zstd
# Example for superdog-listener:
#   sudo apt-get install -y zstd libportaudio2 portaudio19-dev mpv

# === 2. Venv + pip install ===
python -m venv .venv
.venv/bin/pip install --upgrade pip
.venv/bin/pip install -r requirements.txt
# Example extras (superdog-listener):
#   .venv/bin/pip install openwakeword --no-deps
#   .venv/bin/python -c "import openwakeword; openwakeword.utils.download_models()"

# === 3. Optional pre-download (edit per repo) ===
# Example for superdog-listener Piper voice:
#   mkdir -p models/piper
#   curl -fsSL 'https://huggingface.co/.../en_US-amy-medium.onnx' \
#     -o models/piper/en_US-amy-medium.onnx

# === 4. Stage source into $BUNDLE_DIR (edit per repo) ===
mkdir -p "$BUNDLE_DIR"

# Option A: enumerate tracked top-level *.py files (preferred — avoids
# silently dropping newly-added modules; matches the cure adopted by
# superdog-listener#21).
#
# Using mapfile + an array is deliberate:
# - 'set -e' would kill the script on `grep -v /` returning non-zero
#   when there are no matches (e.g. brand-new repo); `|| true` cures that.
# - 'cp -a $UNQUOTED' would word-split on whitespace, breaking on
#   filenames with spaces or newlines. Array expansion is safe.
mapfile -t PY_FILES < <(git ls-files '*.py' | grep -v / || true)
if [ "${#PY_FILES[@]}" -gt 0 ]; then
  cp -a "${PY_FILES[@]}" VERSION BUILD requirements.txt "$BUNDLE_DIR/"
else
  cp -a VERSION BUILD requirements.txt "$BUNDLE_DIR/"
fi

# Option B: hardcode specific files (use only when you have config / data
# files that aren't *.py).
# cp -a system_prompt.txt system_prompt_local.txt "$BUNDLE_DIR/"

# Copy sub-package dirs as whole trees.
cp -a providers pre_process post_process tools "$BUNDLE_DIR/"

# Copy the venv we just built. Strip __pycache__ to reduce size.
cp -a .venv "$BUNDLE_DIR/"
find "$BUNDLE_DIR/.venv" -type d -name __pycache__ -exec rm -rf {} + 2>/dev/null || true

# === 5. Package + sha256 (this part is identical across repos) ===
tar --zstd -cf "$ASSET_PATH" -C "$(dirname "$BUNDLE_DIR")" "$(basename "$BUNDLE_DIR")"
(cd "$(dirname "$ASSET_PATH")" && sha256sum "$(basename "$ASSET_PATH")" > "$(basename "$ASSET_PATH").sha256")

echo "Built $ASSET_PATH ($(stat -c%s "$ASSET_PATH") bytes)"
