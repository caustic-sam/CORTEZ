#!/bin/sh
set -euo pipefail
# idempotent HACS installer - places HACS into ./config/custom_components/hacs
INSTALL_DIR="/config/custom_components/hacs"
SCRIPTDIR="/scripts"

echo "HACS installer: checking ${INSTALL_DIR}"
if [ -d "${INSTALL_DIR}" ] && [ -f "${INSTALL_DIR}/manifest.json" ]; then
  echo "HACS already present; nothing to do."
  exit 0
fi

mkdir -p "$(dirname "${INSTALL_DIR}")"
cd /tmp
echo "Downloading HACS..."
apk add --no-cache curl unzip >/dev/null 2>&1 || true
curl -fsSL https://github.com/hacs/integration/releases/latest/download/hacs.zip -o hacs.zip
unzip -q hacs.zip -d hacs-tmp
rm -f hacs.zip
mkdir -p "${INSTALL_DIR}"
cp -a hacs-tmp/* "${INSTALL_DIR}/"
rm -rf hacs-tmp
echo "HACS installed to ${INSTALL_DIR}."
echo "Ensure permissions are correct for the Home Assistant container user."
exit 0
