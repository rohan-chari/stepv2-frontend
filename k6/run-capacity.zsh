#!/bin/zsh

set -u
setopt PIPE_FAIL

script_dir=${0:A:h}
command_name=${1:-}
if [[ ! $command_name =~ '^(smoke|find|confirm|soak)$' ]]; then
  print -u2 'usage: k6/run-capacity.zsh smoke|find|confirm|soak'
  exit 2
fi

node_bin=${NODE_BIN:-node}
k6_bin=${K6_BIN:-k6}
parent_grace_seconds=${K6_PARENT_GRACE_SECONDS:-30}
minimum_parent_grace_seconds=15
[[ ${CAPACITY_INTERNAL_TEST_MODE:-0} == 1 ]] && minimum_parent_grace_seconds=1
if [[ ! $parent_grace_seconds =~ '^[0-9]+$' ]] || (( parent_grace_seconds < minimum_parent_grace_seconds || parent_grace_seconds > 30 )); then
  print -u2 'K6_PARENT_GRACE_SECONDS must be at least 15 seconds and no more than 30 seconds'
  exit 2
fi
results_root=${RESULTS_ROOT:-$script_dir/results}
fixture_path=${FIXTURE_PATH:-$script_dir/fixture.json}
run_stamp=$(date -u +%Y%m%dT%H%M%SZ)
run_id=${RUN_ID:-capacity-${run_stamp}-$$}
artifact_dir=$results_root/${run_stamp}-${command_name}-$$
mkdir -p -- $artifact_dir
chmod 700 $artifact_dir

temporary_dir=$(mktemp -d "${TMPDIR:-/tmp}/stepv2-capacity.XXXXXX") || exit 2
typeset -a temporary_paths
cleanup() {
  local temporary_path
  for temporary_path in $temporary_paths; do
    [[ -f $temporary_path ]] && rm -f -- $temporary_path
  done
  rmdir -- $temporary_dir 2>/dev/null || true
}
trap cleanup EXIT INT TERM

export FIXTURE_PATH=$fixture_path
export RUN_ID=$run_id
export LOGICAL_EPOCH_MS=${LOGICAL_EPOCH_MS:-$($node_bin -e 'const now=Date.now(); let anchor=Math.floor(now/300000)*300000+120000; if(anchor>now) anchor-=300000; process.stdout.write(String(anchor));')}
export RUN_SEED=${RUN_SEED:-$(( $(date +%s) % 2147483647 ))}

capacity_helper() {
  $node_bin $script_dir/queue-observer.mjs "$@"
}

observer_helper() {
  if [[ -n ${QUEUE_OBSERVER_BIN:-} ]]; then
    ${QUEUE_OBSERVER_BIN} "$@"
  else
    capacity_helper "$@"
  fi
}

seed_helper() {
  if [[ -n ${SEED_HELPER_BIN:-} ]]; then
    ${SEED_HELPER_BIN} "$@"
  else
    capacity_helper "$@"
  fi
}

config_path=$artifact_dir/effective-config.json
if ! capacity_helper preflight --command $command_name --output $config_path >$artifact_dir/preflight.stdout.log 2>$artifact_dir/preflight.stderr.log; then
  capacity_helper invalid-result --command $command_name --output $artifact_dir/result.json >/dev/null 2>&1 || true
  print -u2 "capacity preflight failed; see $artifact_dir/preflight.stderr.log"
  print "artifacts: $artifact_dir"
  exit 2
fi

plan_value() {
  $node_bin -e 'const fs=require("fs"); const c=JSON.parse(fs.readFileSync(process.argv[1],"utf8")); const v=c.plan[Number(process.argv[2])-1]?.[process.argv[3]]; if(v===undefined) process.exit(2); process.stdout.write(String(v));' $config_path $1 $2
}

config_value() {
  $node_bin -e 'const fs=require("fs"); const c=JSON.parse(fs.readFileSync(process.argv[1],"utf8")); const v=c[process.argv[2]]; if(v===undefined) process.exit(2); process.stdout.write(String(v));' $config_path $1
}

plan_count=$($node_bin -e 'const fs=require("fs"); process.stdout.write(String(JSON.parse(fs.readFileSync(process.argv[1],"utf8")).plan.length));' $config_path)
queue_verified=$(config_value queueTargetConfirmed)
typeset -a run_paths

