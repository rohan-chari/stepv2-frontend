#!/bin/zsh
set -euo pipefail

script_dir="${0:A:h}"
frontend_repo="${script_dir:h:h}"
backend_repo="${BACKEND_REPO:-${frontend_repo:h}/stepv2-backend}"
capacity_root="${XDG_DATA_HOME:-$HOME/.local/share}/stepv2-capacity"
capacity_vm="${CAPACITY_VM:-stepv2-prod-sim}"
capacity_db="${CAPACITY_DB:-stepv2_capacity_prod_20260818}"
pg_bin="${CAPACITY_PG_BIN:-/opt/homebrew/opt/postgresql@18/bin}"
readme="$frontend_repo/k6/README.md"
expected_corpus_sha="efb60729d60dd72ec8532156b1cc8e1ae041147f290d68ab5f5c087e025a4d3e"
expected_fixture_sha="1f07e854c2d05845e307cc294cd1821cf0b56f3f716aa74bca5061d1454bcc93"
expected_fixture_revision="capacity-fixture-v1:a75bcee0"
corpus="$capacity_root/sanitized-benchmark-20260818-v2.dump"
fixture="$capacity_root/users-20260818-v2.json"
lock_dir="$capacity_root/capacity-workflow.lock"
pgbouncer_pidfile="$capacity_root/pgbouncer.pid"
pgbouncer_ownerfile="$capacity_root/pgbouncer.owner"
pgbouncer_config="$capacity_root/pgbouncer.ini"
run_stamp="$(date -u +%Y%m%dT%H%M%SZ)"
run_id="daily-$run_stamp-$$"
local_date="$(TZ=America/New_York date +%F)"
result_dir="$capacity_root/runs/$run_id"
preliminary="$result_dir/preliminary-result-v1.json"
recovery="$result_dir/recovery-result-v1.json"
cleanup_evidence="$result_dir/teardown-v1.json"
record_file="$result_dir/readme-record-v1.json"
source_tar="$result_dir/fetched-main.tar"
local_fixture="$result_dir/local-fixture.json"
classification="invalid"
reason="setup did not complete"
backend_sha=""
snapshot_hash=""
selection_ready=false
append_succeeded=false
phase_one_ok=true
resolution_concurrency_per_worker="${ASYNC_RACE_RESOLUTION_CONCURRENCY_OVERRIDE:-1}"
[[ "$resolution_concurrency_per_worker" == <1-3> ]] || {
  print -u2 -- "ASYNC_RACE_RESOLUTION_CONCURRENCY_OVERRIDE must be 1, 2, or 3"
  exit 2
}

umask 077
mkdir -p "$capacity_root/runs"

update_preliminary() {
  node "$script_dir/update-preliminary.mjs" --file "$preliminary" --phase "$1" --status "$classification" --reason "$reason" \
    --backend-sha "$backend_sha" --snapshot-hash "$snapshot_hash" && \
  node "$script_dir/update-preliminary.mjs" --file "$recovery" --phase "$1" --status "$classification" --reason "$reason" \
    --backend-sha "$backend_sha" --snapshot-hash "$snapshot_hash"
}

stop_owned_pgbouncer() {
  local pool_pid owner_start actual_start actual_command
  pool_pid="$(cat "$pgbouncer_pidfile" 2>/dev/null || true)"
  owner_start="$(cat "$pgbouncer_ownerfile" 2>/dev/null || true)"
  if [[ "$pool_pid" == <-> ]] && kill -0 "$pool_pid" 2>/dev/null; then
    actual_start="$(ps -p "$pool_pid" -o lstart= | sed 's/^ *//')"
    actual_command="$(ps -p "$pool_pid" -o command=)"
    [[ "$actual_start" == "$owner_start" && "$actual_command" == *pgbouncer*"$pgbouncer_config"* ]] || return 1
    kill "$pool_pid" || return 1
    for _ in {1..20}; do kill -0 "$pool_pid" 2>/dev/null || break; sleep 0.25; done
    kill -0 "$pool_pid" 2>/dev/null && return 1
  fi
  rm -f -- "$pgbouncer_pidfile" "$pgbouncer_ownerfile"
}

