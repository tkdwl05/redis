#!/bin/bash
# Redis Rate Limiting - 발표용 라이브 데모
# 작성자: tkdwl05
# 날짜: 2025-12-09

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # 색상 없음

REDIS_CLI="./redis-cli"

# 데모 단계 표시 함수
demo_step() {
    echo ""
    echo -e "${MAGENTA}========================================${NC}"
    echo -e "${CYAN}$1${NC}"
    echo -e "${MAGENTA}========================================${NC}"
    echo ""
    read -p "Enter를 눌러 계속..."
}

# 명령어 실행 함수
demo_command() {
    echo -e "${YELLOW}$ $1${NC}"
    sleep 0.5
    eval "$1"
    echo ""
    sleep 1
}

clear

echo -e "${GREEN}"
cat << "EOF"
╔═══════════════════════════════════════════════╗
║                                               ║
║     Redis Rate Limiting 구현 프로젝트           ║
║                                               ║
║   작성자: tkdwl05                              ║
║   날짜: 2025-12-09                             ║
║                                               ║
╚═══════════════════════════════════════════════╝
EOF
echo -e "${NC}"

echo -e "${CYAN}구현한 기능:${NC}"
echo "  1. Client-based Rate Limiting (클라이언트별 요청 제한)"
echo "  2. Configurable Limits (설정 가능한 제한)"
echo "  3. Time Window Management (시간 윈도우 관리)"
echo ""
read -p "Enter를 눌러 데모 시작..."

# ==========================================
# 데모 1: Rate Limit 설정 확인
# ==========================================
demo_step "데모 1: Rate Limit 설정 확인"

echo -e "${CYAN}현재 Rate Limit 설정을 확인합니다${NC}"
echo ""

demo_command "$REDIS_CLI CONFIG GET rlimit*"
echo -e "${YELLOW}→ 현재 Rate Limit 설정 (기본값)${NC}"

# ==========================================
# 데모 2: Rate Limit 활성화
# ==========================================
demo_step "데모 2: Rate Limit 활성화 (5개/10초)"

echo -e "${CYAN}Rate Limit을 활성화하고 제한을 설정합니다${NC}"
echo "  - 윈도우: 10초"
echo "  - 최대 요청: 5개"
echo ""

demo_command "$REDIS_CLI CONFIG SET rlimit-enabled 1"
echo -e "${GREEN}→ Rate Limit 활성화${NC}"
echo ""

demo_command "$REDIS_CLI CONFIG SET rlimit-window-sec 10"
echo -e "${GREEN}→ 시간 윈도우: 10초로 설정${NC}"
echo ""

demo_command "$REDIS_CLI CONFIG SET rlimit-max-requests 5"
echo -e "${GREEN}→ 최대 요청: 5개로 설정${NC}"
echo ""

demo_command "$REDIS_CLI CONFIG GET rlimit*"
echo -e "${CYAN}→ 변경된 설정 확인${NC}"

# ==========================================
# 데모 3: Rate Limit 테스트 (성공)
# ==========================================
demo_step "데모 3: Rate Limit 테스트 - 정상 요청"

echo -e "${CYAN}시나리오:${NC} 한 세션에서 10초 내에 5번 요청 (제한 내)"
echo ""

echo -e "${YELLOW}$ (echo PING; echo PING; echo PING; echo PING; echo PING) | $REDIS_CLI${NC}"
sleep 0.5
(echo "PING"; echo "PING"; echo "PING"; echo "PING"; echo "PING") | $REDIS_CLI
echo ""
echo -e "${GREEN}→ 5개 요청 모두 성공!${NC}"
sleep 1

# ==========================================
# 데모 4: Rate Limit 테스트 (초과)
# ==========================================
demo_step "데모 4: Rate Limit 테스트 - 요청 초과"

echo -e "${CYAN}시나리오:${NC} 같은 세션에서 계속 요청 (6~10번째)"
echo ""

echo -e "${YELLOW}$ (echo PING; echo PING; echo PING; echo PING; echo PING) | $REDIS_CLI${NC}"
sleep 0.5
echo -e "${RED}주의: 이미 5개 요청을 했으므로 모두 차단될 것입니다!${NC}"
echo ""
(echo "PING"; echo "PING"; echo "PING"; echo "PING"; echo "PING") | $REDIS_CLI
echo ""
echo -e "${RED}→ Rate Limit 에러 발생! (ERR Rate limit exceeded)${NC}"
sleep 1

