#!/bin/sh
# Run inside the isolated agent service. ps reports RSS in KiB.
set -eu
out=${1:?evidence directory required}
date -u +%FT%T.%3NZ > "$out/start.utc"
{
    uname -a
    cat /etc/os-release
    id
    nproc
    cat /sys/fs/cgroup/cpu.max /sys/fs/cgroup/memory.max
    env | sort | grep -E '^(AGENT_|MEMORY_LIMIT=|CPU_MAX_OCCUPY=|MULTI_THREAD_ENABLE=)'
} > "$out/environment.txt"
cat /sys/fs/cgroup/memory.events > "$out/memory-events-before.txt"
printf 'utc pid ppid elapsed_s rss_KiB threads state command\n' > "$out/monitor.log"
./agent-leak-app > "$out/console.log" 2>&1 &
launcher=$!
while kill -0 "$launcher" 2>/dev/null; do
    stamp=$(date -u +%FT%T.%3NZ)
    ps -C agent-leak-app -o pid=,ppid=,etimes=,rss=,nlwp=,stat=,comm= |
        awk -v t="$stamp" '{print t, $1, $2, $3, $4, $5, $6, $7}' >> "$out/monitor.log"
    sleep 1
done
status=0
wait "$launcher" || status=$?
date -u +%FT%T.%3NZ > "$out/end.utc"
printf 'launcher_pid=%s\nexit_code=%s\n' "$launcher" "$status" > "$out/exit.txt"
cat /sys/fs/cgroup/memory.events > "$out/memory-events-after.txt"
