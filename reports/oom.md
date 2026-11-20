# [Bug] 힙이 계속 증가해 MemoryGuard가 에이전트를 종료함

## 현상과 재현 조건

2026년 11월 20일, 외부 요청 없이 기동한 `agent-leak-app`에서 힙과 RSS가 함께 증가했다. 에이전트는 포트 15034에서 연결을 기다리다가 두 실행 모두 자체 메모리 보호 정책에 따라 종료됐다. 아래 시각은 UTC다.

Ubuntu 24.04.5 x86_64 컨테이너에서 UID 10001로 실행했다. CPU 할당량은 1코어 분량, 컨테이너 메모리 한도는 1GiB였다. 앱 설정은 `CPU_MAX_OCCUPY=50`, `MULTI_THREAD_ENABLE=true`로 고정하고 `MEMORY_LIMIT`만 변경했다. 저장소에 기존 관제 스크립트가 없어 [monitor.sh](../scripts/monitor.sh)를 작성했다. 스크립트는 `ps`로 같은 이름의 부모·자식 프로세스를 기록하며, 아래 RSS는 종료 로그가 지목한 자식 PID의 값이다. [재현 명령](../readme.md)

## Before & After

| 측정 항목 | Before · run-64 | After · run-128 |
| --- | ---: | ---: |
| MEMORY_LIMIT | 64MB | 128MB |
| 앱 PID | 27 | 24 |
| 서비스 시작 → 자체 종료 선언 | 08:50:59.004 → 08:51:15.900 | 08:51:28.199 → 08:51:53.373 |
| 서비스 생존 시간 | 16.896초 | 25.174초 |
| 서비스 시작 후 첫 RSS → 마지막 RSS | 17.7 → 92.7 MiB | 17.5 → 153.3 MiB |
| 해당 표본 구간의 평균 RSS 증가율 | 4.60 MiB/s | 5.66 MiB/s |
| MemoryGuard 판단 시 힙 | 75MB | 150MB |
| 런처 종료 코드 | 137 | 137 |
| cgroup의 oom_kill 증가량 | 0 | 0 |

생존 시간은 두 실행에서 같은 로그 이벤트인 `Agent listening`부터 `Self-terminating`까지로 정의했다. RSS 증가율은 서비스 시작 후 첫 표본과 마지막 표본의 차이를 두 표본 간 실제 시간으로 나눈 값이다. 수집 루프는 1초씩 대기하므로 실제 표본 간격에는 실행 지연이 포함된다.

## 증거

| 실행 | monitor.sh에서 발췌한 시각 → RSS (KiB) |
| --- | --- |
| [64MB 원본](../evidence/oom/run-64/monitor.log) | 08:50:59.350 → 18,076 · 08:51:02.407 → 43,680 · 08:51:06.561 → 69,284 · 08:51:15.672 → 94,888 |
| [128MB 원본](../evidence/oom/run-128/monitor.log) | 08:51:28.567 → 17,916 · 08:51:30.604 → 43,520 · 08:51:36.563 → 69,124 · 08:51:51.201 → 145,936 · 08:51:52.570 → 156,968 |

64MB 실행에서 앱이 남긴 마지막 세 줄이다. [앱 로그](../evidence/oom/run-64/agent_app.log)

```text
2026-11-20 08:51:15,674 [INFO] [MemoryWorker] Current Heap: 75MB
2026-11-20 08:51:15,875 [CRITICAL] [MemoryGuard] Memory limit exceeded (75MB >= 64MB) / (Recommend Over 256MB)
2026-11-20 08:51:15,900 [CRITICAL] [MemoryGuard] Self-terminating process 27 to prevent system instability.
```

128MB 실행은 힙 75MB를 통과하고 100MB, 125MB를 거쳐 다음 기록으로 끝났다. [앱 로그](../evidence/oom/run-128/agent_app.log)

```text
2026-11-20 08:51:53,332 [INFO] [MemoryWorker] Current Heap: 150MB
2026-11-20 08:51:53,363 [CRITICAL] [MemoryGuard] Memory limit exceeded (150MB >= 128MB) / (Recommend Over 256MB)
2026-11-20 08:51:53,373 [CRITICAL] [MemoryGuard] Self-terminating process 24 to prevent system instability.
```

종료 후 수집기가 런처를 회수해 두 번 모두 코드 137을 기록했다. 종료 코드만으로는 원인을 특정할 수 없다. 두 컨테이너에서 실행 전후 `memory.events`의 `oom`과 `oom_kill`이 모두 0이었고, 각 앱 로그에는 임계치 비교와 해당 PID의 자체 종료 선언이 연속해서 남았다. 직접적인 종료 원인은 MemoryGuard다. [64MB 실행 증거](../evidence/oom/run-64) · [128MB 실행 증거](../evidence/oom/run-128)

## 메모리 구조와 원인 해석

힙은 실행 중 동적으로 할당한 데이터를 담는 영역이다. 앱이 기록한 `Current Heap`은 25MB 단위로 증가했고, MemoryGuard의 비교값은 마지막 힙 로그와 일치했다. Linux의 RSS는 힙 외에도 스택, 코드, 공유 라이브러리 등 해당 프로세스에서 실제 RAM에 올라온 페이지를 포함한다. 따라서 앱의 힙 수치와 RSS는 측정 범위가 다르다. 특히 128MB 실행의 마지막 RSS 표본은 최종 힙 로그보다 약 0.76초 앞선다.

두 실행 모두 힙 증가와 함께 RSS가 계단식으로 상승했고 종료 전까지 이전 수준으로 회복되지 않았다. 이는 MemoryWorker 실행 중 메모리가 누적되는 누수 증상과 일치한다. 어떤 객체가 계속 참조되는지, 어느 할당 경로에서 해제가 누락되는지까지 규명하려면 소스 또는 시간대별 힙 프로파일이 필요하다.

## 조치 검증

임계치를 64MB에서 128MB로 높이자 이번 비교에서 서비스 생존 시간이 **8.278초(약 49%)** 늘었다. 상향 후에도 메모리가 계속 증가해 같은 정책으로 종료됐다. 따라서 임계치 조정은 종료를 늦추는 임시 완화다. 조건별 1회 측정이므로 연장 시간은 이 두 실행의 관측값이다.
