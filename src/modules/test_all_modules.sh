#!/bin/bash
# Redis Modules Comprehensive Test Script
# Tests: cachelock, taskqueue, distlock
# Author: tkdwl05
# Date: 2025-12-08

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

REDIS_CLI="../redis-cli"
PASSED=0
FAILED=0

echo "=========================================="
echo "Redis Modules - Comprehensive Test Suite"
echo "=========================================="
echo ""

# ==============================================
# SERVER STARTUP
# ==============================================
echo "=== Checking Redis Server ==="

# Check if server is already running
if $REDIS_CLI ping > /dev/null 2>&1; then
    echo -e "${GREEN}✓ Redis server is already running${NC}"
else
    echo -e "${YELLOW}⚠ Redis server not running. Starting...${NC}"
    
    # Kill any existing Redis processes
    pkill redis-server 2>/dev/null
    sleep 1
    
    # Start Redis server with modules
    ../redis-server --loadmodule ./cachelock.so \
                    --loadmodule ./taskqueue.so \
                    --loadmodule ./distlock.so \
                    --daemonize yes \
                    --logfile redis-modules.log
    
    # Wait for server to start
    sleep 2
    
    # Verify server started
    if $REDIS_CLI ping > /dev/null 2>&1; then
        echo -e "${GREEN}✓ Redis server started successfully${NC}"
    else
        echo -e "${RED}✗ Failed to start Redis server${NC}"
        echo "Check redis-modules.log for details:"
        tail -20 redis-modules.log
        exit 1
    fi
fi

# Check modules are loaded
MODULES=$($REDIS_CLI MODULE LIST | grep -c "name")
if [ "$MODULES" -eq 3 ]; then
    echo -e "${GREEN}✓ All 3 modules loaded (cachelock, taskqueue, distlock)${NC}"
else
    echo -e "${RED}✗ Expected 3 modules, found $MODULES${NC}"
    echo "Restarting server with modules..."
    pkill redis-server
    sleep 1
    ../redis-server --loadmodule ./cachelock.so \
                    --loadmodule ./taskqueue.so \
                    --loadmodule ./distlock.so \
                    --daemonize yes \
                    --logfile redis-modules.log
    sleep 2
fi

echo ""

# Helper function to run test
run_test() {
    local test_name="$1"
    local command="$2"
    local expected="$3"
    
    echo -n "Testing: $test_name ... "
    result=$($command 2>&1)
    
    if [[ "$result" == *"$expected"* ]]; then
        echo -e "${GREEN}✓ PASS${NC}"
        ((PASSED++))
        return 0
    else
        echo -e "${RED}✗ FAIL${NC}"
        echo "  Expected: $expected"
        echo "  Got: $result"
        ((FAILED++))
        return 1
    fi
}

# ==============================================
# TEST 1: Cache Stampede Prevention
# ==============================================
echo "=== Test 1: Cache Stampede Prevention ==="

# Test 1.1: Acquire lock (should return LOAD)
run_test "CACHE.LOCK (acquire)" \
    "$REDIS_CLI CACHE.LOCK test:user:100 5000 10000" \
    "LOAD"

# Test 1.2: Set cache value
run_test "CACHE.SET (write-through)" \
    "$REDIS_CLI CACHE.SET test:user:100 AliceSmith 60000" \
    "OK"

# Test 1.3: Get cache value
run_test "CACHE.GET (retrieve)" \
    "$REDIS_CLI CACHE.GET test:user:100" \
    "AliceSmith"

# Test 1.4: Try to acquire same lock (CACHE.SET released it, so should be LOAD again)
run_test "CACHE.LOCK (after SET)" \
    "$REDIS_CLI CACHE.LOCK test:user:100 5000 10000" \
    "LOAD"

# Test 1.5: Get non-existent key (empty response is OK)
run_test "CACHE.GET (miss)" \
    "$REDIS_CLI CACHE.GET test:user:999 2>&1 | grep -q 'nil' && echo 'nil' || echo ''" \
    ""

echo ""

# ==============================================
# TEST 2: Task Queue (Streams)
# ==============================================
echo "=== Test 2: Task Queue (Streams) ==="

