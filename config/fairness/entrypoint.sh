#!/usr/bin/env bash
# Renders the portal configuration O'FAIRe expects on its classpath, then runs
# the command (catalina.sh run, or fairness-cache).
#
# Upstream ships this file as config/portals/<portal>/config.properties inside
# the war and expects it to be edited by hand before packaging; here it is
# generated at startup from the environment, so the appliance stays configured
# from .env only.
set -euo pipefail

: "${SERVER_DEFAULT_PORTAL:=ontoportal}"
: "${PORTAL_URL:=http://api:9393}"
: "${PORTAL_APIKEY:=}"
: "${PORTAL_ADMIN_APIKEY:=}"
: "${CACHE_ENABLED:=true}"
: "${CACHE_FILE_PATH:=/srv/ontoportal/data/fairness/save.json}"

# Used to build the cache of the private ontologies too; falls back to the
# public key, which then only sees what an anonymous user sees.
if [ -z "${PORTAL_ADMIN_APIKEY}" ]; then
  PORTAL_ADMIN_APIKEY="${PORTAL_APIKEY}"
fi

# The portal name and its configuration directory must be the same string:
# O'FAIRe reads the directory to build the PortalInstance, then looks the
# properties up again by the *name* property lowercased (ResultCache), so a
# mismatch loses the cache path. Deriving both from one variable rules it out.
portal="$(printf '%s' "${SERVER_DEFAULT_PORTAL}" | tr '[:upper:]' '[:lower:]')"
export SERVER_DEFAULT_PORTAL="${portal}"

config_dir="/usr/local/tomcat/webapps/ROOT/WEB-INF/classes/config/portals/${portal}"
mkdir -p "${config_dir}"
cat >"${config_dir}/config.properties" <<EOF
name=${portal}
url=${PORTAL_URL}
apikey=${PORTAL_APIKEY}
adminApikey=${PORTAL_ADMIN_APIKEY}
cacheFilePath=${CACHE_FILE_PATH}
cacheEnabled=${CACHE_ENABLED}
EOF

# ResultCache creates the cache directory with mkdir(), not mkdirs(): the
# parent has to exist already (it is a volume, so this is a no-op after the
# first start).
mkdir -p "$(dirname "${CACHE_FILE_PATH}")"

echo "[+] O'FAIRe portal '${portal}' -> ${PORTAL_URL} (cache: ${CACHE_ENABLED}, ${CACHE_FILE_PATH})"

exec "$@"