finalize_phase_one() {
  set +e
  local pm2_cleanup=ok lima_cleanup=ok pool_cleanup=ok postgres_cleanup=ok temp_cleanup=ok verification=ok
  touch "$result_dir/stop-server-sampler"
  [[ -n "${server_sampler_pid:-}" ]] && wait "$server_sampler_pid" 2>/dev/null
  if /opt/homebrew/bin/limactl list "$capacity_vm" --json 2>/dev/null | jq -e 'if type=="array" then any(.[];.status=="Running") else .status=="Running" end' >/dev/null 2>&1; then
    /opt/homebrew/bin/limactl shell "$capacity_vm" -- bash -lc 'pm2 delete steps-tracker-prod-sim >/dev/null 2>&1 || true' || pm2_cleanup=failed
    if [[ -n "${run_id:-}" ]]; then
      /opt/homebrew/bin/limactl shell "$capacity_vm" -- rm -f -- "/tmp/$run_id-settings.json" "/tmp/$run_id-start.mjs" "/tmp/$run_id-backend-out.log" "/tmp/$run_id-backend-error.log" || temp_cleanup=failed
    fi
    if [[ -n "${artifact_vm:-}" ]]; then
      /opt/homebrew/bin/limactl shell "$capacity_vm" -- bash -lc 'case "$1" in /opt/stepv2-backend-daily-daily-*) sudo find "$1" -depth -delete;; *) exit 2;; esac' _ "$artifact_vm" || temp_cleanup=failed
    fi
    /opt/homebrew/bin/limactl stop "$capacity_vm" >/dev/null 2>&1 || lima_cleanup=failed
  fi
  stop_owned_pgbouncer || pool_cleanup=failed
  if "$pg_bin/pg_ctl" -D "$capacity_root/postgres18" status >/dev/null 2>&1; then
    "$pg_bin/pg_ctl" -D "$capacity_root/postgres18" stop -m fast >/dev/null 2>&1 || postgres_cleanup=failed
  fi
  rm -f -- "$local_fixture" "$result_dir/stop-server-sampler" || temp_cleanup=failed
  /opt/homebrew/bin/limactl list "$capacity_vm" --json 2>/dev/null | jq -e 'if type=="array" then all(.[];.status!="Running") else .status!="Running" end' >/dev/null || verification=failed
  "$pg_bin/pg_ctl" -D "$capacity_root/postgres18" status >/dev/null 2>&1 && verification=failed
  for port in 3302 56432 55432; do
    lsof -nP -iTCP:$port -sTCP:LISTEN >/dev/null 2>&1 && verification=failed
  done
  [[ "$pm2_cleanup" == ok && "$lima_cleanup" == ok && "$pool_cleanup" == ok && "$postgres_cleanup" == ok && "$temp_cleanup" == ok && "$verification" == ok ]] || {
    phase_one_ok=false
    classification=invalid
    reason="cleanup verification failed"
  }
  if ! node -e 'const fs=require("fs");const [p,...v]=process.argv.slice(1);const keys=["pm2","lima","pgbouncer","postgres","temporaryFiles","verification"],tmp=`${p}.tmp.${process.pid}`;fs.writeFileSync(tmp,JSON.stringify({schemaVersion:"daily-k6-teardown-v1",completedAt:new Date().toISOString(),outcomes:Object.fromEntries(keys.map((k,i)=>[k,v[i]]))},null,2)+"\n",{mode:0o600});fs.renameSync(tmp,p)' \
    "$cleanup_evidence" "$pm2_cleanup" "$lima_cleanup" "$pool_cleanup" "$postgres_cleanup" "$temp_cleanup" "$verification"; then
    phase_one_ok=false; classification=invalid; reason="teardown evidence persistence failed"
  fi
  update_preliminary teardown-complete || { classification=invalid; reason="preliminary result persistence failed"; }
  set -e
}

