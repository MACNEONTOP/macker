#!/usr/bin/env bash
set -euo pipefail

# 간단 에러 처리 함수
die() {
  echo "[ERROR] $*" >&2
  exit 1
}

# 스크립트 기준 루트 디렉터리
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Filebeat 버전/경로 정의
FB_VERSION="9.2.1"
FB_TARBALL="filebeat-${FB_VERSION}-darwin-aarch64.tar.gz"
FB_URL="https://artifacts.elastic.co/downloads/beats/filebeat/${FB_TARBALL}"
FB_DIR="${ROOT_DIR}/filebeat-${FB_VERSION}-darwin-aarch64"

echo "[*] Step 0. 사전 체크"

# 0-1. root / sudo 확인 (Filebeat config를 root 소유로 맞추기 위함)
if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
  die "이 스크립트는 sudo/root 권한으로 실행해야 합니다. (예: sudo ./run.sh)"
fi

# 0-2. 필수 명령어 확인
command -v curl >/dev/null 2>&1 || die "curl 명령을 찾을 수 없습니다."
command -v docker >/dev/null 2>&1 || die "docker 명령을 찾을 수 없습니다."

# 0-3. docker compose / docker-compose 결정
if command -v docker compose >/dev/null 2>&1; then
  DC=(docker compose)
elif command -v docker-compose >/dev/null 2>&1; then
  DC=(docker-compose)
else
  die "docker compose 또는 docker-compose 명령을 찾을 수 없습니다."
fi

# 0-4. filebeat 설정 파일 존재 여부
FB_CONF_SRC="${ROOT_DIR}/setup/filebeat/filebeat.yml"
if [[ ! -f "${FB_CONF_SRC}" ]]; then
  die "설정 파일이 없습니다: ${FB_CONF_SRC}"
fi

echo "[*] Step 1. Filebeat tarball 다운로드 (없을 때만)"
cd "${ROOT_DIR}"

if [[ -f "${FB_TARBALL}" ]]; then
  echo "    - ${FB_TARBALL} 이미 존재, 재다운로드 생략"
else
  echo "    - ${FB_TARBALL} 다운로드 중..."
  curl -L -o "${FB_TARBALL}" "${FB_URL}" || die "Filebeat tarball 다운로드에 실패했습니다."
fi

echo "[*] Step 2. Filebeat 압축 해제"
if [[ -d "${FB_DIR}" ]]; then
  echo "    - ${FB_DIR} 디렉터리가 이미 존재합니다. 재압축 해제 생략"
else
  tar xzf "${FB_TARBALL}" || die "Filebeat tar.gz 압축 해제에 실패했습니다."
fi

if [[ ! -d "${FB_DIR}" ]]; then
  die "Filebeat 디렉터리를 찾을 수 없습니다: ${FB_DIR}"
fi

echo "[*] Step 3. Filebeat 설정 파일 교체"
cd "${FB_DIR}"

# 기본 filebeat.yml 제거 (있을 경우)
if [[ -f "filebeat.yml" ]]; then
  rm -f filebeat.yml || die "기존 filebeat.yml 삭제에 실패했습니다."
fi

# setup/filebeat/filebeat.yml 복사
cp "${FB_CONF_SRC}" "${FB_DIR}/filebeat.yml" || die "filebeat 설정 파일 복사에 실패했습니다."

# Filebeat 실행/설정 파일 권한 조정 (macOS 기준 root:wheel)
echo "[*] Step 4. Filebeat 권한 설정"
chown root:wheel "${FB_DIR}/filebeat" "${FB_DIR}/filebeat.yml" || die "chown root:wheel 실패"
chmod 700 "${FB_DIR}/filebeat"
chmod 600 "${FB_DIR}/filebeat.yml"

echo "[*] Step 5. ELK setup 실행 (내부 유저/비밀번호 초기화)"
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

echo "[*] Step 7. Filebeat 설정/출력 테스트"
cd "${FB_DIR}"

./filebeat test config -c filebeat.yml \
  || die "filebeat 설정(test config)에 문제가 있습니다."

./filebeat test output -c filebeat.yml \
  || die "filebeat 출력(test output: Logstash/ES) 테스트에 실패했습니다."

echo "[*] Step 8. Filebeat 실행"
echo "[*] localhost:5601 접속"
echo "[*] filebeate Control + C 종료"
./filebeat -c filebeat.yml