#!/bin/bash

set -euo pipefail

usage() {
    echo "Usage: $(basename "$0") collect INSTANCE S3PATH"
    echo "       $(basename "$0") show INSTANCE [MAX_AGE]"
    echo ""
    echo "Where:"
    echo "  collect|show  - Collect (slow) or show (fast) stats"
    echo "  INSTANCE      - Unique name to be used as identifier for stats (e.g. mybackup)"
    echo "  S3PATH        - S3 path without trailing slash (e.g. s3://mybucket/some/path)"
    echo "  MAX_AGE       - How old (in seconds) should be the stats file before it is considered stale (default: 0)"
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
    stats_name="s3-stats"
    stats_dir="${BARMAN_S3_STATS_DIR:-/var/lib/barman/s3_stats}"
    stats_file="$stats_dir/$stats_instance-s3-stats.json"

    case "$cmd-$#" in
        collect-3)
            if [[ $3 =~ ^s3://([^/ ]+)(/([^[:space:]]+))?$ ]]; then
                bucket="${BASH_REMATCH[1]}"
                prefix="${BASH_REMATCH[3]}/"
            else
                usage
                exit 1
            fi

            start_time=$(jq -n now)
            stats_data=$(aws s3api list-objects --bucket "$bucket" --prefix "$prefix" --output json --query "{size: sum(Contents[].Size), count: length(Contents[])}")
            end_time=$(jq -n now)

            [[ -d "$stats_dir" ]] || mkdir -p "$stats_dir"
            stats_file_tmp=$(mktemp "$stats_file.XXXX")
            jq <<< "$stats_data" --arg start_time "$start_time" --arg end_time "$end_time" --arg name "$stats_name" --arg instance "$stats_instance" \
                '. * {name: $name, instance: $instance,
                      start_time: ($start_time | tonumber), end_time: ($end_time | tonumber),
                      duration: (($end_time | tonumber) - ($start_time | tonumber))}' > "$stats_file_tmp"
            mv "$stats_file_tmp" "$stats_file"
            ;;
        show-2|show-3)
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
