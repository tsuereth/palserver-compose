#!/usr/bin/env bash

if [ -z "${PALSERVER_PID_FILE}" ]; then
	echo Missing required variable PALSERVER_PID_FILE
	exit 1
fi
if [ ! -w "${PALSERVER_PID_FILE}" ]; then
	echo Unable to write to PALSERVER_PID_FILE at ${PALSERVER_PID_FILE}
	exit 2
fi

# Build options for the config manager based on what was provided in ENV.
CONFIG_MANAGER_OPTIONS=()
if [ ! -z "${SERVER_NAME}" ]; then
	CONFIG_MANAGER_OPTIONS+=("--set-server-name")
	CONFIG_MANAGER_OPTIONS+=("${SERVER_NAME}")
fi
if [ ! -z "${SERVER_DESCRIPTION}" ]; then
	CONFIG_MANAGER_OPTIONS+=("--set-server-description")
	CONFIG_MANAGER_OPTIONS+=("${SERVER_DESCRIPTION}")
fi
if [ ! -z "${ADMIN_PASSWORD}" ]; then
	CONFIG_MANAGER_OPTIONS+=("--set-admin-password")
	CONFIG_MANAGER_OPTIONS+=("${ADMIN_PASSWORD}")
fi
if [ ! -z "${ADMIN_PASSWORD_FILE}" ]; then
	CONFIG_MANAGER_OPTIONS+=("--set-admin-password-file")
	CONFIG_MANAGER_OPTIONS+=("${ADMIN_PASSWORD_FILE}")
fi
if [ ! -z "${SERVER_PASSWORD}" ]; then
	CONFIG_MANAGER_OPTIONS+=("--set-server-password")
	CONFIG_MANAGER_OPTIONS+=("${SERVER_PASSWORD}")
fi
if [ ! -z "${SERVER_PASSWORD_FILE}" ]; then
	CONFIG_MANAGER_OPTIONS+=("--set-server-password-file")
	CONFIG_MANAGER_OPTIONS+=("${SERVER_PASSWORD_FILE}")
fi
if [ ! -z "${REST_API_ENABLED}" ]; then
	CONFIG_MANAGER_OPTIONS+=("--set-rest-api-enabled")
	CONFIG_MANAGER_OPTIONS+=("${REST_API_ENABLED}")
fi

# Set up the server configuration, including any ENV overrides.
${CONFIG_MANAGER_DIR}/PalServerConfigManager \
	--palserver-install-dir=${PALSERVER_DATA_PATH} \
	"${CONFIG_MANAGER_OPTIONS[@]}"
CONFIG_MANAGER_RESULT=$?
if [ "${CONFIG_MANAGER_RESULT}" != "0" ]; then
	echo Error result ${CONFIG_MANAGER_RESULT} from PalServerConfigManager
	exit ${CONFIG_MANAGER_RESULT}
fi

PALSERVER_OPTIONS=()

# Use JSON log formatting, instead of the default text format.
# The PalServer JSON schema isn't ... great, but,
# text logging includes way too many empty lines!
PALSERVER_OPTIONS+=("-logformat=json")

# Always enable the gamedata API, for the metrics exporter.
PALSERVER_OPTIONS+=("-enable-gamedata-api")

if [ ! -z "${PUBLIC_LOBBY}" ]; then
	PALSERVER_OPTIONS+=("-publiclobby")
fi

echo Starting game server: ${PALSERVER_DATA_PATH}/PalServer.sh "${PALSERVER_OPTIONS[@]}"
${PALSERVER_DATA_PATH}/PalServer.sh "${PALSERVER_OPTIONS[@]}" &
PALSERVER_PID=$!
echo PalServer is running as PID ${PALSERVER_PID}
echo $PALSERVER_PID > ${PALSERVER_PID_FILE}

# Wait for the PalServer process to exit.
wait ${PALSERVER_PID}
PALSERVER_RESULT=$?
echo PalServer at PID ${PALSERVER_PID} has completed with result ${PALSERVER_RESULT}
