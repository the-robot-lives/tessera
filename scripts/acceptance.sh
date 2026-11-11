#!/usr/bin/env bash
# tessera ACCEPTANCE pass — the local mirror of the CI FAST lane gate
# (docs/notes/test-tiering.md):
#
#   ExUnit fast (lib + persona_kit) · WTR fast · WTR conformance (Tier-1)
#   · e2e-smoke (Cypress @fast: the BLOCKING shadow-event core claim)
#
# Speed contract (warm cache): well under 2 minutes wall-clock.
#   * the four unit suites run CONCURRENTLY (independent processes);
#   * the two demo boots (Hologram :5586, plain-HTML :5587) run CONCURRENTLY
#     (wall = max, not sum) and ONE boot is reused for every @fast spec;
#   * the gallery (:5588) is NOT booted — it is not part of the core claim
#     (nightly full suite covers it);
#   * installs are skipped when node_modules/deps already exist (warm path).
#
# The Hologram chain emits the Tier-2 serving bundles (`mix tessera.bundles`
# → priv/static/tessera) BEFORE boot — without them the /holo_runtime glue
# 404s on tessera-runtime.esm.js and the core-claim specs fail.
#
# Demos are ALWAYS stopped on exit (trap). KEEP_DEMOS=1 leaves them running
# for debugging (you must then stop them yourself).
#
# Usage: scripts/acceptance.sh   (from anywhere; paths resolve to the repo)
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOGDIR="$(mktemp -d "${TMPDIR:-/tmp}/tessera-acceptance.XXXXXX")"
T0=$(date +%s)

# name|pid|rc|secs bookkeeping (bash 3.2-safe indexed arrays)
JOB_NAMES=()
JOB_PIDS=()

log() { printf '%s\n' "$*"; }

# run_job <name> <dir> <cmd...> — background job, logs + timing under $LOGDIR
run_job() {
  local name="$1" dir="$2"
  shift 2
  (
    cd "$dir" || exit 1
    local s e rc
    s=$(date +%s)
    "$@" > "$LOGDIR/$name.log" 2>&1
    rc=$?
    e=$(date +%s)
    echo $((e - s)) > "$LOGDIR/$name.secs"
    exit $rc
  ) &
  JOB_NAMES+=("$name")
  JOB_PIDS+=("$!")
}

# wait_jobs — waits for every run_job, prints a per-job line, returns fail count
wait_jobs() {
  local fails=0 i name pid rc secs
  for i in "${!JOB_PIDS[@]}"; do
    name="${JOB_NAMES[$i]}"
    pid="${JOB_PIDS[$i]}"
    rc=0
    wait "$pid" || rc=$?
    secs="?"
    [ -f "$LOGDIR/$name.secs" ] && secs=$(cat "$LOGDIR/$name.secs")
    if [ "$rc" -eq 0 ]; then
      log "  PASS  $name (${secs}s)"
    else
      log "  FAIL  $name (${secs}s, exit $rc) — log: $LOGDIR/$name.log"
      tail -25 "$LOGDIR/$name.log" | sed 's/^/        /'
      fails=$((fails + 1))
    fi
  done
  JOB_NAMES=()
  JOB_PIDS=()
  return "$fails"
}

stop_demos() {
  local port pids
  for port in 5586 5587; do
    pids=$(lsof -ti "tcp:$port" -sTCP:LISTEN 2>/dev/null || true)
    if [ -n "$pids" ]; then
      # shellcheck disable=SC2086
      kill $pids 2>/dev/null || true
    fi
  done
}

cleanup() {
  if [ "${KEEP_DEMOS:-0}" = "1" ]; then
    log "KEEP_DEMOS=1 — leaving demos up (stop them yourself: ports 5586/5587)"
  else
    stop_demos
  fi
}
trap cleanup EXIT

# ---------------------------------------------------------------- prerequisites
# Warm path: skip installs when the tree already has them. Cold path: install.
ensure_npm() { # <dir>
  if [ ! -d "$1/node_modules" ]; then
    log "  npm ci in ${1#"$ROOT"/} (cold)"
    (cd "$1" && npm ci --no-audit --no-fund) > "$LOGDIR/npm-$(basename "$1").log" 2>&1 || {
      log "  npm ci failed in $1 — $LOGDIR/npm-$(basename "$1").log"
      exit 1
    }
  fi
}

log "== prerequisites =="
ensure_npm "$ROOT/js"
ensure_npm "$ROOT/examples/persona_kit"
ensure_npm "$ROOT/demo/plain_html"
ensure_npm "$ROOT/demo/e2e"
if [ ! -d "$ROOT/deps" ]; then
  (cd "$ROOT" && mix deps.get) > "$LOGDIR/deps-root.log" 2>&1 || { log "mix deps.get (root) failed"; exit 1; }
fi
if [ ! -d "$ROOT/examples/persona_kit/deps" ]; then
  (cd "$ROOT/examples/persona_kit" && mix deps.get) > "$LOGDIR/deps-pk.log" 2>&1 || { log "mix deps.get (persona_kit) failed"; exit 1; }
fi
if [ ! -d "$ROOT/demo/hologram_app/deps" ]; then
  (cd "$ROOT/demo/hologram_app" && mix deps.get) > "$LOGDIR/deps-holo.log" 2>&1 || { log "mix deps.get (hologram_app) failed"; exit 1; }