finalize_phase_two() {
  set +e
  if [[ "$selection_ready" == true ]]; then
    local tested_rps standard day readme_hash fingerprint initial_floor initial_ceiling floor ceiling rough_dau backend_value snapshot_value series
    update_preliminary result-ready-for-readme || { classification=invalid; reason="final private result persistence failed"; }
    tested_rps="$(jq -r .rps "$result_dir/selection.json")"
    standard="$(jq -r .standard "$result_dir/selection.json")"
    day="$(jq -r .day "$result_dir/selection.json")"
    readme_hash="$(jq -r .readmeHash "$result_dir/selection.json")"
    fingerprint="$(cat "$result_dir/fingerprint.txt")"
    initial_floor="$(jq -r '.floor // empty' "$result_dir/selection.json")"
    initial_ceiling="$(jq -r '.ceiling // empty' "$result_dir/selection.json")"
    floor="$initial_floor"; ceiling="$initial_ceiling"
    if [[ "$standard" == true && "$classification" == pass ]]; then floor="$tested_rps"; [[ "$ceiling" == "$tested_rps" ]] && ceiling=""; fi
    if [[ "$standard" == true && "$classification" == breaking ]]; then
      [[ -z "$ceiling" || "$tested_rps" -lt "$ceiling" ]] && ceiling="$tested_rps"
    fi
    rough_dau=""; [[ "$classification" != invalid ]] && rough_dau="$(( ((tested_rps * 10000 / 259 + 50) / 100) * 100 ))"
    backend_value="$backend_sha"; snapshot_value="$snapshot_hash"
    series="$(jq -r .seriesCompatibility "$result_dir/selection.json")"
    node -e 'const fs=require("fs");const a=process.argv.slice(1),p=a[0],tmp=`${p}.tmp.${process.pid}`;const nullable=x=>x===""?null:Number(x);fs.writeFileSync(tmp,JSON.stringify({schemaVersion:"daily-k6-log-v1",day:Number(a[1]),runId:a[2],localDate:a[3],standard:a[4]==="true",testedRps:Number(a[5]),classification:a[6],floor:nullable(a[7]),ceiling:nullable(a[8]),fingerprint:a[9],seriesCompatibility:a[10],backend:a[11]||null,snapshotHash:a[12]||null,roughDau:nullable(a[13]),note:a[14].slice(0,180)},null,2)+"\n",{mode:0o600});fs.renameSync(tmp,p)' \
      "$record_file" "$day" "$run_id" "$local_date" "$standard" "$tested_rps" "$classification" "$floor" "$ceiling" "$fingerprint" "$series" "$backend_value" "$snapshot_value" "$rough_dau" "$reason"
    if ! node "$script_dir/daily-capacity-cli.mjs" render --record "$record_file" --output "$result_dir/readme-recovery-row.md"; then
      classification=invalid; reason="private Markdown recovery row persistence failed"
      node -e 'const fs=require("fs"),p=process.argv[1],t=`${p}.tmp.${process.pid}`,d=JSON.parse(fs.readFileSync(p));Object.assign(d,{classification:"invalid",floor:process.argv[2]===""?null:Number(process.argv[2]),ceiling:process.argv[3]===""?null:Number(process.argv[3]),roughDau:null,note:process.argv[4]});fs.writeFileSync(t,JSON.stringify(d,null,2)+"\n",{mode:0o600});fs.renameSync(t,p)' "$record_file" "$initial_floor" "$initial_ceiling" "$reason"
      update_preliminary recovery-row-persistence-failed || true
    elif node "$script_dir/daily-capacity-cli.mjs" append --readme "$readme" --expected-hash "$readme_hash" --record "$record_file"; then
      append_succeeded=true
    else
      classification=invalid; reason="README append failed; recovery row preserved"
      node -e 'const fs=require("fs"),p=process.argv[1],t=`${p}.tmp.${process.pid}`,d=JSON.parse(fs.readFileSync(p));Object.assign(d,{classification:"invalid",floor:process.argv[2]===""?null:Number(process.argv[2]),ceiling:process.argv[3]===""?null:Number(process.argv[3]),roughDau:null,note:process.argv[4]});fs.writeFileSync(t,JSON.stringify(d,null,2)+"\n",{mode:0o600});fs.renameSync(t,p)' "$record_file" "$initial_floor" "$initial_ceiling" "$reason"
      node "$script_dir/daily-capacity-cli.mjs" render --record "$record_file" --output "$result_dir/readme-recovery-row.md" || true
      update_preliminary readme-append-failed || true
    fi
  fi
  if ! mv "$lock_dir" "$result_dir/released-capacity-lock"; then
    classification=invalid
    reason="lock release failed; correction row preserved privately"
    if [[ "$append_succeeded" == true && -f "$record_file" ]]; then
      initial_floor="$(jq -r '.floor // empty' "$result_dir/selection.json")"
      initial_ceiling="$(jq -r '.ceiling // empty' "$result_dir/selection.json")"
      node -e 'const fs=require("fs"),p=process.argv[1],t=`${p}.tmp.${process.pid}`,d=JSON.parse(fs.readFileSync(p));Object.assign(d,{classification:"invalid",floor:process.argv[2]===""?null:Number(process.argv[2]),ceiling:process.argv[3]===""?null:Number(process.argv[3]),roughDau:null,note:process.argv[4]});fs.writeFileSync(t,JSON.stringify(d,null,2)+"\n",{mode:0o600});fs.renameSync(t,p)' "$record_file" "$initial_floor" "$initial_ceiling" "$reason"
      node "$script_dir/daily-capacity-cli.mjs" render --record "$record_file" --output "$result_dir/readme-recovery-row.md" || true
      node "$script_dir/daily-capacity-cli.mjs" correct --readme "$readme" --record "$record_file" || true
    fi
    append_succeeded=false
    update_preliminary lock-release-failed || true
  fi
  set -e
}

on_exit() {
  local original_exit="$1"
  trap - EXIT INT TERM
  finalize_phase_one
  finalize_phase_two
  print -r -- "Artifacts: $result_dir"
  [[ "$classification" != invalid && "$append_succeeded" == true && "$original_exit" -eq 0 ]] && exit 0
  exit 1
}
fail() { reason="$1"; exit "${2:-2}"; }

mkdir "$result_dir"
mkdir "$lock_dir" 2>/dev/null || {
  print -u2 -- "daily capacity lock exists; follow stale-lock recovery in LOCAL-PROD-SIM-RUNBOOK.md"
  exit 2
}
trap 'on_exit $?' EXIT
trap 'reason="interrupted"; exit 130' INT TERM
process_start="$(ps -p $$ -o lstart= | sed 's/^ *//')"
node -e 'require("fs").writeFileSync(process.argv[1],`pid=${process.argv[2]}\nstart=${process.argv[3]}\nrun_id=${process.argv[4]}\n`,{mode:0o600})' "$lock_dir/owner" "$$" "$process_start" "$run_id"
node "$script_dir/update-preliminary.mjs" --file "$preliminary" --run-id "$run_id" --phase lock-acquired --status invalid --reason "setup did not complete"
node "$script_dir/update-preliminary.mjs" --file "$recovery" --run-id "$run_id" --phase lock-acquired --status invalid --reason "setup did not complete"
fallback_fingerprint="$(node -e 'const c=require("node:crypto");process.stdout.write(`sha256:${c.createHash("sha256").update("daily-k6-compatibility-v1:unmeasured").digest("hex")}`)' </dev/null)"
print -r -- "$fallback_fingerprint" > "$result_dir/fingerprint.txt"
selection_args=(select --readme "$readme" --fingerprint "$fallback_fingerprint" --output "$result_dir/selection.json")
[[ -n "${RPS_OVERRIDE:-}" ]] && selection_args+=(--override "$RPS_OVERRIDE")
node "$script_dir/daily-capacity-cli.mjs" "${selection_args[@]}"
selection_ready=true
update_preliminary bounded-selection-ready

