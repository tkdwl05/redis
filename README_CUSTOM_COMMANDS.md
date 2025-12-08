# Redis 커스텀 리스트 명령어

[![Tests Passed](https://img.shields.io/badge/tests-passing-brightgreen.svg)](tests/)
[![Redis Version](https://img.shields.io/badge/Redis-7.0-red.svg)](https://redis.io/)

Redis에 새로운 리스트 명령어 3개 구현: `LCOUNT`, `LMAX`, `LMIN`

## 🚀 기능

### LCOUNT
리스트에서 특정 요소의 개수를 세는 명령어입니다.
```bash
redis> RPUSH mylist 1 2 3 1 1 2
redis> LCOUNT mylist 1
(integer) 3
```

### LMAX
리스트에서 최댓값을 찾는 명령어입니다 (숫자 또는 사전순).
```bash
# 숫자 비교
redis> RPUSH numbers 10 5 20 15
redis> LMAX numbers
"20"

# 문자열 비교
redis> RPUSH words abc z def
redis> LMAX words
"z"
```

### LMIN
리스트에서 최솟값을 찾는 명령어입니다 (숫자 또는 사전순).
```bash
# 숫자 비교
redis> LMIN numbers
"5"

# 문자열 비교
redis> LMIN words
"abc"
```

## 📋 명령어 스펙

| 명령어 | 문법 | 시간 복잡도 | 설명 |
|---------|--------|-----------------|-------------|
| `LCOUNT` | `LCOUNT key element` | O(N) | 리스트에서 요소의 출현 횟수 반환 |
| `LMAX` | `LMAX key` | O(N) | 최댓값 반환 (숫자 또는 사전순) |
| `LMIN` | `LMIN key` | O(N) | 최솟값 반환 (숫자 또는 사전순) |

## 🔧 설치 방법

1. **이 저장소를 클론하거나 패치를 적용합니다:**

```bash
# 수정된 파일들을 Redis 소스 디렉토리로 복사
cp src/commands/*.json ~/redis/src/commands/
cp src/t_list.c ~/redis/src/
cp src/server.h ~/redis/src/
```

2. **명령어 헤더 파일 생성:**

```bash
cd ~/redis
python utils/generate-command-code.py
```

3. **Redis 빌드:**

```bash
make clean
make
```

## 🧪 테스트

포함된 테스트 스위트 실행:

```bash
./runtest --single unit/type/list-custom
```

### 테스트 결과

```
✓ LCOUNT 기본 테스트
✓ LCOUNT 존재하지 않는 키 테스트
✓ LMAX 기본 테스트
✓ LMAX 문자열 테스트
✓ LMAX 빈 리스트 테스트
✓ LMIN 기본 테스트
✓ LMIN 문자열 테스트
✓ LMIN 빈 리스트 테스트

\o/ 모든 테스트 통과!
```

## 📁 수정된 파일

- `src/commands/lcount.json` - LCOUNT 명령어 정의
- `src/commands/lmax.json` - LMAX 명령어 정의
- `src/commands/lmin.json` - LMIN 명령어 정의
- `src/t_list.c` - 명령어 구현
- `src/server.h` - 함수 선언
- `tests/unit/type/list-custom.tcl` - 테스트 스위트

## 🎯 구현 세부사항

### 하이브리드 비교 전략

`LMAX`와 `LMIN`은 스마트 비교 전략을 사용합니다:
1. **먼저 숫자 비교 시도** - 모든 요소가 숫자로 변환 가능하면 숫자 비교 사용
2. **문자열 비교로 전환** - 숫자가 아닌 요소가 있으면 `sdscmp()`를 사용한 문자열 비교로 전환

이를 통해 다음을 보장합니다:
- `["10", "5", "20"]` → 최댓값: "20" (숫자 비교)
- `["abc", "z", "def"]` → 최댓값: "z" (사전순 비교)

### 메모리 안전성

- 정수로 인코딩된 객체를 안전하게 처리하기 위해 `getDecodedObject()` 사용
- 메모리 누수 방지를 위한 `decrRefCount()`로 적절한 참조 카운팅
- 처리 전 모든 입력 검증

## 🐛 알려진 문제

없음. 모든 테스트 통과.

## 📖 API 레퍼런스

### LCOUNT

**문법:** `LCOUNT key element`

**반환값:** 정수 - 리스트에서 요소의 출현 횟수

**예제:**
```bash
redis> RPUSH mylist a b a c a
(integer) 5
redis> LCOUNT mylist a
(integer) 3
redis> LCOUNT mylist x
(integer) 0
redis> LCOUNT nonexisting a
(integer) 0
```

### LMAX

**문법:** `LMAX key`

**반환값:** 문자열 - 최댓값, 또는 리스트가 비어있으면 nil

**예제:**
```bash
redis> RPUSH mylist 5 10 3 8
(integer) 4
redis> LMAX mylist
"10"
redis> DEL mylist
(integer) 1
redis> RPUSH mylist "apple" "banana" "cherry"
(integer) 3
redis> LMAX mylist
"cherry"
redis> LMAX emptylist
(nil)
```

### LMIN

**문법:** `LMIN key`

**반환값:** 문자열 - 최솟값, 또는 리스트가 비어있으면 nil

**예제:**
```bash
redis> RPUSH mylist 5 10 3 8
(integer) 4
redis> LMIN mylist
"3"
redis> DEL mylist
(integer) 1
redis> RPUSH mylist "apple" "banana" "cherry"
(integer) 3
redis> LMIN mylist
"apple"
```

## 🤝 기여

이 프로젝트는 학습 프로젝트입니다. 자유롭게 사용하고 수정하실 수 있습니다.

## 📝 라이선스

Redis 라이선스(BSD 3-Clause)를 따릅니다.

## ✨ 감사의 글

Redis 7.0.15를 기반으로 한 대학 프로젝트로 다음을 학습했습니다:
- Redis 내부 구조 및 명령어 구현
- 복잡한 자료구조를 사용한 C 프로그래밍
- 메모리 관리 및 참조 카운팅
- 테스트 주도 개발 (TDD)

---

**상태:** ✅ CentOS 7 환경의 Redis 7.0.15에서 완전히 동작하고 테스트 완료
