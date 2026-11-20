#!/bin/sh
set -eu
out=/evidence
{
    uname -a
    cat /etc/os-release
    id
    nproc
    cat /sys/fs/cgroup/cpu.max /sys/fs/cgroup/memory.max
    env | sort | grep -E '^(AGENT_|MEMORY_LIMIT=|CPU_MAX_OCCUPY=|MULTI_THREAD_ENABLE=)'
} > "$out/environment.txt"
cat /sys/fs/cgroup/memory.events > "$out/memory-events-before.txt"
date -u +%FT%T.%3NZ > "$out/start.utc"
LC_ALL=C top -b -d 1 -w 180 > "$out/top.log" &
observer=$!
# Give top one frame before launching the process.
sleep 1
timeout -k 3 90 ./agent-leak-app > "$out/console.log" 2>&1 &
runner=$!
status=0
wait "$runner" || status=$?
date -u +%FT%T.%3NZ > "$out/end.utc"
printf 'timeout_wait_status=%s\n' "$status" > "$out/exit.txt"
kill "$observer" 2>/dev/null || true
wait "$observer" || true
cat /sys/fs/cgroup/memory.events > "$out/memory-events-after.txt"
