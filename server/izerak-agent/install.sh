#!/usr/bin/env bash
#
# Installe l'agent iZerak sur un Raspberry Pi (Debian / Raspberry Pi OS).
# A executer en root depuis le repertoire server/izerak-agent du depot.
#
#   sudo ./install.sh
#
# Idempotent : relancer le script met a jour le code sans regenerer le jeton
# ni ecraser une configuration existante.

set -euo pipefail

PREFIX=/opt/izerak-agent
CONFIG_DIR=/etc/izerak-agent
CONFIG_FILE="${CONFIG_DIR}/config.yaml"
SERVICE_USER=izerak-agent
UNIT=/etc/systemd/system/izerak-agent.service
SUDOERS=/etc/sudoers.d/izerak-agent

if [[ ${EUID} -ne 0 ]]; then
  echo "Ce script doit etre lance en root." >&2
  exit 1
fi

SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "==> Compte de service"
if ! id -u "${SERVICE_USER}" >/dev/null 2>&1; then
  # Compte systeme sans shell ni repertoire personnel : il n'a pas vocation a
  # ouvrir de session.
  useradd --system --no-create-home --shell /usr/sbin/nologin "${SERVICE_USER}"
fi

echo "==> Code et environnement virtuel"
install -d -o root -g root -m 0755 "${PREFIX}"
cp -r "${SOURCE_DIR}/izerak_agent" "${SOURCE_DIR}/pyproject.toml" "${PREFIX}/"
python3 -m venv "${PREFIX}/venv"
"${PREFIX}/venv/bin/pip" install --quiet --upgrade pip
"${PREFIX}/venv/bin/pip" install --quiet "${PREFIX}"

echo "==> Configuration"
install -d -o root -g "${SERVICE_USER}" -m 0750 "${CONFIG_DIR}"

if [[ -f "${CONFIG_FILE}" ]]; then
  echo "    ${CONFIG_FILE} existe deja, conserve tel quel."
else
  # 32 octets aleatoires, en base64 url-safe pour rester copiable a la main.
  TOKEN="$(python3 -c 'import secrets; print(secrets.token_urlsafe(32))')"
  sed "s|REMPLACER_PAR_LE_JETON_GENERE|${TOKEN}|" \
    "${SOURCE_DIR}/config.example.yaml" > "${CONFIG_FILE}"
  echo
  echo "    Jeton genere. A saisir dans les reglages de l'application :"
  echo
  echo "      ${TOKEN}"
  echo
fi
# Lisible par le seul compte de service : le fichier porte le jeton.
chown root:"${SERVICE_USER}" "${CONFIG_FILE}"
chmod 0640 "${CONFIG_FILE}"

echo "==> Autorisation sudo"
install -o root -g root -m 0440 "${SOURCE_DIR}/izerak-agent.sudoers" "${SUDOERS}"
# Une regle sudoers invalide rend sudo inutilisable sur toute la machine : on
# verifie avant de laisser le fichier en place.
if ! visudo -c -f "${SUDOERS}" >/dev/null; then
  rm -f "${SUDOERS}"
  echo "Regle sudoers invalide, installation interrompue." >&2
  exit 1
fi

echo "==> Unite systemd"
install -o root -g root -m 0644 "${SOURCE_DIR}/izerak-agent.service" "${UNIT}"
systemctl daemon-reload
systemctl enable --now izerak-agent.service

echo
echo "==> Termine."
echo "    Etat      : systemctl status izerak-agent"
echo "    Journaux  : journalctl -u izerak-agent -f"
echo
echo "    Verifiez que tls_certificate et tls_private_key pointent vers le"
echo "    certificat de la WebUI qBittorrent, puis relancez :"
echo "      systemctl restart izerak-agent"
echo
echo "    Empreinte a comparer dans l'application :"
echo "      openssl x509 -in <certificat> -noout -fingerprint -sha256"
