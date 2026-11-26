#!/bin/bash
# Maps Railway onto LearnHouse's all-in-one image (nginx on $PORT in front of the Next.js
# web app, the Python API and the collaboration server, run by pm2):
# - one variable, LEARNHOUSE_DOMAIN (the Railway domain unless set), gives every public
#   URL the web app, API, cookies, CORS, CSRF and the collab WebSocket need;
# - CORS and CSRF are scoped to that domain (upstream's default pattern accepts any);
# - course files are on the /data volume (/data/content, linked from /app/api/content,
#   where upstream reads them); kept secrets are in /data/.railway, outside what is served;
# - an empty JWT secret, NextAuth secret, collab key or admin password is generated once
#   and kept on the volume, so the API never refuses to start for a missing secret;
# - waits for Postgres, which starts alongside it.
set -u
log() { echo "[railway] $*"; }

DATA=/data
CONTENT="$DATA/content"
STATE="$DATA/.railway"
mkdir -p "$CONTENT" "$STATE"
chmod 700 "$STATE"
[ -e "$CONTENT/__init__.py" ] || : > "$CONTENT/__init__.py"
if [ ! -L /app/api/content ]; then
  rm -rf /app/api/content && ln -s "$CONTENT" /app/api/content
fi

# Railway points the domain and healthcheck at $PORT, which nginx serves; Next.js gets
# its own internal port.
HTTP_PORT="${PORT:-80}"
case "$HTTP_PORT" in '' | *[!0-9]*) log "PORT=$HTTP_PORT is not a number, using 80"; HTTP_PORT=80 ;; esac
if [ "$HTTP_PORT" != 80 ]; then
  sed -i -E "s/listen (\[::\]:)?80;/listen \1$HTTP_PORT;/" /etc/nginx/http.d/default.conf
fi
export PORT=8000 HOSTNAME=0.0.0.0

domain="${LEARNHOUSE_DOMAIN:-${RAILWAY_PUBLIC_DOMAIN:-}}"
domain="${domain#https://}"; domain="${domain#http://}"; domain="${domain%%/*}"
case "$domain" in *[!A-Za-z0-9.:-]*) log "LEARNHOUSE_DOMAIN=$domain is not a host name; ignoring it"; domain="${RAILWAY_PUBLIC_DOMAIN:-}" ;; esac
if [ -z "$domain" ]; then
  domain="localhost:$HTTP_PORT"
  log "no public domain yet: add one under Settings > Networking (port $HTTP_PORT) and redeploy"
fi
base="https://$domain"
slug="${LEARNHOUSE_INITIAL_ORG_SLUG:-default}"
slug="$(printf '%s' "$slug" | tr 'A-Z' 'a-z')"
export LEARNHOUSE_DOMAIN="$domain" LEARNHOUSE_INITIAL_ORG_SLUG="$slug"

set_default() { [ -n "${!1:-}" ] || export "$1=$2"; }
set_default LEARNHOUSE_FRONTEND_DOMAIN "$domain"
set_default LEARNHOUSE_MEDIA_URL "$base"
set_default LEARNHOUSE_ALLOWED_ORIGINS "$base"
set_default LEARNHOUSE_ALLOWED_REGEXP "^https://$(printf '%s' "$domain" | sed 's/[.]/\\./g')\$"
set_default LEARNHOUSE_SSL true
set_default LEARNHOUSE_ENV production
set_default LEARNHOUSE_TENANCY single
set_default LEARNHOUSE_PORT 9000
set_default LEARNHOUSE_API_URL http://localhost:9000
set_default LEARNHOUSE_INTERNAL_API_URL http://localhost:9000
set_default LEARNHOUSE_CONTENT_DELIVERY_TYPE filesystem
set_default LEARNHOUSE_DEVELOPMENT_MODE false
set_default LEARNHOUSE_LOGFIRE_ENABLED false
set_default NEXTAUTH_URL "$base"
set_default NEXT_PUBLIC_LEARNHOUSE_API_URL "$base/api/v1/"
set_default NEXT_PUBLIC_LEARNHOUSE_BACKEND_URL "$base/"
set_default NEXT_PUBLIC_LEARNHOUSE_DOMAIN "$domain"
set_default NEXT_PUBLIC_LEARNHOUSE_TOP_DOMAIN "$domain"
set_default NEXT_PUBLIC_LEARNHOUSE_HTTPS true
set_default NEXT_PUBLIC_LEARNHOUSE_MULTI_ORG false
set_default NEXT_PUBLIC_LEARNHOUSE_DEFAULT_ORG "$slug"
set_default NEXT_PUBLIC_COLLAB_URL "wss://$domain/collab"
set_default COLLAB_TRUST_PROXY true

