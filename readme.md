# Linux 프로세스 장애 진단 실습

이 저장소는 Linux 컨테이너에서 `agent-leak-app`의 메모리 증가, CPU 과점유, 교착상태를 재현하고 원인을 분석한 실습 기록이다. 메모리와 CPU 실험에서는 애플리케이션 로그를 PID별 자원 사용량과 대조해 프로세스가 종료된 이유를 추적했다. 교착상태 실험에서는 프로세스가 살아 있는데도 작업이 멈춘 이유를 두 워커의 락 획득 순서와 스레드 대기 상태로 확인했다.

각 실험은 환경변수 하나만 바꿔 변경 전후의 동작을 비교했다. 아래에서 실험별 진단 보고서, 원본 관측 로그, 재현 명령을 확인할 수 있다.

## OOM

[메모리 증가 및 MemoryGuard 종료 보고서](reports/oom.md) · [실행별 측정 자료](evidence/oom) · [RSS 수집 스크립트](scripts/monitor.sh) #1

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

## CPU Spike

[CPU 과점유 및 Watchdog 보고서](reports/cpu.md) · [CPU 실행 증거](evidence/cpu) · [top 수집 스크립트](scripts/monitor-cpu.sh) #2

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

## Deadlock

[교착상태 진단 보고서](reports/deadlock.md) · [실행별 원본 증거](evidence/deadlock) · [스레드 관측 스크립트](scripts/monitor-deadlock.sh) #3

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
