#!/bin/sh
# Starts WoPeD on a virtual display and serves it to browsers through Xpra's HTML5 client.
# The container stops when WoPeD exits (--exit-with-children).
set -eu

if [ -z "${XPRA_PASSWORD:-}" ]; then
  echo "XPRA_PASSWORD is not set. Refusing to expose WoPeD without a password." >&2
  echo "Run with: docker run -e XPRA_PASSWORD=... -p 14500:14500 <image>" >&2
  exit 1
fi

export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/tmp/xdg-runtime}"
mkdir -p "$XDG_RUNTIME_DIR"
chmod 700 "$XDG_RUNTIME_DIR"

# Optional: a host folder can be mounted at /nets (see images/Dockerfile) for saving nets.
if [ -d /nets ] && [ ! -w /nets ]; then
  echo "Warning: /nets is not writable by uid $(id -u), so saving nets there will fail." >&2
  echo "         Fix the folder's owner, or build with --build-arg WOPED_UID=\$(id -u) --build-arg WOPED_GID=\$(id -g)." >&2
fi

exec xpra start :100 \
  --daemon=no \
  --html=on \
  --bind-tcp=0.0.0.0:14500,auth=env \
  --exit-with-children=yes \
  --mdns=no --notifications=no --pulseaudio=no --dbus-launch=no \
  --start-child="java -Dawt.useSystemAAFontSettings=on -jar /opt/woped/woped.jar"
