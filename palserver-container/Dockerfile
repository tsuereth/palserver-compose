FROM mcr.microsoft.com/dotnet/sdk:10.0
COPY .editorconfig /
COPY PalServerConfigManager /PalServerConfigManager
RUN dotnet publish /PalServerConfigManager/PalServerConfigManager.csproj \
	--runtime linux-x64 \
	--property:PublishSingleFile=true --self-contained true \
	--output /publish_output

# ---

FROM ubuntu:26.04
ENV DEBIAN_FRONTEND=noninteractive
RUN apt update && \
	apt install -y curl && \
	rm -rf /var/lib/apt/lists/*

ENV CONFIG_MANAGER_DIR=/PalServerConfigManager
COPY --from=0 /publish_output ${CONFIG_MANAGER_DIR}
RUN chmod +x ${CONFIG_MANAGER_DIR}/PalServerConfigManager

ENV SERVER_NAME=
ENV SERVER_DESCRIPTION=
ENV ADMIN_PASSWORD=
ENV ADMIN_PASSWORD_FILE=
ENV SERVER_PASSWORD=
ENV SERVER_PASSWORD_FILE=
ENV REST_API_ENABLED=True

COPY entrypoint.sh /
# PalServer insists (reasonably) on running as a non-root user.
# PalServerConfigManager and other tools should also run as this user,
# to maintain consistent permissions across server and save data.
USER ubuntu
ENTRYPOINT ["/entrypoint.sh"]
