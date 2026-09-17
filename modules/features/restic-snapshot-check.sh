#!/usr/bin/env bash
set -euo pipefail

textfile_dir=$1
shift

# Arguments are triples: metric label, credential file, repository override.
check_repo() (
  name=$1
  env_file=$2
  repository=$3
  checked_at=$(date +%s) || exit 1
  success=0
  timestamp=0
  metric_file="$textfile_dir/restic_$name.prom"
  temporary=$(mktemp "$metric_file.XXXXXX") || exit 1
  trap 'rm -f "$temporary"' EXIT

  # Each query gets a separate environment. Client credentials contain only a
  # password, so their repository must not leak in from an off-site query.
  if timestamp=$(
    (
      set -a
      # shellcheck source=/dev/null
      source "$env_file" || exit 1
      set +a
      if [ -n "$repository" ]; then
        export RESTIC_REPOSITORY="$repository"
      fi
      # Metadata queries do not need a cache or a HOME in the system service.
      restic --no-cache snapshots --latest 1 --json
    ) 2>/dev/null |
      jq -er '.[].time' |
      while IFS= read -r snapshot_time; do
        date -d "$snapshot_time" +%s || exit 1
      done |
      sort -n |
      tail -n 1
  ) && [[ "$timestamp" =~ ^[0-9]+$ ]]; then
    success=1
  else
    timestamp=0
    echo "restic-snapshot-check: unable to read snapshots for $name" >&2
  fi

  {
    printf 'restic_last_snapshot_timestamp_seconds{repo="%s"} %s\n' "$name" "$timestamp"
    printf 'restic_snapshot_check_success{repo="%s"} %s\n' "$name" "$success"
    printf 'restic_snapshot_check_timestamp_seconds{repo="%s"} %s\n' "$name" "$checked_at"
  } > "$temporary" || exit 1
  chmod 0644 "$temporary" || exit 1
  mv "$temporary" "$metric_file" || exit 1
  [ "$success" -eq 1 ]
)

result=0
while [ "$#" -gt 0 ]; do
  check_repo "$1" "$2" "$3" || result=1
  shift 3
done
exit "$result"
