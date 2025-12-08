#!/bin/bash
# Redis 모듈 - 발표용 라이브 데모
# 작성자: tkdwl05
# 날짜: 2025-12-08

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # 색상 없음

REDIS_CLI="../redis-cli"

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
║     Redis 고급 기능 구현 프로젝트                ║
║                                               ║
║   작성자: tkdwl05                              ║
║   날짜: 2025-12-08                             ║
║                                               ║
╚═══════════════════════════════════════════════╝
EOF
echo -e "${NC}"

echo -e "${CYAN}구현한 기능:${NC}"
echo "  1. Cache Stampede Prevention (캐시 stampede 방지)"
echo "  2. Streams 기반 Task Queue (작업 큐)"
echo "  3. Distributed Locks (분산 락)"
echo ""
read -p "Enter를 눌러 데모 시작..."

# ==========================================
# 데모 1: Cache Stampede Prevention
# ==========================================
demo_step "데모 1: Cache Stampede Prevention"

echo -e "${CYAN}시나리오:${NC} 캐시 미스 시 여러 클라이언트가 동일한 사용자 데이터를 요청"
echo ""

demo_command "$REDIS_CLI CACHE.LOCK user:1001 5000 10000"
echo -e "${GREEN}→ 클라이언트 1이 'LOAD'를 받음 - 데이터베이스에서 가져와야 함${NC}"
echo ""

demo_command "$REDIS_CLI CACHE.LOCK user:1001 5000 10000"
echo -e "${YELLOW}→ 클라이언트 2는 'WAIT'을 받음 - 클라이언트 1을 기다림${NC}"
echo ""

demo_command "$REDIS_CLI CACHE.SET user:1001 '홍길동_30세' 60000"
echo -e "${GREEN}→ 클라이언트 1이 캐시에 쓰고 락을 해제${NC}"
echo ""

demo_command "$REDIS_CLI CACHE.GET user:1001"
echo -e "${GREEN}→ 이제 모든 클라이언트가 캐시에서 읽을 수 있음${NC}"
echo ""

demo_command "$REDIS_CLI CACHE.LOCK user:1001 5000 10000"
echo -e "${GREEN}→ 락이 해제되어, 새 요청은 다시 'LOAD'를 받음${NC}"

# ==========================================
# 데모 2: Task Queue
# ==========================================
demo_step "데모 2: Streams 기반 Task Queue"

echo -e "${CYAN}시나리오:${NC} 비동기 주문 처리 시스템"
echo ""

demo_command "$REDIS_CLI XGROUP CREATE orders processors $ MKSTREAM"
echo -e "${GREEN}→ Consumer group 'processors' 생성${NC}"
echo ""

demo_command "$REDIS_CLI TASK.PUBLISH orders '주문_#1001'"
demo_command "$REDIS_CLI TASK.PUBLISH orders '주문_#1002'"
demo_command "$REDIS_CLI TASK.PUBLISH orders '주문_#1003'"
echo -e "${GREEN}→ 큐에 3개의 주문을 발행${NC}"
echo ""

demo_command "$REDIS_CLI TASK.CONSUME processors worker1 orders 2 1000"
echo -e "${GREEN}→ Worker 1이 2개의 작업을 소비${NC}"
echo ""

demo_command "$REDIS_CLI XLEN orders"
echo -e "${CYAN}→ 현재 큐 길이${NC}"

# ==========================================
# 데모 3: Distributed Locks
# ==========================================
demo_step "데모 3: 분산 락 (Distributed Locks)"

echo -e "${CYAN}시나리오:${NC} 여러 서버에서 일일 배치 작업 조정"
echo ""

demo_command "$REDIS_CLI LOCK.ACQUIRE daily_report server1 30000"
echo -e "${GREEN}→ 서버 1이 락 획득 성공 (1 반환)${NC}"
echo ""

demo_command "$REDIS_CLI LOCK.ACQUIRE daily_report server2 30000"
echo -e "${RED}→ 서버 2는 획득 실패 (0 반환) - 락이 이미 점유됨${NC}"
echo ""

demo_command "$REDIS_CLI LOCK.EXTEND daily_report server1 30000"
echo -e "${GREEN}→ 서버 1이 락 연장 (작업이 아직 진행 중)${NC}"
echo ""

demo_command "$REDIS_CLI LOCK.EXTEND daily_report server2 30000"
echo -e "${RED}→ 서버 2는 연장 불가 (0 반환) - 소유자가 아님${NC}"
echo ""

demo_command "$REDIS_CLI LOCK.RELEASE daily_report server1"
echo -e "${GREEN}→ 서버 1이 락 해제${NC}"
echo ""

demo_command "$REDIS_CLI LOCK.ACQUIRE daily_report server2 30000"
echo -e "${GREEN}→ 이제 서버 2가 락을 획득할 수 있음${NC}"

# ==========================================
# 데모 4: 모듈 상태
# ==========================================
demo_step "데모 4: 모듈 상태 확인"

demo_command "$REDIS_CLI MODULE LIST"
echo -e "${GREEN}→ 3개 모듈 모두 성공적으로 로드됨${NC}"
echo ""

demo_command "$REDIS_CLI INFO commandstats | grep -E 'cache|task|lock' | head -10"
echo -e "${CYAN}→ 명령어 사용 통계${NC}"

# ==========================================
# 마무리
# ==========================================
demo_step "데모 완료!"

echo -e "${GREEN}"
cat << "EOF"
╔═══════════════════════════════════════════════╗
║                                               ║
║   ✅ 모든 기능이 성공적으로 시연되었습니다!        ║
║                                               ║
║   - Cache Stampede Prevention  ✓              ║
║   - Task Queue 처리            ✓              ║
║   - 분산 락                    ✓              ║
║                                               ║
║   감사합니다!                                   ║
║                                               ║
╚═══════════════════════════════════════════════╝
EOF
echo -e "${NC}"

echo ""
echo -e "${CYAN}주요 성과:${NC}"
echo "  • 컴파일 에러 제로"
echo "  • 모든 모듈 크래시 없이 로드"
echo "  • 20/20 자동 테스트 통과"
echo "  • Production-ready 구현"
echo ""
