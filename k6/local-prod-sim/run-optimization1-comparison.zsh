#!/bin/zsh
set -euo pipefail

script_dir="${0:A:h}"
frontend_repo="${script_dir:h:h}"
backend_repo="${BACKEND_REPO:-${frontend_repo:h}/stepv2-backend}"
capacity_root="${XDG_DATA_HOME:-$HOME/.local/share}/stepv2-capacity"
capacity_vm="${CAPACITY_VM:-stepv2-prod-sim}"
capacity_db="${CAPACITY_DB:-stepv2_capacity_prod_20260818}"
pg_bin="${CAPACITY_PG_BIN:-/opt/homebrew/opt/postgresql@18/bin}"
pgbouncer_config="$capacity_root/pgbouncer.ini"
pgbouncer_pidfile="$capacity_root/pgbouncer.pid"
pgbouncer_ownerfile="$capacity_root/pgbouncer.owner"
rate_rps="${RPS:-160}"
expected_corpus_sha="efb60729d60dd72ec8532156b1cc8e1ae041147f290d68ab5f5c087e025a4d3e"
expected_fixture_sha="1f07e854c2d05845e307cc294cd1821cf0b56f3f716aa74bca5061d1454bcc93"
expected_fixture_revision="capacity-fixture-v1:a75bcee0"

[[ "$rate_rps" == "160" || "$rate_rps" == "260" ]] || {
  print -u2 "RPS must be 160 or 260"
  exit 2
}
warmup_iterations="$((rate_rps * 5))"
print -r -- "$capacity_db" | grep -Eq '^stepv2_capacity_[A-Za-z0-9_]+$' || {
  print -u2 "CAPACITY_DB must start with stepv2_capacity_ and contain only letters, digits, or underscores"
  exit 2
}
[[ -d "$backend_repo/src" ]] || { print -u2 "backend repo not found: $backend_repo"; exit 2; }
[[ -f "$capacity_root/sanitized-benchmark-20260818-v2.dump" ]] || {
  print -u2 "missing private sanitized corpus; follow LOCAL-PROD-SIM-RUNBOOK.md once"
  exit 2
}
[[ -f "$capacity_root/users-20260818-v2.json" ]] || {
  print -u2 "missing private fixture; follow LOCAL-PROD-SIM-RUNBOOK.md once"
  exit 2
}
[[ "$(shasum -a 256 "$capacity_root/sanitized-benchmark-20260818-v2.dump" | awk '{print $1}')" == "$expected_corpus_sha" ]] || {
  print -u2 "private corpus checksum mismatch"
  exit 2
}
[[ "$(shasum -a 256 "$capacity_root/users-20260818-v2.json" | awk '{print $1}')" == "$expected_fixture_sha" ]] || {
  print -u2 "private fixture checksum mismatch"
  exit 2
}
[[ "$(jq -r '.metadata.fixtureRevision // empty' "$capacity_root/users-20260818-v2.json")" == "$expected_fixture_revision" ]] || {
  print -u2 "private fixture revision mismatch"
  exit 2
}

umask 077
mkdir -p "$capacity_root/runs"
lock_dir="$capacity_root/capacity-workflow.lock"
mkdir "$lock_dir" 2>/dev/null || {
  print -u2 "another local capacity comparison is already running: $lock_dir"
  exit 2
}
run_stamp="$(date -u +%Y%m%dT%H%M%SZ)"
pair_epoch_ms="$(($(date -u +%s) * 1000))"
result_dir="$capacity_root/runs/optimization1-$run_stamp-${rate_rps}rps"
mkdir -p "$result_dir"
process_start="$(ps -p $$ -o lstart= | sed 's/^ *//')"
node -e 'require("fs").writeFileSync(process.argv[1],`pid=${process.argv[2]}\nstart=${process.argv[3]}\nrun_id=${process.argv[4]}\n`,{mode:0o600})' \
  "$lock_dir/owner" "$$" "$process_start" "optimization1-$run_stamp-${rate_rps}rps"

source_tar="$(mktemp "$capacity_root/optimization1-source.XXXXXX.tar")"
source_manifest="$(mktemp "$capacity_root/optimization1-source.XXXXXX.manifest")"
cleanup_source_tar() {
  rm -f -- "$source_tar" "$source_manifest"
}
teardown_done=false