# Selection happens under the lock. Measure the compatibility topology before
# selecting so even an early invalid row never inherits an assumed VM identity.
tool_version() { "$@" 2>/dev/null | head -1 | tr -d '\r' || print missing; }
/opt/homebrew/bin/limactl start "$capacity_vm" >/dev/null
guest_node_version="$(/opt/homebrew/bin/limactl shell "$capacity_vm" -- node --version)"
guest_pm2_version="$(/opt/homebrew/bin/limactl shell "$capacity_vm" -- pm2 --version | tail -1)"
[[ "$guest_node_version" == "v24.13.0" ]] || fail "guest Node version drift"
[[ "$guest_pm2_version" == "6.0.14" ]] || fail "guest PM2 version drift"
/opt/homebrew/bin/limactl shell "$capacity_vm" -- sudo systemctl start nginx
/opt/homebrew/bin/limactl shell "$capacity_vm" -- sudo nginx -T > "$result_dir/nginx-config.txt" 2>&1
guest_cpu="$(/opt/homebrew/bin/limactl shell "$capacity_vm" -- nproc)"
guest_memory_bytes="$(/opt/homebrew/bin/limactl shell "$capacity_vm" -- awk '/^MemTotal:/{print $2*1024}' /proc/meminfo)"
guest_arch="$(/opt/homebrew/bin/limactl shell "$capacity_vm" -- uname -m)"
host_port_listener=false; lsof -nP -iTCP:3302 -sTCP:LISTEN >/dev/null 2>&1 && host_port_listener=true
node "$script_dir/validate-local-topology.mjs" --capacity-db "$capacity_db" --pgbouncer "$pgbouncer_config" \
  --guest-cpu "$guest_cpu" --guest-memory-bytes "$guest_memory_bytes" --guest-arch "$guest_arch" \
  --nginx-config "$result_dir/nginx-config.txt" --host-port-listener "$host_port_listener" --route-match deferred \
  --output "$result_dir/topology-preflight-v1.json" || fail "local topology preflight drift"
node -e 'const fs=require("fs");const a=process.argv.slice(1),p=a[0],t=`${p}.tmp.${process.pid}`;fs.writeFileSync(t,JSON.stringify({corpus:a[1],fixture:a[2],clientCohort:"ios_bara_2_3_7_ads_payout",k6:a[3],node:a[4],pm2:a[5],lima:a[6],postgres:a[7],pgbouncer:a[8],hostArch:a[9],guestArch:a[10],limaCpu:Number(a[11]),limaMemoryBytes:Number(a[12]),portForward:a[13],nginxUpstream:a[14],pgbouncerMapping:a[15]})+"\n",{mode:0o600});fs.renameSync(t,p)' \
  "$result_dir/fingerprint-input.json" "$expected_corpus_sha" "$expected_fixture_revision" \
  "$(tool_version /opt/homebrew/bin/k6 version)" "$guest_node_version" "$guest_pm2_version" \
  "$(tool_version /opt/homebrew/bin/limactl --version)" "$(tool_version "$pg_bin/postgres" --version)" \
  "$(tool_version /opt/homebrew/bin/pgbouncer --version)" "$(uname -m)" "$guest_arch" "$guest_cpu" "$guest_memory_bytes" \
  "$(jq -r .portForward "$result_dir/topology-preflight-v1.json")" \
  "$(jq -r .nginxUpstream "$result_dir/topology-preflight-v1.json")" \
  "$(jq -r .pgbouncerMapping "$result_dir/topology-preflight-v1.json")"
node "$script_dir/daily-capacity-cli.mjs" fingerprint --input "$result_dir/fingerprint-input.json" > "$result_dir/fingerprint.txt"
selection_args=(select --readme "$readme" --fingerprint "$(cat "$result_dir/fingerprint.txt")" --output "$result_dir/selection.json")
[[ -n "${RPS_OVERRIDE:-}" ]] && selection_args+=(--override "$RPS_OVERRIDE")
node "$script_dir/daily-capacity-cli.mjs" "${selection_args[@]}"
selection_ready=true
update_preliminary checkpoint-selected
rate_rps="$(jq -r .rps "$result_dir/selection.json")"
warmup_iterations="$((rate_rps * 5))"
preAllocatedVUs="$(( (rate_rps * 24 + 9) / 10 ))" # ceil(RPS * 2.4)
maxVUs="$(( (rate_rps * 32 + 9) / 10 ))"          # ceil(RPS * 3.2)

