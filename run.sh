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

echo "[*] Step 0. 사전 체크"

# 0-1. root 금지 (docker + filebeat 둘 다 일반 사용자 기준)
if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
  die "이 스크립트는 root/sudo 로 실행하면 안 됩니다. 일반 사용자 계정에서 실행해 주세요."
fi

# 0-2. 필수 명령어
command -v curl >/dev/null 2>&1    || die "curl 명령을 찾을 수 없습니다."
command -v docker >/dev/null 2>&1  || die "docker 명령을 찾을 수 없습니다."

# 0-3. docker compose
if command -v docker compose >/dev/null 2>&1; then
  DC=(docker compose)
elif command -v docker-compose >/dev/null 2>&1; then
  DC=(docker-compose)
else
  die "docker compose 또는 docker-compose 명령을 찾을 수 없습니다."
fi

# 0-4. filebeat 설정 존재
FB_CONF_SRC="${ROOT_DIR}/setup/filebeat/filebeat.yml"
[[ -f "${FB_CONF_SRC}" ]] || die "설정 파일이 없습니다: ${FB_CONF_SRC}"

echo "[*] Step 1. Filebeat tarball 다운로드 (없을 때만)"
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

echo "[*] Step 3. Filebeat 설정 파일 교체"
cd "${FB_DIR}"
[[ -f "filebeat.yml" ]] && rm -f filebeat.yml
cp "${FB_CONF_SRC}" "${FB_DIR}/filebeat.yml" || die "filebeat.yml 복사 실패"

# 권한은 현재 사용자 기준으로만 정리
chmod 700 "${FB_DIR}/filebeat"
chmod 600 "${FB_DIR}/filebeat.yml"

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

echo "[*] Step 7. Filebeat 실행"
./filebeat -c filebeat.yml