# Redis Advanced Features - Redis Modules

Redis 고급 기능 구현: 캐시 스탬피드 방지, Streams 작업 큐, 분산 락 (C 언어 Redis Module)

## 🎯 프로젝트 개요

이 프로젝트는 Redis의 세 가지 고급 기능을 **Redis Module**로 구현합니다:

1. **Cache Stampede Prevention** - 캐시 스탬피드 방지
2. **Streams Task Queue** - Streams 기반 작업 큐  
3. **Distributed Lock** - 분산 락

## 📁 파일 구조

```
redis/
└── src/
    └── modules/
        ├── cachelock.c    # 캐시 스탬피드 방지 모듈
        ├── taskqueue.c    # 작업 큐 모듈
        ├── distlock.c     # 분산 락 모듈
        └── Makefile       # 빌드 파일
```

## 🔧 빌드 방법

```bash
cd src/modules
make

# 출력: cachelock.so, taskqueue.so, distlock.so
```

## 🚀 사용 방법

### 1. 모듈 로드

```bash
# Redis 서버 시작 시 모듈 로드
redis-server --loadmodule ./src/modules/cachelock.so \
             --loadmodule ./src/modules/taskqueue.so \
             --loadmodule ./src/modules/distlock.so
```

또는 런타임에 로드:

```bash
redis-cli MODULE LOAD /path/to/cachelock.so
redis-cli MODULE LOAD /path/to/taskqueue.so
redis-cli MODULE LOAD /path/to/distlock.so
```

### 2. Cache Stampede Prevention

**명령어:**
- `CACHE.LOCK key ttl_ms loader_timeout_ms` - 락 획득
- `CACHE.SET key value ttl_ms` - 캐시 설정 + 락 해제
- `CACHE.GET key` - 캐시 조회

**사용 예:**

```bash
# 클라이언트 1: 락 획득
redis-cli> CACHE.LOCK user:1234 5000 10000
"LOAD"  # 이 클라이언트가 DB에서 데이터를 로드해야 함

# 클라이언트 2: 동일 키 접근
redis-cli> CACHE.LOCK user:1234 5000 10000
"WAIT"  # 다른 클라이언트가 로드 중, 대기

# 클라이언트 1: 데이터 캐시
redis-cli> CACHE.SET user:1234 "user data" 60000
"OK"

# 이후 모든 클라이언트
redis-cli> CACHE.GET user:1234
"user data"
```

### 3. Streams Task Queue

**명령어:**
- `TASK.PUBLISH stream payload [retry_count]` - 작업 발행
- `TASK.CONSUME group consumer stream [count] [block_ms]` - 작업 소비
- `TASK.ACK stream group stream_id` - 작업 완료 확인
- `TASK.RETRY stream stream_id payload retry_count retry_stream dlq max_retries` - 재시도

**사용 예:**

```bash
# Consumer Group 생성
redis-cli> XGROUP CREATE tasks workers $ MKSTREAM
"OK"

# 작업 발행
redis-cli> TASK.PUBLISH tasks "job1"
"1733654321000-0"

# 작업 소비 (5초 대기)
redis-cli> TASK.CONSUME workers consumer1 tasks 10 5000
1) 1) "tasks"
   2) 1) 1) "1733654321000-0"
         2) 1) "payload"
            2) "job1"
            3) "timestamp"
            4) "1733654321"
            5) "retry_count"
            6) "0"

# 작업 완료 확인
redis-cli> TASK.ACK tasks workers 1733654321000-0
(integer) 1

# 실패 시 재시도
redis-cli> TASK.RETRY tasks 1733654321000-0 "job1" 0 retry_tasks dead_tasks 3
"OK"
```

### 4. Distributed Lock

**명령어:**
- `LOCK.ACQUIRE lock_name identifier ttl_ms` - 락 획득
- `LOCK.RELEASE lock_name identifier` - 락 해제
- `LOCK.EXTEND lock_name identifier ttl_ms` - 락 갱신

**사용 예:**

```bash
# 프로세스 1: 락 획득
redis-cli> LOCK.ACQUIRE daily_job process1 30000
(integer) 1  # 성공

# 프로세스 2: 동일 락 시도
redis-cli> LOCK.ACQUIRE daily_job process2 30000
(integer) 0  # 실패 (이미 process1이 보유)

# 프로세스 1: 락 갱신
redis-cli> LOCK.EXTEND daily_job process1 30000
(integer) 1

# 프로세스 1: 락 해제
redis-cli> LOCK.RELEASE daily_job process1
(integer) 1
```

## 🎨 주요 기능

### Cache Stampede Prevention
- ✅ Mutex 기반 락으로 DB 로더 1회만 실행
- ✅ Write-through 캐시 지원
- ✅ TTL 자동 관리

### Streams Task Queue
- ✅ Consumer Group 지원
- ✅ 자동 재시도 로직
- ✅ Dead-letter queue
- ✅ At-least-once 처리 보장

### Distributed Lock
- ✅ Lua 스크립트로 원자적 해제
- ✅ 락 갱신 (renewal) 지원
- ✅ 배치 작업 동시 실행 방지

## 🧪 테스트

```bash
# 모듈 빌드 확인
cd src/modules
make test

# Redis 서버 로그 확인
redis-server --loglevel debug \
             --loadmodule ./cachelock.so \
             --loadmodule ./taskqueue.so \
             --loadmodule ./distlock.so
```

## 📊 성능 목표

| 항목 | 목표 |
|------|------|
| 캐시 스탬피드 방지 | 동시 100 요청 시 DB 조회 1회 |
| 큐 처리량 | 1000+ tasks/sec |
| 락 획득 시간 | 평균 < 5ms |

## 🔍 구현 세부사항

### Cache Lock 메커니즘
```
SET lock:{key} 1 NX PX ttl_ms
→ 성공: "LOAD" (DB 로더 역할)
→ 실패: "WAIT" (다른 로더 대기)
```

### Task Queue 흐름
```
Producer → XADD → Stream
                    ↓
         XREADGROUP (Consumer Group)
                    ↓
         Process → XACK (성공) / RETRY (실패)
```

### Distributed Lock 원자성
```lua
-- LOCK.RELEASE Lua 스크립트
if redis.call("get", KEYS[1]) == ARGV[1] then
    return redis.call("del", KEYS[1])
else
    return 0
end
```

## 📝 라이선스

이 프로젝트는 학술적 목적으로 작성되었습니다.

## 👤 Author

tkdwl05

---

**Redis Version:** 7.0+  
**Language:** C99  
**Build System:** Make