[[ -d "$backend_repo/.git" ]] || fail "backend repository missing"
[[ -f "$corpus" && -f "$fixture" ]] || fail "private corpus or fixture missing"
[[ "$(shasum -a 256 "$corpus" | awk '{print $1}')" == "$expected_corpus_sha" ]] || fail "private corpus checksum mismatch"
[[ "$(shasum -a 256 "$fixture" | awk '{print $1}')" == "$expected_fixture_sha" ]] || fail "private fixture checksum mismatch"
[[ "$(jq -r '.metadata.fixtureRevision // empty' "$fixture")" == "$expected_fixture_revision" ]] || fail "private fixture revision mismatch"
print -r -- "$capacity_db" | grep -Eq '^stepv2_capacity_[A-Za-z0-9_]+$' || fail "invalid dedicated database name"
[[ -n "${PROD_SSH_TARGET:-}" && -n "${PROD_BACKEND_DIR:-}" ]] || fail "private production snapshot configuration missing"

print "[1/6] Fetching and pinning backend main"
zsh "$script_dir/package-fetched-main.zsh" --repo "$backend_repo" --output "$source_tar" > "$result_dir/source.json" || fail "FETCH_HEAD packaging failed"
backend_sha="$(jq -r .sha "$result_dir/source.json")"
artifact_host="$result_dir/backend-artifact"
mkdir "$artifact_host"
tar -xf "$source_tar" -C "$artifact_host"
(cd "$artifact_host" && npm ci --ignore-scripts && npx prisma generate)
update_preliminary source-pinned

print "[2/6] Capturing one redacted production snapshot"
node "$script_dir/capture-production-snapshot.mjs" \
  --target "$PROD_SSH_TARGET" --backend-dir "$PROD_BACKEND_DIR" \
  --output "$result_dir/production-snapshot-v1.json" || fail "production snapshot invalid"
DATABASE_URL="postgresql://local@127.0.0.1:55432/$capacity_db" \
  node "$script_dir/extract-fetched-settings.mjs" --artifact-dir "$artifact_host" --output "$result_dir/fetched-defaults-v1.json" || fail "fetched-main defaults invalid"
node "$script_dir/daily-capacity-cli.mjs" reconcile \
  --snapshot "$result_dir/production-snapshot-v1.json" \
  --defaults "$result_dir/fetched-defaults-v1.json" \
  --output "$result_dir/reconciled-settings-v1.json" || fail "snapshot/main reconciliation invalid"
snapshot_hash="$(jq -r .snapshotHash "$result_dir/reconciled-settings-v1.json")"
update_preliminary snapshot-reconciled

print "[3/6] Restoring and migrating the isolated corpus"
if ! "$pg_bin/pg_ctl" -D "$capacity_root/postgres18" status >/dev/null 2>&1; then
  "$pg_bin/pg_ctl" -D "$capacity_root/postgres18" -l "$capacity_root/postgres18.log" -o '-h 127.0.0.1 -p 55432' start >/dev/null
fi
actual_data_dir="$("$pg_bin/psql" -h 127.0.0.1 -p 55432 -d postgres -Atc 'SHOW data_directory')"
[[ "$actual_data_dir" == "$capacity_root/postgres18" ]] || fail "unexpected PostgreSQL cluster identity"
"$pg_bin/dropdb" -h 127.0.0.1 -p 55432 --if-exists "$capacity_db"
"$pg_bin/createdb" -h 127.0.0.1 -p 55432 "$capacity_db"
"$pg_bin/pg_restore" -h 127.0.0.1 -p 55432 -d "$capacity_db" --no-owner --no-acl --exit-on-error "$corpus"
"$pg_bin/psql" -h 127.0.0.1 -p 55432 -d "$capacity_db" -v ON_ERROR_STOP=1 -f "$script_dir/validate-sanitization.sql" > "$result_dir/corpus-validation.log"
local_user="$(id -un)"
print -r -- "$local_user" | grep -Eq '^[A-Za-z0-9_]+$' || fail "local database user is unsafe"
local_database_url="postgresql://$local_user@127.0.0.1:55432/$capacity_db"
(cd "$artifact_host" && env -i PATH="$PATH" DATABASE_URL="$local_database_url" npx prisma migrate deploy --config prisma.config.ts) > "$result_dir/migration.log" 2>&1 || fail "fetched-main migration failed"
settings_hash="$(node "$script_dir/daily-capacity-cli.mjs" settings-hash --settings "$result_dir/reconciled-settings-v1.json")"
node "$script_dir/apply-local-settings.mjs" --settings "$result_dir/reconciled-settings-v1.json" \
  --artifact-dir "$artifact_host" --database-url "$local_database_url" --expected-db "$capacity_db" \
  --expected-marker "$expected_corpus_sha" --expected-hash "$settings_hash" || fail "local settings application failed"
node "$script_dir/remint-local-fixture.mjs" --input "$fixture" --output "$local_fixture" \
  --database-url "$local_database_url" --backend-artifact "$artifact_host" \
  --epoch-ms "$(( $(date -u +%s) * 1000 ))" || fail "local fixture remint failed"
update_preliminary local-state-ready

print "[4/6] Starting the fixed two-worker topology"
grep -Eq '^[[:space:]]*listen_addr[[:space:]]*=[[:space:]]*127\.0\.0\.1[[:space:]]*$' "$pgbouncer_config" || fail "PgBouncer listen address drift"
grep -Eq '^[[:space:]]*listen_port[[:space:]]*=[[:space:]]*56432[[:space:]]*$' "$pgbouncer_config" || fail "PgBouncer listen port drift"
grep -Eq '^[[:space:]]*pool_mode[[:space:]]*=[[:space:]]*transaction[[:space:]]*$' "$pgbouncer_config" || fail "PgBouncer pool mode drift"
grep -Eq '^[[:space:]]*default_pool_size[[:space:]]*=[[:space:]]*25[[:space:]]*$' "$pgbouncer_config" || fail "PgBouncer pool size drift"
/opt/homebrew/bin/pgbouncer -d "$pgbouncer_config"
for _ in {1..40}; do
  [[ -s "$pgbouncer_pidfile" ]] && break
  sleep 0.25