stop_owned_pgbouncer() {
  pool_pid="$(cat "$pgbouncer_pidfile" 2>/dev/null || true)"
  if [[ ! "$pool_pid" =~ ^[0-9]+$ ]] || ! kill -0 "$pool_pid" 2>/dev/null; then
    rm -f -- "$pgbouncer_pidfile" "$pgbouncer_ownerfile"
    return 0
  fi

  owner_pid="$(sed -n '1p' "$pgbouncer_ownerfile" 2>/dev/null || true)"
  owner_started="$(sed -n '2p' "$pgbouncer_ownerfile" 2>/dev/null || true)"
  current_started="$(ps -p "$pool_pid" -o lstart= 2>/dev/null | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
  current_command="$(ps -p "$pool_pid" -o command= 2>/dev/null || true)"
  current_executable="$(ps -p "$pool_pid" -o comm= 2>/dev/null || true)"
  if [[ "$owner_pid" != "$pool_pid" || -z "$owner_started" ||
        "$owner_started" != "$current_started" ||
        "$current_command" != *"$pgbouncer_config"* ||
        "$current_executable" != *pgbouncer ]]; then
    print -u2 "refusing to signal unverified PID $pool_pid from $pgbouncer_pidfile"
    return 2
  fi

  kill -TERM "$pool_pid"
  for _ in {1..25}; do
    kill -0 "$pool_pid" 2>/dev/null || break
    sleep 0.2
  done
  kill -0 "$pool_pid" 2>/dev/null && kill -KILL "$pool_pid" 2>/dev/null
  rm -f -- "$pgbouncer_pidfile" "$pgbouncer_ownerfile"
}

record_owned_pgbouncer() {
  for _ in {1..25}; do
    pool_pid="$(cat "$pgbouncer_pidfile" 2>/dev/null || true)"
    [[ "$pool_pid" =~ ^[0-9]+$ ]] && kill -0 "$pool_pid" 2>/dev/null && break
    sleep 0.2
  done
  [[ "$pool_pid" =~ ^[0-9]+$ ]] && kill -0 "$pool_pid" 2>/dev/null || {
    print -u2 "PgBouncer did not publish a live PID"
    return 2
  }
  current_started="$(ps -p "$pool_pid" -o lstart= 2>/dev/null | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
  current_command="$(ps -p "$pool_pid" -o command= 2>/dev/null || true)"
  current_executable="$(ps -p "$pool_pid" -o comm= 2>/dev/null || true)"
  [[ -n "$current_started" && "$current_command" == *"$pgbouncer_config"* &&
     "$current_executable" == *pgbouncer ]] || {
    print -u2 "new PgBouncer process failed ownership verification"
    return 2
  }
  {
    print -r -- "$pool_pid"
    print -r -- "$current_started"
  } > "$pgbouncer_ownerfile"
}

teardown() {
  set +e
  [[ "$teardown_done" == true ]] && return
  teardown_done=true
  cleanup_source_tar
  rm -f -- "$result_dir/off-fixture.json" "$result_dir/on-fixture.json"
  /opt/homebrew/bin/limactl shell "$capacity_vm" -- \
    pm2 delete steps-tracker-prod-sim >/dev/null 2>&1
  /opt/homebrew/bin/limactl stop "$capacity_vm" >/dev/null 2>&1
  stop_owned_pgbouncer
  if "$pg_bin/pg_ctl" -D "$capacity_root/postgres18" status >/dev/null 2>&1; then
    "$pg_bin/pg_ctl" -D "$capacity_root/postgres18" stop -m fast >/dev/null
  fi
  mv "$lock_dir" "$result_dir/released-capacity-lock" >/dev/null 2>&1
}
trap 'teardown' EXIT
trap 'exit 130' INT TERM
trap 'exit_code=$?; teardown; exit $exit_code' ZERR

print "[1/5] Packaging current backend source"
cd "$backend_repo"
git ls-files -z --cached --others --exclude-standard -- \
  package.json package-lock.json src prisma/schema.prisma prisma/migrations \
  | sort -z > "$source_manifest"
sensitive_runtime_path="$(tr '\0' '\n' < "$source_manifest" | \
  grep -Eim1 '(^|/)(\.env($|\.)|CLAUDE\.local\.md$|[^/]*service-account[^/]*\.json$|id_(rsa|ed25519)$|[^/]+\.(pem|key|p12|pfx|jks|keystore)$|credentials\.json$)' || true)"
[[ -z "$sensitive_runtime_path" ]] || {
  print -u2 "refusing sensitive runtime path in backend artifact: $sensitive_runtime_path"
  exit 2
}
source_sha="$(xargs -0 shasum -a 256 < "$source_manifest" | shasum -a 256 | awk '{print $1}')"
COPYFILE_DISABLE=1 tar --no-xattrs --null -T "$source_manifest" -cf "$source_tar"
cd "$frontend_repo"
backend_revision="${source_sha[1,12]}"
artifact_dir="/opt/stepv2-backend-opt1-$backend_revision"

