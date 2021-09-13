#!/bin/bash

set -euo pipefail

usage() {
    echo "Usage: $(basename "$0") run INSTANCE SOURCE DESTINATION [DELETE]"
    echo "Usage: $(basename "$0") stats INSTANCE [MAX_AGE]"
    echo ""
    echo "Where:"
    echo "  run|stats               - Run sync or show stats"
    echo "  INSTANCE                - Unique name to be used as identifier for stats (e.g. mybackup)"
    echo "  SOURCE and DESTINATION  - <LocalPath> <S3Uri> or <S3Uri> <LocalPath> or <S3Uri> <S3Uri>, see 'aws s3 sync help' for more details"
    echo "  DELETE                  - Files that exist in the destination but not in the source are deleted during sync. Values: delete|nodelete (default: nodelete)"
    echo ""
    echo "Environment variables:"
    echo "  BARMAN_S3_STATS_DIR - directory to store stats (default: /var/lib/barman/telegraf/s3)"
}

main() {
    if [[ $# -lt 2 ]]; then
        usage
        exit 1
    fi

    cmd=$1
    stats_instance=$2
    stats_name="s3-sync"
    stats_dir="${BARMAN_S3_STATS_DIR:-/var/lib/barman/s3_stats}"
    stats_file="$stats_dir/$stats_instance-s3-sync-stats.json"

    case "$cmd-$#" in
        run-4|run-5)
            src=$3
            dest=$4
            delete=${5:-nodelete}

            aws_s3_sync_params=()

            case "$delete" in
                delete)
                    aws_s3_sync_params+=(--delete)
                    ;;
                nodelete)
                    ;;
                *)
                    usage
                    exit 1
                    ;;
            esac

            start_time=$(jq -n now)
            if aws s3 sync "$src" "$dest" "${aws_s3_sync_params[@]}"; then
                aws_s3_sync_result=$?
            else
                aws_s3_sync_result=$?
            fi
            end_time=$(jq -n now)

            [[ -d "$stats_dir" ]] || mkdir -p "$stats_dir"
            stats_file_tmp=$(mktemp "$stats_file.XXXX")
            jq -n --arg result "$aws_s3_sync_result" --arg start_time "$start_time" --arg end_time "$end_time" --arg name "$stats_name" --arg instance "$stats_instance" \
                '{name: $name, instance: $instance, result: ($result | tonumber),
                  start_time: ($start_time | tonumber), end_time: ($end_time | tonumber),
                  duration: (($end_time | tonumber) - ($start_time | tonumber))}' > "$stats_file_tmp"
            mv "$stats_file_tmp" "$stats_file"
            ;;
        stats-2|stats-3)
            max_age=${3:-0}
            if [[ -f "$stats_file" ]]; then
                cat "$stats_file" | jq --arg max_age "$max_age" '.age = now - .start_time | .max_age = ($max_age | tonumber) | .stale = (if .age > .max_age then 1 else 0 end)'
            else
                echo "{}"
            fi
            ;;
        *)
            usage
            exit 1
            ;;
    esac
}

main "$@"
