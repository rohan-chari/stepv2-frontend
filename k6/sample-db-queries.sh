#!/bin/bash
# Poor-man's pg_stat_statements: sample the currently-running statement many
# times. A statement that appears in N% of samples is consuming ~N% of the
# database's busy time. pg_stat_statements is not installed on this cluster.
S="$1"
for i in $(seq 1 900); do
  psql "$S" -t -A -c "
    SELECT left(regexp_replace(query, '\s+', ' ', 'g'), 150)
    FROM pg_stat_activity
    WHERE datname='step-tracker-staging'
      AND backend_type='client backend'
      AND state='active'
      AND query NOT LIKE '%pg_stat_activity%';" 2>/dev/null
done
