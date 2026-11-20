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
date -u +%FT%T.%3NZ > "$out/start.utc"
timeout --verbose -k 3 40 ./agent-leak-app > "$out/console.log" 2>&1 &
runner=$!
while kill -0 "$runner" 2>/dev/null; do
    {
        date -u +%FT%T.%3NZ
        ps -C agent-leak-app -o pid,ppid,lstart,args
        ps -L -C agent-leak-app -o pid,lwp,stat,wchan:25,time,rss
        if [ -f "$out/agent_app.log" ]; then
            wc -c "$out/agent_app.log"
        fi
    } >> "$out/threads.log" || true
    sleep 2
done
status=0
wait "$runner" || status=$?
printf 'timeout_wait_status=%s\n' "$status" > "$out/exit.txt"
date -u +%FT%T.%3NZ > "$out/end.utc"
