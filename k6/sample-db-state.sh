#!/bin/bash
# Samples staging's backend state once a second. The question this answers:
# are the pooled connections ACTIVE (DB core saturated -> resize the cluster)
# or IDLE (DB fine -> the wall is src/db.js pool config)?
S="$1"
for i in $(seq 1 100); do
  psql "$S" -t -A -F'|' -c "
    SELECT
      now()::time(0)::text
      || ' active='   || COUNT(*) FILTER (WHERE state='active')
      || ' idle_tx='  || COUNT(*) FILTER (WHERE state='idle in transaction')
      || ' idle='     || COUNT(*) FILTER (WHERE state='idle')
      || ' total='    || COUNT(*)
      || ' | waits: ' || COALESCE(string_agg(DISTINCT
             COALESCE(wait_event_type,'-')||':'||COALESCE(wait_event,'RUNNING'), ', ')
             FILTER (WHERE state='active'), 'none')
    FROM pg_stat_activity
    WHERE datname='step-tracker-staging' AND backend_type='client backend';" 2>/dev/null
  sleep 1
done