run_k6_phase() {
  local phase_name=$1
  local phase_seconds=$2
  local planned_requests=$3
  local ordinal_base=$4
  local status_context=$5
  local summary_path=$6
  local stdout_path=$7
  local stderr_path=$8
  export PHASE=$phase_name
  export PHASE_DURATION_SECONDS=$phase_seconds
  export PLANNED_REQUESTS=$planned_requests
  export WRITE_ORDINAL_BASE=$ordinal_base
  export STATUS_CONTEXT_PATH=$status_context
  export SUMMARY_PATH=$summary_path
  local parent_limit_seconds=$(( phase_seconds + parent_grace_seconds ))
  [[ $command_name == smoke ]] && parent_limit_seconds=$(( 300 + parent_grace_seconds ))
  $node_bin -e '
    const {spawnSync}=require("node:child_process");
    const timeout=Number(process.argv[1]);
    const result=spawnSync(process.argv[2],["run","--quiet",process.argv[3]],{stdio:"inherit",timeout,killSignal:"SIGKILL"});
    if(result.error?.code==="ETIMEDOUT") { process.stderr.write("k6 phase exceeded parent deadline\n"); process.exit(124); }
    if(result.error) { process.stderr.write("k6 phase launch failed\n"); process.exit(2); }
    process.exit(result.status ?? 2);
  ' $(( parent_limit_seconds * 1000 )) $k6_bin $script_dir/capacity-test.js >$stdout_path 2>$stderr_path
}

