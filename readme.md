

# OOM

[메모리 증가 및 MemoryGuard 종료 보고서](reports/oom.md) · [실행별 측정 자료](evidence/oom) · [RSS 수집 스크립트](scripts/monitor.sh)

Docker Desktop의 Linux 컨테이너 모드에서 저장소 루트를 열고 아래 PowerShell 명령을 실행한다. 각 실행은 일반 사용자로 구동되며 CPU 1개 분량, 메모리 1GiB, 최대 180초로 제한된다. 컨테이너 안에서 모니터와 대상 프로세스를 함께 실행한다. 실행별 디렉터리를 새로 만들어 이전 로그를 보존한다.

```powershell
docker compose -f compose.agent.yaml build agent
$base = (Get-Location).Path
$run = Get-Date -Format yyyyMMdd-HHmmss
foreach ($limit in 64,128) {
    $out = New-Item -ItemType Directory "evidence/oom/$run-$limit" -ErrorAction Stop
    docker compose -f compose.agent.yaml run --rm --no-deps -e "MEMORY_LIMIT=$limit" -e AGENT_LOG_DIR=/evidence -v "${base}/scripts:/scripts:ro" -v "$($out.FullName):/evidence" agent timeout 180 sh /scripts/monitor.sh /evidence
    if ($LASTEXITCODE -ne 0) { throw "수집 실패 ($LASTEXITCODE)" }
}
```

각 실행의 부팅 검사 결과는 `console.log`, 앱의 종료 상태는 `exit.txt`, PID별 RSS(KiB)는 `monitor.log`에 기록된다.

# CPU Spike

[CPU 과점유 및 Watchdog 보고서](reports/cpu.md) · [CPU 실행 증거](evidence/cpu) · [top 수집 스크립트](scripts/monitor-cpu.sh)

위와 같은 Linux 이미지에서 다음 PowerShell 명령으로 재현한다. 각 컨테이너에서 `top -b -d 1`이 전체 CPU 요약과 PID별 사용률을 함께 기록한다. 앱은 최대 90초 동안 관찰한다.

```powershell
$base = (Get-Location).Path
$run = Get-Date -Format yyyyMMdd-HHmmss
foreach ($limit in 10,100) {
    $out = New-Item -ItemType Directory "evidence/cpu/$run-$limit" -ErrorAction Stop
    docker compose -f compose.agent.yaml run --rm --no-deps -e "CPU_MAX_OCCUPY=$limit" -e MEMORY_LIMIT=512 -e MULTI_THREAD_ENABLE=false -e AGENT_LOG_DIR=/evidence -v "${base}/scripts:/scripts:ro" -v "$($out.FullName):/evidence" agent sh /scripts/monitor-cpu.sh
    if ($LASTEXITCODE -ne 0) { throw "수집 실패 ($LASTEXITCODE)" }
}
```

# Deadlock 

[교착상태 진단 보고서](reports/deadlock.md) · [실행별 원본 증거](evidence/deadlock) · [스레드 관측 스크립트](scripts/monitor-deadlock.sh)

위와 같은 Linux 이미지에서 아래 PowerShell 명령을 실행한다. 각 실행에서 PID와 TID, 스레드 대기 지점, 누적 CPU 시간, RSS, 앱 로그 크기를 약 2초 간격으로 기록한다. 40초가 지나면 수집기가 종료 신호를 보낸다.

```powershell
$base = (Get-Location).Path
$run = Get-Date -Format yyyyMMdd-HHmmss
foreach ($mode in 'true','false') {
    $out = New-Item -ItemType Directory "evidence/deadlock/$run-$mode" -ErrorAction Stop
    docker compose -f compose.agent.yaml run --rm --no-deps -e "MULTI_THREAD_ENABLE=$mode" -e MEMORY_LIMIT=512 -e CPU_MAX_OCCUPY=10 -e AGENT_LOG_DIR=/evidence -v "${base}/scripts:/scripts:ro" -v "$($out.FullName):/evidence" agent sh /scripts/monitor-deadlock.sh
    if ($LASTEXITCODE -ne 0) { throw "수집 실패 ($LASTEXITCODE)" }
}
```