# Secrets kept on the volume when a variable is empty or too short for upstream.
kept() { # name file minlen
  local name=$1 file="$STATE/$2" min=$3 val="${!1:-}"
  if [ ${#val} -ge "$min" ]; then return; fi
  [ -n "$val" ] && log "$name is shorter than $min characters; using a generated one instead"
  if [ ! -s "$file" ]; then
    (umask 077; head -c 48 /dev/urandom | base64 | tr -dc 'A-Za-z0-9' | head -c 48 > "$file")
    log "$name was empty: generated one and saved it on the volume"
  fi
  export "$name=$(cat "$file")"
}
kept LEARNHOUSE_AUTH_JWT_SECRET_KEY jwt-secret 32
kept NEXTAUTH_SECRET nextauth-secret 32
kept COLLAB_INTERNAL_KEY collab-key 32
set_default LEARNHOUSE_INITIAL_ADMIN_EMAIL admin@example.com
if [ -z "${LEARNHOUSE_INITIAL_ADMIN_PASSWORD:-}" ]; then
  kept LEARNHOUSE_INITIAL_ADMIN_PASSWORD admin-password 1
  log "LEARNHOUSE_INITIAL_ADMIN_PASSWORD was empty; a first boot uses the one in $STATE/admin-password"
fi

# Wait for Postgres (upstream waits only 30 s). bash /dev/tcp resolves IPv6 names.
db="${LEARNHOUSE_SQL_CONNECTION_STRING:-}"
host="$(printf '%s' "$db" | sed -n 's|.*@\([^:/?]*\).*|\1|p')"
dbport="$(printf '%s' "$db" | sed -n 's|.*@[^:/?]*:\([0-9]*\).*|\1|p')"
if [ -n "$host" ]; then
  for i in $(seq 1 90); do
    timeout 2 bash -c ">/dev/tcp/$host/${dbport:-5432}" 2>/dev/null && break
    [ "$i" = 1 ] && log "waiting for Postgres at $host:${dbport:-5432}"
    sleep 2
  done
fi

# Railway counts the kernel's cache of files read or written as the service's memory and
# never frees it without memory pressure; drop it for course files every 15 minutes.
( while sleep 900; do nice -n 19 drop-file-cache "$CONTENT" /tmp || true; done ) &

# Upstream's start.sh runs the three apps under pm2 and tails its logs with a second pm2
# process; with uv's launcher that is about 180 MB of memory doing nothing. A small
# supervisor runs them directly instead: each one is restarted if it exits, logs go
# straight to Railway, and a stop signal reaches all of them.
export PYTHONUNBUFFERED=1 PYTHONIOENCODING=utf-8
pids=()
supervise() { # name dir command...
  local name=$1 dir=$2; shift 2
  (
    cd "$dir" || exit 1
    trap 'kill -TERM "$child" 2>/dev/null; wait "$child"; exit 0' TERM
    while :; do
      "$@" &
      child=$!
      wait "$child"
      log "$name exited with code $?; restarting in 3 s"
      sleep 3
    done
  ) &
  pids+=($!)
}
supervise web /app/web node server-wrapper.js
supervise api /app/api /app/api/.venv/bin/python app.py
supervise collab /app/collab node dist/index.js
nginx -g 'daemon off;' &
pids+=($!)

stopping=
trap 'stopping=1; kill -TERM "${pids[@]}" 2>/dev/null' TERM INT
wait -n "${pids[@]}"
[ -z "$stopping" ] && log "nginx stopped; restarting the service"
# Either a stop signal or nginx ended: stop the rest, and exit non-zero only on a failure
# so Railway restarts the service.
kill -TERM "${pids[@]}" 2>/dev/null
wait
[ -n "$stopping" ] && exit 0
exit 1