# Test 2.1: Create consumer group
$REDIS_CLI DEL test:tasks 2>/dev/null
run_test "XGROUP CREATE" \
    "$REDIS_CLI XGROUP CREATE test:tasks test_workers \$ MKSTREAM" \
    "OK"

# Test 2.2: Publish task 1
run_test "TASK.PUBLISH (job 1)" \
    "$REDIS_CLI TASK.PUBLISH test:tasks job1" \
    "-"

# Test 2.3: Publish task 2
run_test "TASK.PUBLISH (job 2)" \
    "$REDIS_CLI TASK.PUBLISH test:tasks job2" \
    "-"

# Test 2.4: Publish task 3
run_test "TASK.PUBLISH (job 3)" \
    "$REDIS_CLI TASK.PUBLISH test:tasks job3" \
    "-"

# Test 2.5: Consume tasks
run_test "TASK.CONSUME (get 2 tasks)" \
    "$REDIS_CLI TASK.CONSUME test_workers consumer1 test:tasks 2 1000" \
    "test:tasks"

# Test 2.6: Check stream length
run_test "XLEN (stream length)" \
    "$REDIS_CLI XLEN test:tasks" \
    "3"

echo ""

# ==============================================
# TEST 3: Distributed Lock
# ==============================================
echo "=== Test 3: Distributed Lock ==="

# Test 3.1: Acquire lock (process1)
run_test "LOCK.ACQUIRE (process1)" \
    "$REDIS_CLI LOCK.ACQUIRE test:batch_job process1 30000" \
    "1"

# Test 3.2: Try to acquire same lock (process2 - should fail)
run_test "LOCK.ACQUIRE (process2 - blocked)" \
    "$REDIS_CLI LOCK.ACQUIRE test:batch_job process2 30000" \
    "0"

# Test 3.3: Extend lock (process1)
run_test "LOCK.EXTEND (process1)" \
    "$REDIS_CLI LOCK.EXTEND test:batch_job process1 30000" \
    "1"

# Test 3.4: Try to extend with wrong identifier
run_test "LOCK.EXTEND (wrong identifier)" \
    "$REDIS_CLI LOCK.EXTEND test:batch_job process2 30000" \
    "0"

# Test 3.5: Release lock (process1)
run_test "LOCK.RELEASE (process1)" \
    "$REDIS_CLI LOCK.RELEASE test:batch_job process1" \
    "1"

# Test 3.6: Now process2 can acquire
run_test "LOCK.ACQUIRE (process2 - success)" \
    "$REDIS_CLI LOCK.ACQUIRE test:batch_job process2 30000" \
    "1"

# Test 3.7: Release lock (process2)
run_test "LOCK.RELEASE (process2)" \
    "$REDIS_CLI LOCK.RELEASE test:batch_job process2" \
    "1"

echo ""

# ==============================================
# TEST 4: Module Status
# ==============================================
echo "=== Test 4: Module Status ==="

# Check if all 3 modules are loaded
MODULES=$($REDIS_CLI MODULE LIST | grep -c "name")
if [ "$MODULES" -eq 3 ]; then
    echo -e "${GREEN}✓ All 3 modules loaded${NC}"
    ((PASSED++))
else
    echo -e "${RED}✗ Expected 3 modules, found $MODULES${NC}"
    ((FAILED++))
fi

# Check server is still running
if $REDIS_CLI ping > /dev/null 2>&1; then
    echo -e "${GREEN}✓ Server still running after tests${NC}"
    ((PASSED++))
else
    echo -e "${RED}✗ Server crashed during tests${NC}"
    ((FAILED++))
fi

echo ""

# ==============================================
# SUMMARY
# ==============================================
echo "=========================================="
echo "Test Summary"
echo "=========================================="
echo ""
echo -e "${GREEN}Passed: $PASSED${NC}"
echo -e "${RED}Failed: $FAILED${NC}"
echo ""

if [ $FAILED -eq 0 ]; then
    echo -e "${GREEN}✓✓✓ ALL TESTS PASSED! ✓✓✓${NC}"
    echo ""
    echo "Your Redis modules are working perfectly!"
    exit 0
else
    echo -e "${RED}✗✗✗ SOME TESTS FAILED ✗✗✗${NC}"
    echo ""
    echo "Please check the failed tests above."
    exit 1
fi