done
[[ -s "$pgbouncer_pidfile" ]] || fail "PgBouncer did not publish its PID"
pool_pid="$(cat "$pgbouncer_pidfile")"
[[ "$pool_pid" == <-> ]] && kill -0 "$pool_pid" 2>/dev/null || fail "PgBouncer process did not remain online"
print -r -- "$(ps -p "$pool_pid" -o lstart= | sed 's/^ *//')" > "$pgbouncer_ownerfile"
pgbouncer_live_route="$("$pg_bin/psql" -h 127.0.0.1 -p 56432 -d "$capacity_db" -AtF '|' -c 'SELECT current_database(), inet_server_addr()::text, inet_server_port()')"
[[ "$pgbouncer_live_route" == "$capacity_db|127.0.0.1/32|55432" ||
   "$pgbouncer_live_route" == "$capacity_db|127.0.0.1|55432" ]] || fail "PgBouncer live database routing drift"
/opt/homebrew/bin/limactl shell "$capacity_vm" -- bash -lc 'sudo systemctl start redis-server nginx; redis-cli FLUSHDB >/dev/null; pm2 delete steps-tracker-prod-sim >/dev/null 2>&1 || true'
artifact_vm="/opt/stepv2-backend-daily-$run_id"
/opt/homebrew/bin/limactl shell "$capacity_vm" -- bash -lc 'set -e; test ! -e "$1"; sudo install -d -m 0755 -o "$(id -un)" -g "$(id -gn)" "$1"; tar -xf - -C "$1"' _ "$artifact_vm" < "$source_tar"
/opt/homebrew/bin/limactl shell "$capacity_vm" -- bash -lc 'set -e; cd "$1"; npm ci --ignore-scripts; npx prisma generate' _ "$artifact_vm"
/opt/homebrew/bin/limactl copy "$result_dir/reconciled-settings-v1.json" "$capacity_vm:/tmp/$run_id-settings.json"
/opt/homebrew/bin/limactl copy "$script_dir/start-local-workers.mjs" "$capacity_vm:/tmp/$run_id-start.mjs"
vm_out="/tmp/$run_id-backend-out.log"; vm_err="/tmp/$run_id-backend-error.log"
/opt/homebrew/bin/limactl shell "$capacity_vm" -- node "/tmp/$run_id-start.mjs" \
  --artifact-dir "$artifact_vm" --settings "/tmp/$run_id-settings.json" --run-id "$run_id" \
  --database-url "postgresql://$local_user@host.lima.internal:56432/$capacity_db" \
  --resolution-concurrency "$resolution_concurrency_per_worker" --stdout "$vm_out" --stderr "$vm_err"
sleep 15
for _ in {1..90}; do
  outstanding="$("$pg_bin/psql" -h 127.0.0.1 -p 55432 -d "$capacity_db" -Atc "SELECT count(*) FROM race_resolution_jobs_v2 WHERE state IN ('queued','running')")"
  [[ "$outstanding" == 0 ]] && break
  sleep 1
done
[[ "$outstanding" == 0 ]] || fail "startup queue did not drain"
pm2_query='[.[]|select(.name=="steps-tracker-prod-sim")|{instance:(.pm2_env.NODE_APP_INSTANCE|tostring),pid:.pid,startedAtMs:.pm2_env.pm_uptime,status:.pm2_env.status,restarts:.pm2_env.restart_time,cwd:.pm2_env.pm_cwd,execPath:.pm2_env.pm_exec_path,exitCode:(.pm2_env.exit_code // 0),unstableRestarts:.pm2_env.unstable_restarts}]|sort_by(.instance)'
/opt/homebrew/bin/limactl shell "$capacity_vm" -- pm2 jlist | jq "$pm2_query" > "$result_dir/pm2-pre.json"
jq -e --arg cwd "$artifact_vm" --arg exec "$artifact_vm/src/capacityLocal.js" 'length==2 and map(.instance)==["0","1"] and all(.[];.status=="online" and .restarts==0 and .unstableRestarts==0 and .exitCode==0 and (.pid|type)=="number" and (.startedAtMs|type)=="number" and .cwd==$cwd and .execPath==$exec)' "$result_dir/pm2-pre.json" >/dev/null || fail "local PM2 preflight identity invalid"
server_evidence_started_at="$(date -u +%FT%TZ)"
server_samples="$result_dir/server-memory.ndjson"
(
  while [[ ! -f "$result_dir/stop-server-sampler" ]]; do
    available="$(/opt/homebrew/bin/limactl shell "$capacity_vm" -- awk '/^MemAvailable:/{print $2}' /proc/meminfo 2>/dev/null || true)"
    [[ "$available" == <-> ]] && print -r -- "$(date -u +%FT%TZ) $available" >> "$server_samples"
    sleep 1
  done
) &
server_sampler_pid=$!
token="$(jq -r '.users[0].token // empty' "$local_fixture")"
[[ -n "$token" ]] || fail "local fixture token missing"
curl -fsS -H "Authorization: Bearer $token" -H 'X-App-Version: 2.3.7' http://127.0.0.1:3302/auth/me > "$result_dir/authenticated-preflight.json" || fail "authenticated preflight returned 401 or failed"
curl -fsS http://127.0.0.1:3302/health > "$result_dir/host-routed-health.json" || fail "Lima host port forward health failed"
/opt/homebrew/bin/limactl shell "$capacity_vm" -- curl -fsS http://127.0.0.1:8080/health > "$result_dir/guest-nginx-health.json" || fail "guest nginx route health failed"
/opt/homebrew/bin/limactl shell "$capacity_vm" -- curl -fsS http://127.0.0.1:3002/health > "$result_dir/guest-direct-health.json" || fail "guest direct worker health failed"
route_match=false
host_health_hash="$(shasum -a 256 "$result_dir/host-routed-health.json" | awk '{print $1}')"
[[ "$host_health_hash" == "$(shasum -a 256 "$result_dir/guest-nginx-health.json" | awk '{print $1}')" &&
   "$host_health_hash" == "$(shasum -a 256 "$result_dir/guest-direct-health.json" | awk '{print $1}')" ]] && route_match=true