print "[2/5] Starting isolated 2-vCPU/2-GiB environment"
if ! "$pg_bin/pg_ctl" -D "$capacity_root/postgres18" status >/dev/null 2>&1; then
  "$pg_bin/pg_ctl" -D "$capacity_root/postgres18" \
    -l "$capacity_root/postgres18.log" \
    -o '-h 127.0.0.1 -p 55432' start >/dev/null
fi
/opt/homebrew/bin/limactl start "$capacity_vm" >/dev/null
actual_data_dir="$("$pg_bin/psql" -h 127.0.0.1 -p 55432 -d postgres -Atc 'SHOW data_directory')"
[[ "$actual_data_dir" == "$capacity_root/postgres18" ]] || {
  print -u2 "refusing destructive DB setup: unexpected PostgreSQL data directory $actual_data_dir"
  exit 2
}

# Remove only obsolete benchmark artifacts that contain files the old packager
# should never have copied. Current artifacts are source-hash allowlisted.
/opt/homebrew/bin/limactl shell "$capacity_vm" -- bash -lc '
  for candidate in /opt/stepv2-backend-*; do
    test -d "$candidate" || continue
    if find "$candidate" -maxdepth 3 -type f \( -name .env -o -name CLAUDE.local.md -o -iname "*service-account*.json" \) -print -quit | grep -q .; then
      sudo rm -rf -- "$candidate"
    fi
  done
'

artifact_exists="$(/opt/homebrew/bin/limactl shell "$capacity_vm" -- \
  bash -lc 'test -f "$1/.capacity-source-sha" && cat "$1/.capacity-source-sha" || true' \
  _ "$artifact_dir")"
if [[ "$artifact_exists" != "$source_sha" ]]; then
  /opt/homebrew/bin/limactl shell "$capacity_vm" -- \
    bash -lc 'set -e; test ! -e "$1"; sudo install -d -m 0755 -o "$(id -un)" -g "$(id -gn)" "$1"; tar -xf - -C "$1"' \
    _ "$artifact_dir" < "$source_tar"
  /opt/homebrew/bin/limactl shell "$capacity_vm" -- bash -lc '
    set -euo pipefail
    cd "$1"
    npm ci --ignore-scripts
    npx prisma generate
    printf "%s\n" "$2" > .capacity-source-sha
  ' _ "$artifact_dir" "$source_sha"
fi
cleanup_source_tar

