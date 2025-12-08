# Redis Modules 테스트 가이드

## 🚀 1단계: 모듈 로드

### Redis 서버 시작
```bash
cd /path/to/redis/src/modules

# 모듈과 함께 Redis 서버 시작
redis-server --loadmodule ./cachelock.so \
             --loadmodule ./taskqueue.so \
             --loadmodule ./distlock.so
```

또는 백그라운드로 실행:
```bash
redis-server --loadmodule ./cachelock.so \
             --loadmodule ./taskqueue.so \
             --loadmodule ./distlock.so \
             --daemonize yes \
             --logfile redis-modules.log
```

### 모듈 로드 확인
```bash
redis-cli MODULE LIST
```

예상 출력:
```
1) 1) "name"
   2) "cachelock"
   3) "ver"
   4) (integer) 1
2) 1) "name"
   2) "taskqueue"
   3) "ver"
   4) (integer) 1
3) 1) "name"
   2) "distlock"
   3) "ver"
   4) (integer) 1
```

---

## 🔒 2단계: Cache Stampede Prevention 테스트

### 터미널 1 - 클라이언트 1
```bash
redis-cli

# 락 획득 시도
> CACHE.LOCK user:1234 5000 10000
"LOAD"   # 성공! 이 클라이언트가 로더

# 3초 대기 (DB 로딩 시뮬레이션)
# ... 3초 후 ...

# 캐시에 데이터 저장 (락 자동 해제)
> CACHE.SET user:1234 "John Doe, age 30" 60000
"OK"
```

### 터미널 2 - 클라이언트 2 (동시 실행)
```bash
redis-cli

# 같은 키에 대해 락 획득 시도 (클라이언트 1과 동시)
> CACHE.LOCK user:1234 5000 10000
"WAIT"   # 대기! 다른 클라이언트가 로딩 중

# 3초 후 다시 조회
> CACHE.GET user:1234
"John Doe, age 30"   # 클라이언트 1이 캐시한 데이터
```

### 캐시 히트 테스트
```bash
redis-cli

> CACHE.GET user:1234
"John Doe, age 30"

> CACHE.GET user:9999
(nil)   # 없는 키
```

---

## 📬 3단계: Task Queue 테스트

### Consumer Group 생성
```bash
redis-cli

> XGROUP CREATE tasks workers $ MKSTREAM
"OK"
```

### Producer - 작업 발행
```bash
redis-cli

> TASK.PUBLISH tasks "Process order #1001"
"1733658000000-0"

> TASK.PUBLISH tasks "Process order #1002"
"1733658001000-0"

> TASK.PUBLISH tasks "Process order #1003"
"1733658002000-0"

# 발행된 작업 확인
> XLEN tasks
(integer) 3
```

### Consumer 1 - 작업 소비
```bash
redis-cli

# 10개 작업을 최대 5초 동안 대기하며 소비
> TASK.CONSUME workers consumer1 tasks 10 5000
1) 1) "tasks"
   2) 1) 1) "1733658000000-0"
         2) 1) "payload"
            2) "Process order #1001"
            3) "timestamp"
            4) "1733658000"
            5) "retry_count"
            6) "0"

# 작업 완료 처리
> TASK.ACK tasks workers 1733658000000-0
(integer) 1
```

### Consumer 2 - 병렬 소비
```bash
redis-cli

> TASK.CONSUME workers consumer2 tasks 10 5000
1) 1) "tasks"
   2) 1) 1) "1733658001000-0"
         2) ...   # 다른 작업 (자동 분배됨)
```

### 실패 및 재시도 테스트
```bash
redis-cli

# Consumer Group 생성 (retry용)
> XGROUP CREATE retry_tasks workers $ MKSTREAM
"OK"

> XGROUP CREATE dead_tasks workers $ MKSTREAM
"OK"

# 작업 실패 시뮬레이션 - 재시도
> TASK.RETRY tasks "1733658002000-0" "Process order #1003" 0 retry_tasks dead_tasks 3
"OK"

# 재시도 스트림 확인
> XLEN retry_tasks
(integer) 1

# 3번 재시도 후 dead letter 이동
> TASK.RETRY tasks "1733658002000-0" "Process order #1003" 3 retry_tasks dead_tasks 3
"OK"

> XLEN dead_tasks
(integer) 1
```

---

## 🔐 4단계: Distributed Lock 테스트

