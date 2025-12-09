#!/usr/bin/env bash
set -euo pipefail

die() {
  echo "[ERROR] $*" >&2
  exit 1
}

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

FB_VERSION="9.2.1"
FB_TARBALL="filebeat-${FB_VERSION}-darwin-aarch64.tar.gz"
FB_URL="https://artifacts.elastic.co/downloads/beats/filebeat/${FB_TARBALL}"
FB_DIR="${ROOT_DIR}/filebeat-${FB_VERSION}-darwin-aarch64"

echo "[*] Step 0. 사전 체크 및 환경 설정"

# 0-1. root 금지
if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
  die "이 스크립트는 root/sudo 로 실행하면 안 됩니다. 일반 사용자 계정에서 실행해 주세요."
fi

# 0-2. 필수 명령어 확인
command -v curl >/dev/null 2>&1    || die "curl 명령을 찾을 수 없습니다."
command -v docker >/dev/null 2>&1  || die "docker 명령을 찾을 수 없습니다."
command -v python3 >/dev/null 2>&1 || die "python3 명령을 찾을 수 없습니다."

# 0-3. docker compose 확인
if command -v docker compose >/dev/null 2>&1; then
  DC=(docker compose)
elif command -v docker-compose >/dev/null 2>&1; then
  DC=(docker-compose)
else
  die "docker compose 또는 docker-compose 명령을 찾을 수 없습니다."
fi

# 0-4. 설정 파일 소스 확인
FB_CONF_SRC="${ROOT_DIR}/setup/filebeat/filebeat.yml"
[[ -f "${FB_CONF_SRC}" ]] || die "설정 파일이 없습니다: ${FB_CONF_SRC}"

# 소스 디렉터리 변수 정의
SRC_DIR="$(dirname "${FB_CONF_SRC}")"
PY_SCRIPT_SRC="${SRC_DIR}/fsevents_logger.py"
[[ -f "${PY_SCRIPT_SRC}" ]] || die "Python 스크립트가 없습니다: ${PY_SCRIPT_SRC}"

# =========================================================
# [추가됨] 0-5. Python 라이브러리 설치 (watchdog)
# =========================================================
echo "    - Python watchdog 라이브러리 설치 확인..."

# > /dev/null 2>&1 : 확인 과정의 불필요한 출력 메시지를 숨김
if python3 -m pip show watchdog > /dev/null 2>&1; then
    echo "    - watchdog 라이브러리가 이미 설치되어 있습니다. (Skip)"
else
    echo "    - watchdog 미설치됨. 설치를 시작합니다..."
    python3 -m pip install watchdog || die "watchdog 라이브러리 설치 실패"
fi

echo "[*] Step 1. Filebeat tarball 다운로드"
cd "${ROOT_DIR}"
if [[ -f "${FB_TARBALL}" ]]; then
  echo "    - ${FB_TARBALL} 이미 존재, 재다운로드 생략"
else
  curl -L -o "${FB_TARBALL}" "${FB_URL}" || die "Filebeat tarball 다운로드 실패"
fi

echo "[*] Step 2. Filebeat 압축 해제"
if [[ -d "${FB_DIR}" ]]; then
  echo "    - ${FB_DIR} 이미 존재, 재압축 해제 생략"
else
  tar xzf "${FB_TARBALL}" || die "Filebeat tar.gz 압축 해제 실패"
fi
[[ -d "${FB_DIR}" ]] || die "Filebeat 디렉터리를 찾을 수 없습니다: ${FB_DIR}"


echo "[*] Step 3. Filebeat 설정 파일 및 스크립트 교체"
cd "${FB_DIR}"

# 기존 파일 정리
[[ -f "filebeat.yml" ]] && rm -f filebeat.yml
[[ -f "fsevents_logger.py" ]] && rm -f fsevents_logger.py

# 파일 복사
cp "${FB_CONF_SRC}" "${FB_DIR}/filebeat.yml" || die "filebeat.yml 복사 실패"
cp "${PY_SCRIPT_SRC}" "${FB_DIR}/fsevents_logger.py" || die "fsevents_logger.py 복사 실패"

# 권한 설정
chmod 700 "${FB_DIR}/filebeat"
chmod 600 "${FB_DIR}/filebeat.yml"
chmod +x "${FB_DIR}/fsevents_logger.py"


echo "[*] Step 4. ELK setup 실행"
set +e
"${DC[@]}" --project-directory "${ROOT_DIR}" --profile=setup up setup
SETUP_EXIT=$?
set -e
if [[ ${SETUP_EXIT} -ne 0 ]]; then
  die "docker compose --profile=setup up setup 단계 오류. docker 로그 확인 필요"
fi

echo "[*] Step 5. ELK 스택 기동"
"${DC[@]}" --project-directory "${ROOT_DIR}" up -d || die "ELK 스택 기동 실패"

echo "[*] Step 6. Filebeat 설정/출력 테스트"
cd "${FB_DIR}"
./filebeat test config  -c filebeat.yml || die "filebeat test config 실패"
./filebeat test output -c filebeat.yml || die "filebeat test output 실패"


echo "[*] Step 7. fsevents_logger 및 Filebeat 실행"
# ---------------------------------------------------------
# 실행 및 종료 로직
# ---------------------------------------------------------

# 종료 시그널 처리 함수
cleanup() {
    echo ""
    echo "[!] Stopping processes..."
    if [[ -n "${PY_PID-}" ]]; then
        echo "    - Killing Python Logger (PID: $PY_PID)"
        kill "$PY_PID" 2>/dev/null || true
    fi
    if [[ -n "${FB_PID-}" ]]; then
        echo "    - Killing Filebeat (PID: $FB_PID)"
        kill "$FB_PID" 2>/dev/null || true
    fi
    exit 0
}

# Trap 설정
trap cleanup SIGINT SIGTERM EXIT

echo "    - 1/2 Starting fsevents_logger.py..."
python3 fsevents_logger.py &
PY_PID=$!

sleep 1

echo "    - 2/2 Starting filebeat..."
./filebeat -c filebeat.yml &
FB_PID=$!

echo "[OK] 모든 서비스가 실행 중입니다. (Python PID: $PY_PID, Filebeat PID: $FB_PID)"
echo "     종료하려면 Ctrl+C를 누르세요."

wait