node "$script_dir/validate-local-topology.mjs" --capacity-db "$capacity_db" --pgbouncer "$pgbouncer_config" \
  --guest-cpu "$guest_cpu" --guest-memory-bytes "$guest_memory_bytes" --guest-arch "$guest_arch" \
  --nginx-config "$result_dir/nginx-config.txt" --host-port-listener "$host_port_listener" --route-match "$route_match" \
  --output "$result_dir/topology-v1.json" || fail "local topology routing drift"
jq -s '.[0] * .[1]' "$result_dir/fingerprint-input.json" "$result_dir/topology-v1.json" > "$result_dir/fingerprint-input.tmp.json"
mv "$result_dir/fingerprint-input.tmp.json" "$result_dir/fingerprint-input.json"
node "$script_dir/daily-capacity-cli.mjs" fingerprint --input "$result_dir/fingerprint-input.json" > "$result_dir/fingerprint.txt"
selection_args=(select --readme "$readme" --fingerprint "$(cat "$result_dir/fingerprint.txt")" --output "$result_dir/selection.json")
[[ -n "${RPS_OVERRIDE:-}" ]] && selection_args+=(--override "$RPS_OVERRIDE")
node "$script_dir/daily-capacity-cli.mjs" "${selection_args[@]}"
rate_rps="$(jq -r .rps "$result_dir/selection.json")"
warmup_iterations="$((rate_rps * 5))"
preAllocatedVUs="$(( (rate_rps * 24 + 9) / 10 ))"
maxVUs="$(( (rate_rps * 32 + 9) / 10 ))"
update_preliminary topology-verified

print "[5/6] Running one ${rate_rps}-RPS adaptive checkpoint"
deadlocks_pre="$("$pg_bin/psql" -h 127.0.0.1 -p 55432 -d "$capacity_db" -Atc "SELECT deadlocks FROM pg_stat_database WHERE datname=current_database()")"
flags_label="snapshot-${snapshot_hash[8,12]}"
update_preliminary traffic-starting
node "$script_dir/run-k6-with-health.mjs" \
  --output "$result_dir/load-generator-health-v1.json" --exit-file "$result_dir/k6-exit.txt" \
  --raw "$result_dir/raw-samples.json" --max-vus "$maxVUs" \
  --stdout "$result_dir/k6-stdout.log" --stderr "$result_dir/k6-stderr.log" -- \
  /opt/homebrew/bin/k6 run \
  -e BASE_URL=http://127.0.0.1:3302 -e USERS_FILE="$local_fixture" \
  -e TARGET_RUNG="daily_${rate_rps}rps" -e CLIENT_COHORT=ios_bara_2_3_7_ads_payout \
  -e BACKEND_REVISION="$backend_sha" -e BACKEND_FLAGS="$flags_label" \
  -e BACKEND_CONFIG="prod-sim-2vcpu-2gb-node-pgbouncer25-resolution-c${resolution_concurrency_per_worker}x2" -e WORKER_COUNT=2 -e PGBOUNCER_POOL=25 \
  -e REDIS_STATE=empty-at-start -e CRON_COHORT=capacity-http-resolution-only \
  -e MATCHED_PAIR_EPOCH_MS="$(( $(date -u +%s) * 1000 ))" -e WARMUP_ITERATIONS="$warmup_iterations" \
  -e DURATION_OVERRIDE=35s -e ALLOW_DIAGNOSTIC_OVERRIDE=1 -e RESOLUTION_DRAIN_TIMEOUT_MS=60000 \
  -e RUN_ID="$run_id" -e REPEAT_INDEX=1 -e SUMMARY_JSON="$result_dir/summary.json" \
  --out json="$result_dir/raw-samples.json" "$frontend_repo/k6/prod-mix-load-test.js"
