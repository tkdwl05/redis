#!/bin/bash
# Quick Test Script for Redis Modules
# 빠른 테스트용 스크립트

echo "=========================================="
echo "Redis Modules Quick Test"
echo "=========================================="
echo ""

# Redis 서버가 실행 중인지 확인
if ! redis-cli ping > /dev/null 2>&1; then
    echo "❌ Redis server is not running!"
    echo "Start Redis with modules:"
    echo "  redis-server --loadmodule ./cachelock.so --loadmodule ./taskqueue.so --loadmodule ./distlock.so"
    exit 1
fi

echo "✅ Redis server is running"
echo ""

# 모듈 로드 확인
echo "📦 Checking loaded modules..."
MODULES=$(redis-cli MODULE LIST | grep -E "cachelock|taskqueue|distlock" | wc -l)
if [ $MODULES -eq 3 ]; then
    echo "✅ All 3 modules loaded"
else
    echo "❌ Modules not loaded. Found: $MODULES/3"
    echo "Load modules with:"
    echo "  redis-cli MODULE LOAD /path/to/cachelock.so"
    exit 1
fi
echo ""

# Cache Lock 테스트
echo "🔒 Testing CACHE.LOCK..."
RESULT=$(redis-cli CACHE.LOCK testkey 5000 10000)
if [ "$RESULT" == "LOAD" ] || [ "$RESULT" == "WAIT" ]; then
    echo "✅ CACHE.LOCK working: $RESULT"
else
    echo "❌ CACHE.LOCK failed"
    exit 1
fi

# Cache 설정 및 조회
redis-cli CACHE.SET testkey "test value" 60000 > /dev/null
CACHE_VALUE=$(redis-cli CACHE.GET testkey)
if [ "$CACHE_VALUE" == "test value" ]; then
    echo "✅ CACHE.SET/GET working"
else
    echo "❌ CACHE.SET/GET failed"
fi
echo ""

# Task Queue 테스트
echo "📬 Testing TASK.PUBLISH..."
redis-cli XGROUP CREATE test_tasks test_group $ MKSTREAM 2>/dev/null
TASK_ID=$(redis-cli TASK.PUBLISH test_tasks "test payload")
if [ ! -z "$TASK_ID" ]; then
    echo "✅ TASK.PUBLISH working: $TASK_ID"
else
    echo "❌ TASK.PUBLISH failed"
    exit 1
fi

# Task 소비
CONSUMED=$(redis-cli TASK.CONSUME test_group consumer1 test_tasks 1 100)
if [ ! -z "$CONSUMED" ]; then
    echo "✅ TASK.CONSUME working"
else
    echo "❌ TASK.CONSUME failed"
fi
echo ""

# Distributed Lock 테스트
echo "🔐 Testing LOCK.ACQUIRE..."
LOCK_RESULT=$(redis-cli LOCK.ACQUIRE test_lock process1 30000)
if [ "$LOCK_RESULT" == "1" ]; then
    echo "✅ LOCK.ACQUIRE working: acquired"
else
    echo "❌ LOCK.ACQUIRE failed"
    exit 1
fi

# 동일 락 재시도 (실패해야 함)
LOCK_RETRY=$(redis-cli LOCK.ACQUIRE test_lock process2 30000)
if [ "$LOCK_RETRY" == "0" ]; then
    echo "✅ LOCK duplicate prevention working"
else
    echo "❌ LOCK should have been blocked"
fi

# 락 해제
UNLOCK_RESULT=$(redis-cli LOCK.RELEASE test_lock process1)
if [ "$UNLOCK_RESULT" == "1" ]; then
    echo "✅ LOCK.RELEASE working"
else
    echo "❌ LOCK.RELEASE failed"
fi
echo ""

# 정리
redis-cli DEL testkey test_tasks test_lock > /dev/null 2>&1

echo "=========================================="
echo "✅ All tests passed!"
echo "=========================================="
echo ""
echo "Next steps:"
echo "  1. Read TEST_GUIDE.md for detailed testing"
echo "  2. Try the integration scenarios"
echo "  3. Monitor with: redis-cli INFO commandstats"
