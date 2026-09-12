#!/usr/bin/env bash

if [ -z "${PALSERVER_DATA_PATH}" ]; then
	echo Missing required variable PALSERVER_DATA_PATH
	exit -1
fi
if [ ! -x "${PALSERVER_DATA_PATH}/PalServer.sh" ]; then
	echo Cannot find expected server script at ${PALSERVER_DATA_PATH}/PalServer.sh
	exit -1
fi

# TODO?: sync remote savedata to local

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
if [ ! -z "${PUBLIC_LOBBY}" ]; then
	PALSERVER_OPTIONS+=("-publiclobby")
fi

# When the host system is canceling/stopping this container,
# it'll issue SIGTERM (15); trap that to try a clean shutdown.
PALSERVER_PID=
STOP_SIGNAL=15
SHUTDOWN_RESULT=
palserver_shutdown()
{
	if [ -z "${PALSERVER_PID}" ]; then
		echo Shutdown handler triggered without a PALSERVER_PID, exiting
		exit 0
	fi

	API_PASSWORD=${ADMIN_PASSWORD}
	if [ ! -z "${ADMIN_PASSWORD_FILE}" ]; then
		API_PASSWORD=$(cat ${ADMIN_PASSWORD_FILE} | tr -d "[:space:]")
	fi
	API_RESULT=
	if [ ! -z "${API_PASSWORD}" ]; then
		echo Sending shutdown API request
		curl --fail --silent \
			--max-time=1 \
			--user admin:${API_PASSWORD} \
			--data='{"waittime":1}' \
			http://localhost:8212/v1/api/shutdown
		API_RESULT=$?
		echo Shutdown API result: ${API_RESULT}
	fi

	if [ "${API_RESULT}" != "0" ]; then
		echo Stopping PalServer at PID ${PALSERVER_PID} with signal ${STOP_SIGNAL}
		kill -${STOP_SIGNAL} ${PALSERVER_PID}
	fi

	echo Shutting down, waiting for PalServer at PID ${PALSERVER_PID}
	wait ${PALSERVER_PID}
	SHUTDOWN_RESULT=$?
	echo Shutdown wait result for PalServer at PID ${PALSERVER_PID} was ${SHUTDOWN_RESULT}
}
trap "palserver_shutdown" ${STOP_SIGNAL}

echo Starting game server: ${PALSERVER_DATA_PATH}/PalServer.sh "${PALSERVER_OPTIONS[@]}"
${PALSERVER_DATA_PATH}/PalServer.sh "${PALSERVER_OPTIONS[@]}" &
PALSERVER_PID=$!
echo PalServer is running as PID ${PALSERVER_PID}

# Wait for the PalServer process to exit.
wait ${PALSERVER_PID}
PALSERVER_RESULT=$?
# (Skip this wait-result message if the shutdown handler already got one.)
if [ -z "${SHUTDOWN_RESULT}" ]; then
	echo PalServer at PID ${PALSERVER_PID} has completed with result ${PALSERVER_RESULT}
fi

# TODO?: sync local savedata to remote
