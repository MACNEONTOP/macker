#!/usr/bin/env bash
set -euo pipefail

# 간단 에러 처리 함수
die() {
  echo "[ERROR] $*" >&2
  exit 1
}

# 스크립트 기준 루트 디렉터리
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "[*] Step 0. 사전 체크"

# 0-1. root / sudo 방지 (brew 가 root로 실행되면 안 됨)
if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
  die "이 스크립트는 root/sudo 로 실행할 수 없습니다. 일반 사용자 계정에서 실행해 주세요."
fi

# 0-2. docker 존재 여부
if ! command -v docker >/dev/null 2>&1; then
  die "docker 명령을 찾을 수 없습니다. Docker Desktop 이 설치되어 있는지 확인해 주세요."
fi

# 0-3. docker compose / docker-compose 존재 여부
if command -v docker compose >/dev/null 2>&1; then
  DC=(docker compose)
elif command -v docker-compose >/dev/null 2>&1; then
  DC=(docker-compose)
else
  die "docker compose 또는 docker-compose 명령을 찾을 수 없습니다."
fi

# 0-4. filebeat 설정 파일 존재 여부
if [[ ! -f "${ROOT_DIR}/setup/filebeat/filebeat.yml" ]]; then
  die "설정 파일이 없습니다: ${ROOT_DIR}/setup/filebeat/filebeat.yml"
fi

echo "[*] Step 1. filebeat 디렉터리 생성"
mkdir -p "${ROOT_DIR}/filebeat"

echo "[*] Step 2. Homebrew 및 filebeat 설치 확인"
if ! command -v brew >/dev/null 2>&1; then
  die "Homebrew 가 설치되어 있지 않습니다. 먼저 brew 를 설치해 주세요."
fi

if ! brew list --versions filebeat >/dev/null 2>&1; then
  echo "[*] filebeat 이 설치되어 있지 않아 설치를 진행합니다."
  if brew tap | grep -q '^elastic/tap$'; then
    brew install elastic/tap/filebeat || die "filebeat 설치에 실패했습니다."
  else
    brew install filebeat || die "filebeat 설치에 실패했습니다."
  fi
else
  echo "[*] filebeat 이 이미 설치되어 있습니다."
fi

echo "[*] Step 3. filebeat 바이너리 복사 (현재 디렉터리/filebeat 에 고정)"
FB_PREFIX="$(brew --prefix filebeat 2>/dev/null || true)"
if [[ -z "${FB_PREFIX}" || ! -x "${FB_PREFIX}/bin/filebeat" ]]; then
  die "filebeat 바이너리를 찾을 수 없습니다: ${FB_PREFIX}/bin/filebeat"
fi

cp "${FB_PREFIX}/bin/filebeat" "${ROOT_DIR}/filebeat/filebeat" \
  || die "filebeat 바이너리 복사에 실패했습니다."
chmod +x "${ROOT_DIR}/filebeat/filebeat"

echo "[*] Step 4. filebeat 설정 파일 덮어쓰기"
# ./setup/filebeat/filebeat.yml -> ./filebeat/filebeat.yml
cp "${ROOT_DIR}/setup/filebeat/filebeat.yml" "${ROOT_DIR}/filebeat/filebeat.yml" \
  || die "filebeat 설정 파일 복사에 실패했습니다."

echo "[*] Step 5. ELK setup 실행 (내부 유저/비밀번호 초기화, 필요 시)"
set +e
"${DC[@]}" --project-directory "${ROOT_DIR}" --profile=setup up setup
SETUP_EXIT=$?
set -e

if [[ ${SETUP_EXIT} -ne 0 ]]; then
  die "docker compose --profile=setup up setup 단계에서 오류가 발생했습니다. docker 로그를 확인해 주세요."
fi

echo "[*] Step 6. ELK 스택 기동"
"${DC[@]}" --project-directory "${ROOT_DIR}" up -d \
  || die "ELK 스택 기동에 실패했습니다."

echo "[*] Step 7. filebeat 출력 테스트 (Logstash 연결 확인)"
(
  cd "${ROOT_DIR}/filebeat"
  ./filebeat test output -c filebeat.yml \
    || die "filebeat → Logstash 출력 테스트에 실패했습니다."
)

echo "[*] Step 8. filebeat 실행"
cd "${ROOT_DIR}/filebeat"
./filebeat -c filebeat.yml