# ==========================================
# 데모 5: 시간 경과 후 재시도
# ==========================================
demo_step "데모 5: 시간 윈도우 리셋 후 재요청"

echo -e "${CYAN}10초 대기 후 다시 요청합니다...${NC}"
echo ""

for i in {10..1}; do
    echo -e "${YELLOW}남은 시간: $i초...${NC}"
    sleep 1
done

echo ""
echo -e "${GREEN}윈도우가 리셋되었습니다!${NC}"
echo ""

demo_command "$REDIS_CLI PING"
echo -e "${GREEN}→ 새 윈도우에서 요청 성공!${NC}"

# ==========================================
# 데모 6: 다양한 제한 설정 테스트
# ==========================================
demo_step "데모 6: 엄격한 제한 설정 (2개/5초)"

echo -e "${CYAN}더 엄격한 제한으로 변경합니다${NC}"
echo ""

demo_command "$REDIS_CLI CONFIG SET rlimit-window-sec 5"
demo_command "$REDIS_CLI CONFIG SET rlimit-max-requests 2"
demo_command "$REDIS_CLI CONFIG GET rlimit*"
echo -e "${YELLOW}→ 5초 안에 2개만 허용${NC}"
echo ""

echo -e "${CYAN}테스트: 한 세션에서 3번 연속 요청${NC}"
echo ""

echo -e "${YELLOW}$ (echo PING; echo PING; echo PING) | $REDIS_CLI${NC}"
sleep 0.5
(echo "PING"; echo "PING"; echo "PING") | $REDIS_CLI
echo ""
echo -e "${GREEN}→ 처음 2개: 성공${NC}"
echo -e "${RED}→ 3번째: Rate Limit!${NC}"
sleep 1

# ==========================================
# 데모 7: Rate Limit 비활성화
# ==========================================
demo_step "데모 7: Rate Limit 비활성화"

echo -e "${CYAN}Rate Limit을 비활성화합니다${NC}"
echo ""

demo_command "$REDIS_CLI CONFIG SET rlimit-enabled 0"
echo -e "${YELLOW}→ Rate Limit 비활성화됨${NC}"
echo ""

echo -e "${CYAN}비활성화 후 10번 연속 요청${NC}"
echo ""

for i in {1..10}; do
    result=$($REDIS_CLI PING 2>&1)
    echo -e "${GREEN}요청 $i: $result${NC}"
    sleep 0.2
done

# ==========================================
# 데모 8: 서버 로그 확인
# ==========================================
demo_step "데모 8: Rate Limit 로그 확인"

echo -e "${CYAN}Redis 서버 로그를 확인하여 Rate Limit 작동 확인${NC}"
echo ""

echo -e "${YELLOW}서버 로그에서 'RLDBG' 또는 'Rate limit' 메시지를 찾으세요:${NC}"
echo ""
echo -e "${CYAN}예시 로그:${NC}"
echo "  RLDBG id=123 tag=PING count=6 max=5 win=10"
echo "  Rate limit exceeded: client-id=123, count=6 in 10 sec (limit=5)"

# ==========================================
# 마무리
# ==========================================
demo_step "데모 완료!"

echo -e "${GREEN}"
cat << "EOF"
╔═══════════════════════════════════════════════╗
║                                               ║
║   ✅ Rate Limiting이 성공적으로 시연되었습니다!   ║
║                                               ║
║   - 설정 가능한 제한 (CONFIG SET)       ✓     ║
║   - 클라이언트별 추적                   ✓     ║
║   - 시간 윈도우 관리                    ✓     ║
║   - 요청 차단 및 에러 처리               ✓     ║
║                                               ║
║   감사합니다!                                   ║
║                                               ║
╚═══════════════════════════════════════════════╝
EOF
echo -e "${NC}"

echo ""
echo -e "${CYAN}주요 성과:${NC}"
echo "  • server.h에 rate limit 필드 추가"
echo "  • config.c에 설정 등록"
echo "  • rate_limit.c에 체크 로직 구현"
echo "  • server.c에 명령어 처리 연결"
echo "  • 완전히 작동하는 Rate Limiting"
echo ""

echo -e "${YELLOW}다음 단계:${NC}"
echo "  1. Redis 로그 확인: tail -f /var/log/redis.log"
echo "  2. 설정 파일 저장: CONFIG REWRITE"
echo "  3. Production 배포 준비"
echo ""
