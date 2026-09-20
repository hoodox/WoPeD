# syntax=docker/dockerfile:1.7
#
# Serves the WoPeD desktop (Swing) app in a browser through Xpra's HTML5 client.
#
# Build (needs a settings.xml with a GitHub token that has read:packages, kept outside the repo):
#   docker build -f images/Dockerfile --secret id=m2settings,src=$HOME/.woped-m2-settings.xml -t woped-xpra .
#   docker build -f images/Dockerfile --build-arg JAVA_VERSION=21 ...      # try a newer Java (17 is what CI uses)
# Run:
#   docker run --rm -e XPRA_PASSWORD=changeme -p 14500:14500 woped-xpra
#   then open http://localhost:14500
# Give WoPeD an extra host folder for nets (WoPeD's default nets folder is left as it is):
#   mkdir -p ~/woped-nets
#   docker run --rm -e XPRA_PASSWORD=changeme -v ~/woped-nets:/nets -v woped-home:/home/woped \
#     -p 127.0.0.1:14500:14500 woped-xpra
# In WoPeD's Open/Save dialogs browse to /nets. To make the dialogs start there, set /nets as the
# home directory in WoPeD's Configuration dialog once (it is saved in the woped-home volume).
# The container user is uid/gid 1000. If your host user differs, build with
#   --build-arg WOPED_UID=$(id -u) --build-arg WOPED_GID=$(id -g)

ARG JAVA_VERSION=17

# ---------------------------------------------------------------- build
FROM maven:3.9-eclipse-temurin-${JAVA_VERSION} AS build
WORKDIR /src
COPY . .
# The GitHub Packages token is mounted only for this step and never written to a layer.
RUN --mount=type=secret,id=m2settings,target=/root/.m2/settings.xml \
    mvn -B install -DskipTests -pl '!WoPeD-Installer,!WoPeD-UnitTests'

# ---------------------------------------------------------------- runtime
FROM eclipse-temurin:${JAVA_VERSION}-jre-jammy AS runtime

ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates wget gnupg fonts-dejavu-core xvfb \
 && wget -q -O /usr/share/keyrings/xpra.asc https://xpra.org/xpra.asc \
 && wget -q -O /etc/apt/sources.list.d/xpra.sources \
      https://raw.githubusercontent.com/Xpra-org/xpra/master/packaging/repos/jammy/xpra.sources \
 && apt-get update \
 && apt-get install -y --no-install-recommends xpra xpra-x11 xpra-html5 \
 && rm -rf /var/lib/apt/lists/*

ARG WOPED_UID=1000
ARG WOPED_GID=1000
RUN groupadd -g "${WOPED_GID}" woped \
 && useradd -m -s /bin/sh -u "${WOPED_UID}" -g "${WOPED_GID}" woped

COPY --from=build /src/WoPeD-Starter/target/*-jar-with-dependencies.jar /opt/woped/woped.jar
COPY images/entrypoint.sh /opt/woped/entrypoint.sh
RUN chmod +x /opt/woped/entrypoint.sh

USER woped
WORKDIR /home/woped
# WoPeD keeps settings and recent files in ~/.WoPeD-<version>/
VOLUME /home/woped
EXPOSE 14500
ENTRYPOINT ["/opt/woped/entrypoint.sh"]
