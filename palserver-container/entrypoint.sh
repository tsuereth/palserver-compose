#!/usr/bin/env sh

RUNAS_UID=${RUNAS_UID:-1000}
RUNAS_GID=${RUNAS_GID:-1000}

if [ -z "${PALSERVER_DATA_PATH}" ]; then
	echo Missing required variable PALSERVER_DATA_PATH
	exit -1
fi
if [ ! -x "${PALSERVER_DATA_PATH}/PalServer.sh" ]; then
	echo Cannot find expected server script at ${PALSERVER_DATA_PATH}/PalServer.sh
	exit -1
fi

# If this script is run by root, create (or reuse) the requested user.
if [ $(id -u) -eq 0 ]; then
	USERNAME=steam
	UID_CHECK=$(getent passwd ${RUNAS_UID})
	UID_CHECK_STATUS=$?
	if [ $UID_CHECK_STATUS -eq 0 ]; then
		USERNAME=$(echo ${UID_CHECK} | cut -d':' -f1)
		echo Found existing user \'${USERNAME}\' with UID ${RUNAS_UID}
	else
		echo Creating user \'${USERNAME}\' with UID:GID ${RUNAS_UID}:${RUNAS_GID}
		useradd --uid ${RUNAS_UID} --gid ${RUNAS_GID} ${USERNAME}
	fi

	echo Switching to user \'${USERNAME}\'
	exec su ${USERNAME} $0 -- $@
fi

# Confirm the script is now running as the requested user.
if [ $(id -u) -ne ${RUNAS_UID} ]; then
	echo Requested UID ${RUNAS_UID}, but running as $(whoami) with UID $(id -u)
	exit 1
fi
if [ $(id -g) -ne ${RUNAS_GID} ]; then
	echo Requested GID ${RUNAS_GID}, but running as $(whoami) with GID $(id -g)
	exit 2
fi

# TODO?: sync remote savedata to local

# Build options for the config manager based on what was provided in ENV.
CONFIG_MANAGER_OPTIONS=
if [ ! -z "${SERVER_NAME}" ]; then
	CONFIG_MANAGER_OPTIONS="${CONFIG_MANAGER_OPTIONS} \
		--set-server-name=${SERVER_NAME}"
fi
if [ ! -z "${SERVER_DESCRIPTION}" ]; then
	CONFIG_MANAGER_OPTIONS="${CONFIG_MANAGER_OPTIONS} \
		--set-server-description=${SERVER_DESCRIPTION}"
fi
if [ ! -z "${ADMIN_PASSWORD}" ]; then
	CONFIG_MANAGER_OPTIONS="${CONFIG_MANAGER_OPTIONS} \
		--set-admin-password=${ADMIN_PASSWORD}"
fi
if [ ! -z "${ADMIN_PASSWORD_FILE}" ]; then
	CONFIG_MANAGER_OPTIONS="${CONFIG_MANAGER_OPTIONS} \
		--set-admin-password-file=${ADMIN_PASSWORD_FILE}"
fi
if [ ! -z "${SERVER_PASSWORD}" ]; then
	CONFIG_MANAGER_OPTIONS="${CONFIG_MANAGER_OPTIONS} \
		--set-server-password=${SERVER_PASSWORD}"
fi
if [ ! -z "${SERVER_PASSWORD_FILE}" ]; then
	CONFIG_MANAGER_OPTIONS="${CONFIG_MANAGER_OPTIONS} \
		--set-server-password-file=${SERVER_PASSWORD_FILE}"
fi
if [ ! -z "${REST_API_ENABLED}" ]; then
	CONFIG_MANAGER_OPTIONS="${CONFIG_MANAGER_OPTIONS} \
		--set-rest-api-enabled=${REST_API_ENABLED}"
fi

# Set up the server configuration, including any ENV overrides.
${CONFIG_MANAGER_DIR}/PalServerConfigManager \
	--palserver-install-dir=${PALSERVER_DATA_PATH} ${CONFIG_MANAGER_OPTIONS}
CONFIG_MANAGER_RESULT=$?
if [ "${CONFIG_MANAGER_RESULT}" != "0" ]; then
	echo Error result ${CONFIG_MANAGER_RESULT} from PalServerConfigManager
	exit ${CONFIG_MANAGER_RESULT}
fi

PALSERVER_OPTIONS=
if [ ! -z "${PUBLIC_LOBBY}" ]; then
	PALSERVER_OPTIONS="${PALSERVER_OPTIONS} -publiclobby"
fi

# When the host system is canceling/stopping this container,
# it'll issue SIGTERM (15); trap that to try a clean shutdown.
PALSERVER_PID=
STOP_SIGNAL=15
palserver_shutdown()
(
	API_PASSWORD=${ADMIN_PASSWORD}
	if [ ! -z "${ADMIN_PASSWORD_FILE}" ]; then
		API_PASSWORD=$(cat ${ADMIN_PASSWORD_FILE} | tr -d "[:space:]")
	fi
	SHUTDOWN_RESULT=1
	if [ ! -z "${API_PASSWORD}" ]; then
		echo Sending shutdown request
		curl --fail --silent \
			--max-time=1 \
			--user admin:${API_PASSWORD} \
			--data='{"waittime":1}' \
			http://localhost:8212/v1/api/shutdown
		SHUTDOWN_RESULT=$?
	fi

	if [ "${SHUTDOWN_RESULT}" != "0" ] && [ ! -z "${PALSERVER_PID}" ]; then
		echo Stopping PalServer at PID ${PALSERVER_PID} with signal ${STOP_SIGNAL}
		kill -${STOP_SIGNAL} ${PALSERVER_PID}
	fi
)
trap "palserver_shutdown" ${STOP_SIGNAL}

echo Starting game server: ${PALSERVER_DATA_PATH}/PalServer.sh ${PALSERVER_OPTIONS}
${PALSERVER_DATA_PATH}/PalServer.sh ${PALSERVER_OPTIONS} &
PALSERVER_PID=$!
echo PalServer is running as PID ${PALSERVER_PID}

# Wait for the PalServer process to exit.
wait ${PALSERVER_PID}
echo PalServer at PID ${PALSERVER_PID} has completed

# TODO?: sync local savedata to remote