integer index=1
while (( index <= plan_count )); do
  rps=$(plan_value $index rps)
  warmup_seconds=$(plan_value $index warmupSeconds)
  measure_seconds=$(plan_value $index measureSeconds)
  planned_warmup=$(plan_value $index plannedWarmup)
  planned_measure=$(plan_value $index plannedMeasure)
  warmup_ordinal=$(plan_value $index warmupWriteOrdinalBase)
  measure_ordinal=$(plan_value $index measureWriteOrdinalBase)
  offered_writes=$(plan_value $index offeredWriteRequests)
  export RPS=$rps
  export REPEAT_INDEX=$index
  export COMMAND=$command_name
  export PLANNED_MEASURE_WRITE_SLOTS=$offered_writes
  export VERIFIED_QUEUE=$([[ $queue_verified == true ]] && print 1 || print 0)

  prefix=$(printf 'run-%02d' $index)
  warmup_context=$temporary_dir/${prefix}-warmup-context.json
  measure_context=$temporary_dir/${prefix}-measure-context.json
  warmup_summary=$temporary_dir/${prefix}-warmup-summary.json
  postcheck_summary=$temporary_dir/${prefix}-postcheck.json
  temporary_paths+=($warmup_context $measure_context $warmup_summary $postcheck_summary)
  measure_summary=$artifact_dir/${prefix}-k6-summary.json
  queue_summary=$artifact_dir/${prefix}-queue.json
  queue_ready=$temporary_dir/${prefix}-queue-ready
  queue_done=$temporary_dir/${prefix}-queue-done
  queue_boundary_ready=$temporary_dir/${prefix}-queue-boundary-ready
  temporary_paths+=($queue_ready $queue_done $queue_boundary_ready)
  run_path=$artifact_dir/${prefix}-result.json
  run_paths+=($run_path)
  warmup_exit=2
  setup_exit=2
  measure_exit=2
  postcheck_exit=2
  queue_exit=2

  if [[ $queue_verified == true ]]; then
    if ! observer_helper barrier --timeout 30 --output $temporary_dir/${prefix}-initial-barrier.json >$artifact_dir/${prefix}-initial-barrier.stdout.log 2>$artifact_dir/${prefix}-initial-barrier.stderr.log; then
      print -u2 "$prefix initial queue barrier failed"
      capacity_helper finalize-run --config $config_path --index $index --warmup $warmup_summary --measure $measure_summary --postcheck $postcheck_summary --queue $queue_summary --stderr $artifact_dir/${prefix}-measure.stderr.log --warmup-exit 2 --setup-exit 2 --measure-exit 2 --postcheck-exit 2 --queue-exit 2 --output $run_path
      break
    fi
    temporary_paths+=($temporary_dir/${prefix}-initial-barrier.json)
  fi

  if seed_helper seed --phase warmup-setup --ordinal-base $((1000000000 + index * 100)) --output $warmup_context >$artifact_dir/${prefix}-warmup-setup.stdout.log 2>$artifact_dir/${prefix}-warmup-setup.stderr.log; then
    run_k6_phase warmup $warmup_seconds $planned_warmup $warmup_ordinal $warmup_context $warmup_summary $artifact_dir/${prefix}-warmup.stdout.log $artifact_dir/${prefix}-warmup.stderr.log
    warmup_exit=$?
  fi

  if (( warmup_exit == 0 || warmup_exit == 99 )); then
    if [[ $queue_verified == true ]]; then
      if ! observer_helper barrier --timeout 120 --contexts $warmup_context --output $temporary_dir/${prefix}-post-warmup-barrier.json >$artifact_dir/${prefix}-post-warmup-barrier.stdout.log 2>$artifact_dir/${prefix}-post-warmup-barrier.stderr.log; then
        warmup_exit=2
      fi
      temporary_paths+=($temporary_dir/${prefix}-post-warmup-barrier.json)
    fi
  fi

  if (( warmup_exit == 0 || warmup_exit == 99 )); then
    if seed_helper seed --phase measurement-setup --ordinal-base $((2000000000 + index * 100)) --previous $warmup_context --output $measure_context >$artifact_dir/${prefix}-measure-setup.stdout.log 2>$artifact_dir/${prefix}-measure-setup.stderr.log; then
      setup_exit=0
    fi
  fi

  if (( setup_exit == 0 )) && [[ $queue_verified == true ]]; then
    if ! observer_helper barrier --timeout 120 --contexts $measure_context --output $temporary_dir/${prefix}-post-setup-barrier.json >$artifact_dir/${prefix}-post-setup-barrier.stdout.log 2>$artifact_dir/${prefix}-post-setup-barrier.stderr.log; then
      setup_exit=2
    fi
    temporary_paths+=($temporary_dir/${prefix}-post-setup-barrier.json)
  fi

  observer_pid=''
  if (( setup_exit == 0 )); then
    if [[ $queue_verified == true ]]; then
      observer_helper observe --measure-seconds $measure_seconds --drain-seconds 120 --ready $queue_ready --done $queue_done --boundary-ready $queue_boundary_ready --output $queue_summary >$artifact_dir/${prefix}-queue.stdout.log 2>$artifact_dir/${prefix}-queue.stderr.log &
      observer_pid=$!
      integer ready_attempt=0
      while [[ ! -f $queue_ready ]] && (( ready_attempt < 300 )); do
        sleep 0.1
        (( ready_attempt += 1 ))
      done
      if [[ ! -f $queue_ready ]]; then
        kill $observer_pid 2>/dev/null || true
        wait $observer_pid 2>/dev/null || true
        observer_pid=''
        setup_exit=2
      fi
    fi
    if (( setup_exit == 0 )); then
      run_k6_phase measure $measure_seconds $planned_measure $measure_ordinal $measure_context $measure_summary $artifact_dir/${prefix}-measure.stdout.log $artifact_dir/${prefix}-measure.stderr.log
      measure_exit=$?
      if [[ $queue_verified == true ]]; then
        touch $queue_done
        integer boundary_attempt=0
        while [[ ! -f $queue_boundary_ready ]] && (( boundary_attempt < 300 )); do
          sleep 0.1
          (( boundary_attempt += 1 ))
        done
        [[ ! -f $queue_boundary_ready ]] && measure_exit=2
      fi
      if (( measure_exit == 0 || measure_exit == 99 )); then
        if seed_helper postcheck --ordinal-base $((3000000000 + index * 100)) --previous $measure_context --output $postcheck_summary >$artifact_dir/${prefix}-postcheck.stdout.log 2>$artifact_dir/${prefix}-postcheck.stderr.log; then
          postcheck_exit=0
        fi
      fi
    fi
    if [[ -n $observer_pid ]]; then
      wait $observer_pid
      queue_exit=$?
    else
      queue_exit=0
    fi
  fi

  capacity_helper finalize-run --config $config_path --index $index --warmup $warmup_summary --measure $measure_summary --postcheck $postcheck_summary --queue $queue_summary --stderr $artifact_dir/${prefix}-measure.stderr.log --warmup-exit $warmup_exit --setup-exit $setup_exit --measure-exit $measure_exit --postcheck-exit $postcheck_exit --queue-exit $queue_exit --output $run_path

  run_outcome=$($node_bin -e 'const fs=require("fs"); process.stdout.write(JSON.parse(fs.readFileSync(process.argv[1],"utf8")).benchmarkOutcome);' $run_path)
  if [[ $command_name == find && $run_outcome != pass ]]; then
    break
  fi
  (( index += 1 ))
done

runs_csv=${(j:,:)run_paths}
capacity_helper aggregate --config $config_path --runs $runs_csv --output $artifact_dir/result.json
final_exit=$?
print "artifacts: $artifact_dir"
print 'manual telemetry required: CPU <90% sustained; no OOM/restart; zero pool timeouts; zero deadlock delta; queue drains; agreed memory headroom retained.'
exit $final_exit
