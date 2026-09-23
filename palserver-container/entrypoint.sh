#!/usr/bin/env bash

if [ -z "${PALSERVER_DATA_PATH}" ]; then
	echo Missing required variable PALSERVER_DATA_PATH
	exit 1
fi
if [ ! -x "${PALSERVER_DATA_PATH}/PalServer.sh" ]; then
	echo Cannot find expected server script at ${PALSERVER_DATA_PATH}/PalServer.sh
	exit 1
fi

RUNAS_UID=$(id -u)
RUNAS_GID=$(id -g)
if [ ! -z "${RUNAS_UID_GID}" ]; then
	RUNAS_UID="${RUNAS_UID_GID%:*}" # substring without ":..."
	if [ ! -z "${RUNAS_UID}" ] && [ -z "${RUNAS_UID##*[!0-9]*}" ]; then
		echo Usage error: a non-numeric UID was provided in RUNAS_UID_GID
		exit 1
	fi

	if [ "${RUNAS_UID}" != $"{RUNAS_UID_GID}" ]; then
		RUNAS_GID="${RUNAS_UID_GID#*:}" # substring without "...:"
		if [ ! -z "${RUNAS_GID}" ] && [ -z "${RUNAS_GID##*[!0-9]*}" ]; then
			echo Usage error: a non-numeric GID was provided in RUNAS_UID_GID
			exit 1
		fi
	fi
fi

# PalServer cannot run as root!
if [ ${RUNAS_UID} -eq 0 ]; then
	echo Usage error: must provide a non-root UID in RUNAS_UID_GID
	exit 1
fi

# If the requested UID doesn't exist, create it.
USERNAME=palserver
UID_CHECK=$(getent passwd ${RUNAS_UID})
UID_CHECK_STATUS=$?
if [ "${UID_CHECK_STATUS}" = "0" ]; then
	USERNAME=$(echo ${UID_CHECK} | cut -d':' -f1)
	echo Found existing user \'${USERNAME}\' with UID ${RUNAS_UID}
else
	echo Creating user \'${USERNAME}\' with UID:GID ${RUNAS_UID}:${RUNAS_GID}
	useradd --uid ${RUNAS_UID} --gid ${RUNAS_GID} ${USERNAME}
	USERADD_RESULT=$?
	if [ "${USERADD_RESULT}" != "0" ]; then
		echo useradd failed with exit status ${USERADD_RESULT}
		exit 2
	fi
fi

# When the host system is canceling/stopping this container,
# it'll issue SIGTERM (15); trap that to try a clean shutdown.
PALSERVER_PID_FILE=
RUNSCRIPT_PID=
STOP_SIGNAL=15
SHUTDOWN_RESULT=
palserver_shutdown()
{
	PALSERVER_PID=
	if [ -z "${PALSERVER_PID_FILE}" ]; then
		echo Shutdown handler triggered without a PALSERVER_PID_FILE
	else
		PALSERVER_PID=$(cat ${PALSERVER_PID_FILE} | tr -d "[:space:]")
		if [ -z "${PALSERVER_PID}" ]; then
			echo Shutdown handler triggered but PALSERVER_PID_FILE ${PALSERVER_PID_FILE} is empty
		fi
	fi

	if [ ! -z "${PALSERVER_PID}" ]; then
		# Try to shut down the server with an API request first,
		# before falling back to a harder `kill` attempt.
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
	fi

	if [ -z "${RUNSCRIPT_PID}" ]; then
		echo Shutdown handler triggered without a RUNSCRIPT_PID
	else
		echo Shutting down, waiting for run-script at PID ${RUNSCRIPT_PID}
		wait ${RUNSCRIPT_PID}
		RUNSCRIPT_WAIT_RESULT=$?
		echo Wait result for run-script at PID ${RUNSCRIPT_PID} was ${RUNSCRIPT_WAIT_RESULT}
		SHUTDOWN_RESULT=1
	fi
}
trap "palserver_shutdown" ${STOP_SIGNAL}

PALSERVER_PID_FILE=$(mktemp -q)
export PALSERVER_PID_FILE
if [ $(id -u) -eq ${RUNAS_UID} ]; then
	USERNAME=$(whoami)
        echo User \'${USERNAME}\' with UID ${RUNAS_UID} starting run-script
        /run.sh &
        RUNSCRIPT_PID=$!
else
	# Make sure the PID file is writable by other users.
	chmod 0777 ${PALSERVER_PID_FILE}
	CHMOD_RESULT=$?
	if [ "${CHMOD_RESULT}" != "0" ]; then
		echo chmod failed with exit status ${CHMOD_RESULT}
		exit 2
	fi

	echo Switching to user \'${USERNAME}\' with UID ${RUNAS_UID} to start run-script
	su -c /run.sh ${USERNAME} &
	RUNSCRIPT_PID=$!
fi
echo run-script is running as PID ${RUNSCRIPT_PID}
wait ${RUNSCRIPT_PID}
RUNSCRIPT_RESULT=$?
# (Skip this wait-result message if the shutdown handler already got one.)
if [ -z "${SHUTDOWN_RESULT}" ]; then
	echo run-script at PID ${RUNSCRIPT_PID} has completed with result ${RUNSCRIPT_RESULT}
fi