k6_exit="$(cat "$result_dir/k6-exit.txt")"
[[ "$k6_exit" == 0 || "$k6_exit" == 99 ]] || fail "k6 generator/runtime failed"

monotonic_seconds() { node -e 'process.stdout.write(String(Number(process.hrtime.bigint())/1e9))'; }
quiet=0; drain_seconds=0; global_drained=false
drain_started_monotonic="$(monotonic_seconds)"
drain_deadline_monotonic="$((drain_started_monotonic + 90.0))"
while (( $(monotonic_seconds) < drain_deadline_monotonic )); do
  outstanding="$("$pg_bin/psql" -h 127.0.0.1 -p 55432 -d "$capacity_db" -Atc "SELECT count(*) FROM race_resolution_jobs_v2 WHERE state IN ('queued','running')")"
  if [[ "$outstanding" == 0 ]]; then quiet=$((quiet + 1)); else quiet=0; fi
  if [[ "$quiet" -ge 5 ]]; then global_drained=true; break; fi
  sleep 1
done
drain_ended_monotonic="$(monotonic_seconds)"
drain_seconds="$((drain_ended_monotonic - drain_started_monotonic))"
touch "$result_dir/stop-server-sampler"; wait "$server_sampler_pid" || true
traffic_ended_at="$(date -u +%FT%TZ)"
deadlocks_post="$("$pg_bin/psql" -h 127.0.0.1 -p 55432 -d "$capacity_db" -Atc "SELECT deadlocks FROM pg_stat_database WHERE datname=current_database()")"
/opt/homebrew/bin/limactl shell "$capacity_vm" -- pm2 jlist | jq "$pm2_query" > "$result_dir/pm2-post.json"
/opt/homebrew/bin/limactl shell "$capacity_vm" -- bash -lc 'cat "$1" "$2" 2>/dev/null' _ "$vm_out" "$vm_err" > "$result_dir/backend.log"
set +e
/opt/homebrew/bin/limactl shell "$capacity_vm" -- journalctl -k --since "$server_evidence_started_at" --until "$traffic_ended_at" -o cat > "$result_dir/kernel.log" 2>/dev/null
kernel_status=$?
set -e
kernel_parse_status=ok; [[ "$kernel_status" -eq 0 ]] || kernel_parse_status=failed
kernel_oom_kills="$(grep -Eic 'out of memory: killed process|oom-kill:' "$result_dir/kernel.log" || true)"
node "$script_dir/normalize-daily-k6.mjs" --summary "$result_dir/summary.json" --raw "$result_dir/raw-samples.json" --output "$result_dir/normalized-raw.json" || fail "raw metric presence/accounting validation failed"
resolution_samples="$(jq -er '.totals.resolutionLagSamples.count | numbers' "$result_dir/summary.json")" || fail "resolution sample evidence missing"
resolution_max="$(jq -er '.totals.resolutionLag.max | numbers' "$result_dir/summary.json")" || fail "resolution lag evidence missing"
resolution_failures="$(jq -er '.totals.resolutionStates.failed.count | numbers' "$result_dir/summary.json")" || fail "resolution failure evidence missing"
resolution_outstanding="$(jq -er '.totals.finalResolutionOutstanding.value | numbers' "$result_dir/summary.json")" || fail "resolution drain evidence missing"
dedicated_drain_seconds="$(jq -er '(.totals.resolutionDrainDuration.value | numbers) / 1000' "$result_dir/summary.json")" || fail "resolution drain duration missing"
dedicated_drained=false; [[ "$resolution_outstanding" == 0 ]] && dedicated_drained=true
node "$script_dir/build-daily-health.mjs" server --memory-samples "$server_samples" --pm2-pre "$result_dir/pm2-pre.json" \
  --pm2-post "$result_dir/pm2-post.json" --logs "$result_dir/backend.log" --started-at "$server_evidence_started_at" \
  --ended-at "$traffic_ended_at" --window-complete true --deadlocks-pre "$deadlocks_pre" --deadlocks-post "$deadlocks_post" \
  --resolution-samples "$resolution_samples" --resolution-max-lag "$resolution_max" --resolution-failures "$resolution_failures" \
  --dedicated-drain-seconds "$dedicated_drain_seconds" --global-drain-seconds "$drain_seconds" --consecutive-zero-samples "$quiet" \
  --dedicated-drained "$dedicated_drained" --global-drained "$global_drained" \
  --kernel-oom-parse-status "$kernel_parse_status" --kernel-oom-kills "$kernel_oom_kills" \
  --output "$result_dir/server-health-v1.json"
node "$script_dir/daily-capacity-cli.mjs" classify --summary "$result_dir/summary.json" --raw "$result_dir/normalized-raw.json" \
  --load-health "$result_dir/load-generator-health-v1.json" --server-health "$result_dir/server-health-v1.json" \
  --k6-exit "$k6_exit" --output "$result_dir/classification-v1.json"
classification="$(jq -r .classification "$result_dir/classification-v1.json")"
reason="$(jq -r .reason "$result_dir/classification-v1.json")"
if [[ "$resolution_concurrency_per_worker" != 1 ]]; then
  reason="aggregate resolution concurrency $((resolution_concurrency_per_worker * 2)): $reason"
fi
update_preliminary classified
print "[6/6] Classified $classification; verified teardown and README append follow"