run_variant() {
  variant="$1"
  flag_value=false
  [[ "$variant" == "on" ]] && flag_value=true
  run_id="opt1-${variant}-${rate_rps}rps-$run_stamp"
  vm_out_log="/tmp/$run_id-out.log"
  vm_error_log="/tmp/$run_id-error.log"

  print "[3/5] Running optimization 1 $variant at $rate_rps RPS"
  /opt/homebrew/bin/limactl shell "$capacity_vm" -- \
    bash -lc 'pm2 delete steps-tracker-prod-sim >/dev/null 2>&1 || true'

  stop_owned_pgbouncer

  "$pg_bin/dropdb" -h 127.0.0.1 -p 55432 --if-exists "$capacity_db"
  "$pg_bin/createdb" -h 127.0.0.1 -p 55432 "$capacity_db"
  "$pg_bin/pg_restore" -h 127.0.0.1 -p 55432 -d "$capacity_db" \
    --no-owner --no-acl --exit-on-error \
    "$capacity_root/sanitized-benchmark-20260818-v2.dump"
  "$pg_bin/psql" -h 127.0.0.1 -p 55432 -d "$capacity_db" -v ON_ERROR_STOP=1 \
    -f "$script_dir/validate-sanitization.sql" > "$result_dir/$run_id-validation.log"
  local_fixture="$result_dir/$variant-fixture.json"
  node "$script_dir/remint-local-fixture.mjs" \
    --input "$capacity_root/users-20260818-v2.json" \
    --output "$local_fixture" \
    --database-url "postgresql://rohan@127.0.0.1:55432/$capacity_db" \
    --backend-repo "$backend_repo" \
    --epoch-ms "$pair_epoch_ms"
  "$pg_bin/psql" -h 127.0.0.1 -p 55432 -d "$capacity_db" -v ON_ERROR_STOP=1 \
    -c "INSERT INTO app_settings (key,value,updated_at) VALUES
      ('capacityPhaseMetricsV1Enabled','true'::jsonb,now()),
      ('raceResolutionQueuedGenerationMergeV1Enabled','$flag_value'::jsonb,now()),
      ('capacityBenchmarkCorpusMarker','\"$expected_corpus_sha\"'::jsonb,now())
      ON CONFLICT (key) DO UPDATE SET value=EXCLUDED.value,updated_at=now()" >/dev/null

  /opt/homebrew/bin/pgbouncer -d "$pgbouncer_config"
  record_owned_pgbouncer
  /opt/homebrew/bin/limactl shell "$capacity_vm" -- bash -lc \
    'sudo systemctl start redis-server nginx; redis-cli FLUSHDB >/dev/null'
  /opt/homebrew/bin/limactl shell "$capacity_vm" -- bash -lc '
    cd "$1"
    NODE_ENV=production PORT=3002 \
      DATABASE_URL="$3" REDIS_URL=redis://127.0.0.1:6379/0 \
      SESSION_TOKEN_SECRET=capacity-local-only-not-a-secret \
      PRISMA_QUERY_EVENTS_ENABLED=true \
      CRON_START_DELAY_MS=0 \
      CAPACITY_RUN_ID="$2" CAPACITY_REPEAT=1 \
      pm2 start src/capacityLocal.js --name steps-tracker-prod-sim -i 2 \
      --max-memory-restart 600M --merge-logs \
      --output "$4" --error "$5" --update-env >/dev/null
  ' _ "$artifact_dir" "$run_id" \
    "postgresql://rohan@host.lima.internal:56432/$capacity_db" \
    "$vm_out_log" "$vm_error_log"

  sleep 20
  quiet=0
  for elapsed in {1..90}; do
    outstanding="$("$pg_bin/psql" -h 127.0.0.1 -p 55432 -d "$capacity_db" -Atc \
      "SELECT count(*) FROM race_resolution_jobs_v2 WHERE state IN ('queued','running')")"
    if [[ "$outstanding" == 0 ]]; then quiet=$((quiet + 1)); else quiet=0; fi
    [[ "$quiet" -ge 5 ]] && break
    sleep 1
  done
  [[ "$quiet" -ge 5 ]] || { print -u2 "$variant startup queue failed to settle"; return 3; }

  /opt/homebrew/bin/limactl shell "$capacity_vm" -- bash -lc 'pm2 jlist' \
    | jq '[.[] | select(.name=="steps-tracker-prod-sim") |
        {status:.pm2_env.status,restarts:.pm2_env.restart_time,
         cwd:.pm2_env.pm_cwd,execPath:.pm2_env.pm_exec_path,memory:.monit.memory}]' \
    > "$result_dir/$run_id-pm2-pre.json"
  jq -e --arg cwd "$artifact_dir" --arg exec "$artifact_dir/src/capacityLocal.js" '
    length==2 and all(.[]; .status=="online" and .restarts==0 and
      .cwd==$cwd and .execPath==$exec)' "$result_dir/$run_id-pm2-pre.json" >/dev/null
  /opt/homebrew/bin/limactl shell "$capacity_vm" -- bash -lc '
    cd "$1"
    DATABASE_URL="$2" CAPACITY_EXPECTED_DB="$3" CAPACITY_EXPECTED_MARKER="$4" \
      node -e '"'"'const { prisma: db } = require("./src/db");
      db.$queryRawUnsafe(`SELECT current_database() AS database,
        (SELECT value::text FROM app_settings
         WHERE key = $1) AS marker`, "capacityBenchmarkCorpusMarker")
        .then(([row]) => {
          if (row?.database !== process.env.CAPACITY_EXPECTED_DB ||
              JSON.parse(row?.marker || "null") !== process.env.CAPACITY_EXPECTED_MARKER) {
            throw new Error("capacity application database identity check failed");
          }
        })
        .finally(() => db.$disconnect())
        .catch((error) => { console.error(error.message); process.exit(1); });'"'"'
  ' _ "$artifact_dir" \
    "postgresql://rohan@host.lima.internal:56432/$capacity_db" \
    "$capacity_db" "$expected_corpus_sha"
  curl -fsS http://127.0.0.1:3302/health > "$result_dir/$run_id-health.json"

  if /opt/homebrew/bin/k6 run \
    -e BASE_URL=http://127.0.0.1:3302 \
    -e USERS_FILE="$local_fixture" \
    -e TARGET_RUNG="diagnostic_${rate_rps}rps" \
    -e CLIENT_COHORT=ios_bara_2_3_7_ads_payout \
    -e BACKEND_REVISION="$backend_revision" \
    -e BACKEND_FLAGS="queued-generation-merge=$flag_value" \
    -e BACKEND_CONFIG=prod-sim-2vcpu-2gb-node24-pgbouncer25 \
    -e WORKER_COUNT=2 -e PGBOUNCER_POOL=25 \
    -e REDIS_STATE=empty-at-start-startup-queue-drained \
    -e CRON_COHORT=capacity-http-resolution-only \
    -e MATCHED_PAIR_EPOCH_MS="$pair_epoch_ms" \
    -e WARMUP_ITERATIONS="$warmup_iterations" \
    -e DURATION_OVERRIDE=35s -e ALLOW_DIAGNOSTIC_OVERRIDE=1 \
    -e RESOLUTION_DRAIN_TIMEOUT_MS=60000 \
    -e RUN_ID="$run_id" -e REPEAT_INDEX=1 \
    -e SUMMARY_JSON="$result_dir/$variant-summary.json" \
    --out json="$result_dir/$variant-samples.json" \
    "$frontend_repo/k6/prod-mix-load-test.js" \
    > "$result_dir/$variant-k6.log" 2>&1; then
    k6_exit=0
  else
    k6_exit=$?
  fi
  print -r -- "$k6_exit" > "$result_dir/$variant-k6-exit.txt"
  rm -f -- "$local_fixture"

  immediate="$("$pg_bin/psql" -h 127.0.0.1 -p 55432 -d "$capacity_db" -Atc \
    "SELECT count(*) FROM race_resolution_jobs_v2 WHERE state IN ('queued','running')")"
  print -r -- "$immediate" > "$result_dir/$variant-post-k6-backlog.txt"
  quiet=0
  drain_seconds=0
  while [[ "$drain_seconds" -lt 90 ]]; do
    outstanding="$("$pg_bin/psql" -h 127.0.0.1 -p 55432 -d "$capacity_db" -Atc \
      "SELECT count(*) FROM race_resolution_jobs_v2 WHERE state IN ('queued','running')")"
    if [[ "$outstanding" == 0 ]]; then quiet=$((quiet + 1)); else quiet=0; fi
    [[ "$quiet" -ge 5 ]] && break
    sleep 1
    drain_seconds=$((drain_seconds + 1))
  done
  [[ "$quiet" -ge 5 ]] || { print -u2 "$variant post-traffic queue failed to settle"; return 4; }
  print -r -- "$drain_seconds" > "$result_dir/$variant-post-k6-drain-seconds.txt"
  /opt/homebrew/bin/limactl shell "$capacity_vm" -- \
    bash -lc 'cat "$1" "$2" 2>/dev/null; rm -f -- "$1" "$2"' \
    _ "$vm_out_log" "$vm_error_log" \
    > "$result_dir/$variant-backend.log" 2>&1

  /opt/homebrew/bin/limactl shell "$capacity_vm" -- bash -lc 'pm2 jlist' \
    | jq '[.[] | select(.name=="steps-tracker-prod-sim") |
        {status:.pm2_env.status,restarts:.pm2_env.restart_time,
         cwd:.pm2_env.pm_cwd,execPath:.pm2_env.pm_exec_path,
         memory:.monit.memory,cpu:.monit.cpu}]' \
    > "$result_dir/$run_id-pm2-post.json"
  jq -e --arg cwd "$artifact_dir" --arg exec "$artifact_dir/src/capacityLocal.js" '
    length==2 and all(.[]; .status=="online" and .restarts==0 and
      .cwd==$cwd and .execPath==$exec)' "$result_dir/$run_id-pm2-post.json" >/dev/null
}

run_variant off
run_variant on

print "[4/5] Comparing matched results"
node "$script_dir/summarize-optimization1.mjs" \
  --off "$result_dir/off-summary.json" \
  --on "$result_dir/on-summary.json" \
  --off-raw "$result_dir/off-samples.json" \
  --on-raw "$result_dir/on-samples.json" \
  --off-exit "$result_dir/off-k6-exit.txt" \
  --on-exit "$result_dir/on-k6-exit.txt" \
  --off-post-k6-backlog "$result_dir/off-post-k6-backlog.txt" \
  --on-post-k6-backlog "$result_dir/on-post-k6-backlog.txt" \
  --off-post-k6-drain "$result_dir/off-post-k6-drain-seconds.txt" \
  --on-post-k6-drain "$result_dir/on-post-k6-drain-seconds.txt" \
  --warmup-iterations "$warmup_iterations" \
  --output "$result_dir/result.md"

print "[5/5] Complete; teardown runs automatically"
print "Artifacts: $result_dir"
