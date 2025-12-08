#!/bin/bash
# Rate Limit 테스트 스크립트
# 작성자: tkdwl05

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

REDIS_CLI="~/redis/src/redis-cli"

echo -e "${CYAN}========================================${NC}"
echo -e "${CYAN}Rate Limit 테스트${NC}"
echo -e "${CYAN}========================================${NC}"
echo ""

echo -e "${YELLOW}설정 가정:${NC}"
echo "  - 최대 요청: 10개"
echo "  - 시간 윈도우: 5초"
echo ""

echo -e "${GREEN}40개의 PING 요청을 빠르게 전송합니다...${NC}"
echo ""

# 시작 시간 기록
START_TIME=$(date +%s)

# 40개 요청 전송 + 응답 카운트
SUCCESS=0
FAILED=0

for i in {1..40}; do
    # PING 전송
    RESPONSE=$(echo "PING" | $REDIS_CLI 2>&1)
    
    # 응답 체크
    if [[ "$RESPONSE" == "PONG" ]]; then
        echo -e "${GREEN}[$i] ✓ PONG${NC}"
        ((SUCCESS++))
    else
        echo -e "${RED}[$i] ✗ $RESPONSE${NC}"
        ((FAILED++))
    fi
    
    # 너무 빠르면 0.05초 대기
    sleep 0.05
done

END_TIME=$(date +%s)
ELAPSED=$((END_TIME - START_TIME))

echo ""
echo -e "${CYAN}========================================${NC}"
echo -e "${CYAN}테스트 결과${NC}"
echo -e "${CYAN}========================================${NC}"
echo -e "${GREEN}성공: $SUCCESS${NC}"
echo -e "${RED}실패: $FAILED${NC}"
echo -e "${YELLOW}소요 시간: ${ELAPSED}초${NC}"
echo ""

if [ $FAILED -gt 0 ]; then
    echo -e "${YELLOW}Rate Limit이 작동 중입니다!${NC}"
    echo -e "${YELLOW}Redis 로그를 확인하세요:${NC}"
    echo "  tail -30 ~/redis/redis.log | grep 'Rate limit'"
else
    echo -e "${GREEN}모든 요청이 성공했습니다.${NC}"
    echo -e "${YELLOW}Rate Limit이 비활성화되었거나 제한을 초과하지 않았습니다.${NC}"
fi

echo ""