### 프로세스 1 - 락 획득
```bash
redis-cli

> LOCK.ACQUIRE daily_job process1 30000
(integer) 1   # 성공!

# 작업 실행 중...
# (30초 내에)

# 락 갱신 (작업이 길어질 경우)
> LOCK.EXTEND daily_job process1 30000
(integer) 1   # 갱신 성공

# 작업 완료 후 락 해제
> LOCK.RELEASE daily_job process1
(integer) 1
```

### 프로세스 2 - 동시 락 시도
```bash
redis-cli

# 프로세스 1이 락을 보유 중일 때
> LOCK.ACQUIRE daily_job process2 30000
(integer) 0   # 실패! 이미 process1이 보유

# 프로세스 1이 락을 해제한 후
> LOCK.ACQUIRE daily_job process2 30000
(integer) 1   # 이제 성공!
```

### 잘못된 해제 시도 (보안 테스트)
```bash
redis-cli

# process1이 락 보유 중
> LOCK.RELEASE daily_job process2
(integer) 0   # 실패! process2는 권한 없음

# 올바른 식별자로만 해제 가능
> LOCK.RELEASE daily_job process1
(integer) 1   # 성공
```

---

## 🧪 5단계: 통합 시나리오 테스트

### 시나리오: 사용자 프로필 캐싱 + 작업 처리

```bash
# 터미널 1: Cache + Queue Producer
redis-cli

# 1. 캐시 확인
> CACHE.GET user:5678
(nil)

# 2. 캐시 미스 - 락 획득
> CACHE.LOCK user:5678 5000 10000
"LOAD"

# 3. 프로필 로드 작업을 큐에 발행
> TASK.PUBLISH profile_load_tasks "load_user:5678"
"1733658100000-0"

# 4. (DB 로드 후) 캐시에 저장
> CACHE.SET user:5678 "Jane Smith, age 25" 60000
"OK"
```

```bash
# 터미널 2: Task Consumer + Lock
redis-cli

# 1. Consumer Group 생성
> XGROUP CREATE profile_load_tasks workers $ MKSTREAM
"OK"

# 2. 배치 작업용 락 획득
> LOCK.ACQUIRE batch_profile_sync scheduler1 300000
(integer) 1

# 3. 작업 소비
> TASK.CONSUME workers worker1 profile_load_tasks 10 5000
1) ...

# 4. 작업 완료
> TASK.ACK profile_load_tasks workers 1733658100000-0
(integer) 1

# 5. 배치 작업 완료 후 락 해제
> LOCK.RELEASE batch_profile_sync scheduler1
(integer) 1
```

---

## ✅ 테스트 체크리스트

- [ ] 모듈이 정상적으로 로드되는가?
- [ ] CACHE.LOCK이 동시 요청 시 하나만 "LOAD" 반환하는가?
- [ ] CACHE.SET 후 CACHE.GET으로 값을 조회할 수 있는가?
- [ ] TASK.PUBLISH로 발행한 작업이 TASK.CONSUME으로 소비되는가?
- [ ] 여러 Consumer가 작업을 분산 처리하는가?
- [ ] TASK.RETRY가 정상 작동하는가?
- [ ] LOCK.ACQUIRE가 동시 요청 시 하나만 성공하는가?
- [ ] LOCK.RELEASE가 올바른 식별자만 허용하는가?
- [ ] LOCK.EXTEND가 정상 작동하는가?

---

## 🐛 트러블슈팅

### 모듈 로드 실패
```bash
# 에러: ERR Error loading the extension
# 해결: redismodule.h 경로 확인
ls -la ../redismodule.h

# 재빌드
make clean
make
```

### 명령어 인식 안 됨
```bash
# 확인
redis-cli MODULE LIST

# 모듈 언로드 후 재로드
redis-cli MODULE UNLOAD cachelock
redis-cli MODULE LOAD /path/to/cachelock.so
```

### 성능 모니터링
```bash
# Redis 통계
redis-cli INFO stats

# 명령어 실행 횟수
redis-cli INFO commandstats
```

---

## 📊 예상 결과

성공적인 테스트 완료 시:
- ✅ 캐시 스탬피드 방지: 동시 100 요청 시 DB 조회 1회만
- ✅ 작업 큐: Consumer 분산 처리 확인
- ✅ 분산 락: 동시 획득 시도 시 1개만 성공

축하합니다! 🎉
Redis 고급 기능 모듈이 정상 작동합니다!