fi
# The plain-HTML build imports persona_kit's contract.generated.mjs siblings
# (Elixir-compiler artifacts). The parallel Hologram boot also emits them, but
# racing the plain build against that is a bug — ensure they exist BEFORE the
# fan-out (warm path: the files are already there, this is a no-op).
if ! ls "$ROOT"/examples/persona_kit/lib/persona_kit/*.contract.generated.mjs > /dev/null 2>&1; then
  log "  generating persona_kit contract modules (cold)"
  (cd "$ROOT/examples/persona_kit" && mix deps.get && mix compile) > "$LOGDIR/pk-compile.log" 2>&1 || {
    log "  persona_kit mix compile failed — $LOGDIR/pk-compile.log"
    exit 1
  }
fi

# ------------------------------------------------------------------ unit suites
log "== unit suites (parallel) =="
U0=$(date +%s)
run_job exunit-lib "$ROOT" mix test.fast
run_job exunit-persona_kit "$ROOT/examples/persona_kit" mix test.fast
# WTR's dev server defaults to :8000 — two concurrent runs would EADDRINUSE,
# so pin distinct ports.
run_job wtr-fast "$ROOT/js" npm run test:fast -- --port 8000
run_job wtr-conformance "$ROOT/js" npm run test:conformance -- --port 8001
UNIT_FAILS=0
wait_jobs || UNIT_FAILS=$?
U1=$(date +%s)
log "  unit phase wall: $((U1 - U0))s"

# -------------------------------------------------------------------- e2e-smoke
log "== e2e-smoke (parallel boots, one boot for all @fast specs) =="
E0=$(date +%s)

boot_holo() {
  cd "$ROOT/demo/hologram_app" || return 1
  # Gate the whole chain on HOLOGRAM_START (Hologram compiler-state hazard,
  # see ci.yml e2e-smoke).
  export HOLOGRAM_START=1
  mix tessera.install || return 1
  # Emit the Tier-2 serving bundles BEFORE boot (the root-cause fix).
  mix tessera.bundles || return 1
  nohup mix holo > "$LOGDIR/holo-server.log" 2>&1 &
  local i
  for i in $(seq 1 120); do
    curl -sf -o /dev/null http://localhost:5586/ && return 0
    sleep 1
  done
  echo "Hologram demo did not come up on :5586" >&2
  tail -30 "$LOGDIR/holo-server.log" >&2
  return 1
}

boot_plain() {
  cd "$ROOT/demo/plain_html" || return 1
  npm run build || return 1
  nohup npm run serve > "$LOGDIR/plain-server.log" 2>&1 &
  local i
  for i in $(seq 1 60); do
    curl -sf -o /dev/null http://localhost:5587/ && return 0
    sleep 1
  done
  echo "plain demo did not come up on :5587" >&2
  tail -20 "$LOGDIR/plain-server.log" >&2
  return 1
}

B0=$(date +%s)
boot_holo > "$LOGDIR/boot-holo.log" 2>&1 &
HOLO_PID=$!
boot_plain > "$LOGDIR/boot-plain.log" 2>&1 &
PLAIN_PID=$!
H=0
P=0
wait "$HOLO_PID" || H=$?
wait "$PLAIN_PID" || P=$?
B1=$(date +%s)
if [ "$H" -ne 0 ] || [ "$P" -ne 0 ]; then
  log "  FAIL  demo boots (holo=$H plain=$P, wall $((B1 - B0))s)"
  [ "$H" -ne 0 ] && tail -25 "$LOGDIR/boot-holo.log" | sed 's/^/        /'
  [ "$P" -ne 0 ] && tail -25 "$LOGDIR/boot-plain.log" | sed 's/^/        /'
  exit 1
fi
log "  PASS  demo boots (parallel, wall $((B1 - B0))s)"

C0=$(date +%s)
CYPRESS_RC=0
(cd "$ROOT/demo/e2e" && npm run test:fast) > "$LOGDIR/cypress.log" 2>&1 || CYPRESS_RC=$?
C1=$(date +%s)
if [ "$CYPRESS_RC" -eq 0 ]; then
  log "  PASS  cypress @fast ($((C1 - C0))s)"
  grep -E "All specs passed|Tests:|Passing:" "$LOGDIR/cypress.log" | head -4 | sed 's/^/        /' || true
else
  log "  FAIL  cypress @fast ($((C1 - C0))s) — log: $LOGDIR/cypress.log"
  grep -E "failing|passing|pending|✖|×" "$LOGDIR/cypress.log" | head -10 | sed 's/^/        /' || true
fi
E1=$(date +%s)
log "  e2e phase wall: $((E1 - E0))s (boots $((B1 - B0))s + cypress $((C1 - C0))s)"

# ---------------------------------------------------------------------- summary
T1=$(date +%s)
FAILS=$((UNIT_FAILS + (CYPRESS_RC != 0 ? 1 : 0)))
log "== acceptance summary =="
log "  total wall: $((T1 - T0))s  (unit $((U1 - U0))s + e2e $((E1 - E0))s)"
log "  logs: $LOGDIR"
if [ "$FAILS" -eq 0 ]; then
  log "  GREEN"
else
  log "  RED ($FAILS failing component(s))"
fi
exit "$FAILS"