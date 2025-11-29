#!/usr/bin/env bash
set -euo pipefail

# 스크립트 기준 루트 디렉터리
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "[*] Step 1. filebeat 디렉터리 생성"
mkdir -p "${ROOT_DIR}/filebeat"

echo "[*] Step 2. Homebrew 및 filebeat 설치 확인"
if ! command -v brew >/dev/null 2>&1; then
  echo "Homebrew 가 설치되어 있지 않습니다. 먼저 brew 를 설치해야 합니다." >&2
  exit 1
fi

if ! brew list --versions filebeat >/dev/null 2>&1; then
  # elastic tap 이 있으면 우선 사용, 없으면 기본 filebeat 시도
  if brew tap | grep -q '^elastic/tap$'; then
    brew install elastic/tap/filebeat
  else
    brew install filebeat
  fi
fi

echo "[*] Step 3. filebeat 바이너리 복사"
FB_PREFIX="$(brew --prefix filebeat)"
cp "${FB_PREFIX}/bin/filebeat" "${ROOT_DIR}/filebeat/filebeat"

echo "[*] Step 4. filebeat 설정 파일 덮어쓰기"
# ./setup/filebeat/filebeat.yml -> ./filebeat/filebeat.yml
cp "${ROOT_DIR}/setup/filebeat/filebeat.yml" "${ROOT_DIR}/filebeat/filebeat.yml"

echo "[*] Step 5. docker-compose 명령 결정"
if command -v docker compose >/dev/null 2>&1; then
  DC="docker compose"
else
  DC="docker-compose"
fi

echo "[*] Step 6. ELK setup 실행 (내부 유저/비밀번호 초기화)"
$DC --project-directory "${ROOT_DIR}" --profile=setup up setup

echo "[*] Step 7. ELK 스택 기동"
$DC --project-directory "${ROOT_DIR}" up -d

echo "[*] Step 8. filebeat 실행"
cd "${ROOT_DIR}/filebeat"
./filebeat -c filebeat.yml