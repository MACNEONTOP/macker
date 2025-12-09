#!/usr/bin/env bash

set -eu
set -o pipefail

source "${BASH_SOURCE[0]%/*}"/lib.sh


# --------------------------------------------------------
# Users declarations

declare -A users_passwords
users_passwords=(
	[logstash_internal]="${LOGSTASH_INTERNAL_PASSWORD:-}"
	[kibana_system]="${KIBANA_SYSTEM_PASSWORD:-}"
	[metricbeat_internal]="${METRICBEAT_INTERNAL_PASSWORD:-}"
	[filebeat_internal]="${FILEBEAT_INTERNAL_PASSWORD:-}"
	[heartbeat_internal]="${HEARTBEAT_INTERNAL_PASSWORD:-}"
	[monitoring_internal]="${MONITORING_INTERNAL_PASSWORD:-}"
	[beats_system]="${BEATS_SYSTEM_PASSWORD:-}"
)

declare -A users_roles
users_roles=(
	[logstash_internal]='logstash_writer'
	[metricbeat_internal]='metricbeat_writer'
	[filebeat_internal]='filebeat_writer'
	[heartbeat_internal]='heartbeat_writer'
	[monitoring_internal]='remote_monitoring_collector'
)

# --------------------------------------------------------
# Roles declarations

declare -A roles_files
roles_files=(
	[logstash_writer]='logstash_writer.json'
	[metricbeat_writer]='metricbeat_writer.json'
	[filebeat_writer]='filebeat_writer.json'
	[heartbeat_writer]='heartbeat_writer.json'
)

# --------------------------------------------------------


log 'Waiting for availability of Elasticsearch. This can take several minutes.'

declare -i exit_code=0
wait_for_elasticsearch || exit_code=$?

if ((exit_code)); then
	case $exit_code in
		6)
			suberr 'Could not resolve host. Is Elasticsearch running?'
			;;
		7)
			suberr 'Failed to connect to host. Is Elasticsearch healthy?'
			;;
		28)
			suberr 'Timeout connecting to host. Is Elasticsearch healthy?'
			;;
		*)
			suberr "Connection to Elasticsearch failed. Exit code: ${exit_code}"
			;;
	esac

	exit $exit_code
fi

sublog 'Elasticsearch is running'

log 'Waiting for initialization of built-in users'

wait_for_builtin_users || exit_code=$?

if ((exit_code)); then
	suberr 'Timed out waiting for condition'
	exit $exit_code
fi

sublog 'Built-in users were initialized'

for role in "${!roles_files[@]}"; do
	log "Role '$role'"

	declare body_file
	body_file="${BASH_SOURCE[0]%/*}/roles/${roles_files[$role]:-}"
	if [[ ! -f "${body_file:-}" ]]; then
		sublog "No role body found at '${body_file}', skipping"
		continue
	fi

	sublog 'Creating/updating'
	ensure_role "$role" "$(<"${body_file}")"
done

for user in "${!users_passwords[@]}"; do
	log "User '$user'"
	if [[ -z "${users_passwords[$user]:-}" ]]; then
		sublog 'No password defined, skipping'
		continue
	fi

	declare -i user_exists=0
	user_exists="$(check_user_exists "$user")"

	if ((user_exists)); then
		sublog 'User exists, setting password'
		set_user_password "$user" "${users_passwords[$user]}"
	else
		if [[ -z "${users_roles[$user]:-}" ]]; then
			suberr '  No role defined, skipping creation'
			continue
		fi

		sublog 'User does not exist, creating'
		create_user "$user" "${users_passwords[$user]}" "${users_roles[$user]}"
	fi
done


echo "[setup] Waiting for Kibana to become available..."

# -------------------------------------------------------------
# [수정] 인덱스 생성 대기 및 매핑 적용 (성공할 때까지 반복)
# -------------------------------------------------------------
echo "[Setup] Starting Runtime Fields Mapping process..."

# 1. 인덱스가 생길 때까지 무한 루프 (Kibana가 룰을 로드할 시간을 줌)
while true; do
  # 인덱스 존재 여부 확인 (HEAD 요청)
  status_code=$(curl -s -o /dev/null -w "%{http_code}" -I -u "elastic:${ELASTIC_PASSWORD}" "http://elasticsearch:9200/.internal.alerts-security.alerts-default-*")

  if [ "$status_code" -eq 200 ]; then
    echo "[Setup] Target index found! Applying mapping..."
    
    # 2. 매핑 적용
    if [ -f "/mapping.json" ]; then
      response=$(curl -s -o /dev/null -w "%{http_code}" -X PUT "http://elasticsearch:9200/.internal.alerts-security.alerts-default-*/_mapping" \
        -u "elastic:${ELASTIC_PASSWORD}" \
        -H "Content-Type: application/json" \
        -d @/mapping.json)
      
      if [ "$response" -eq 200 ]; then
        echo "[Setup] SUCCESS: Mapping applied!"
        break # 성공 시 루프 탈출
      else
        echo "[Setup] Mapping failed (HTTP $response). Retrying in 10s..."
      fi
    else
      echo "[Setup] Error: /mapping.json missing."
      exit 1
    fi
  else
    echo "[Setup] Index not created yet. Waiting 10s..."
  fi
  
  sleep 10
done

# -------------------------------------------------------------
# -------------------------------------------------------------------------------------------------------------------



# KIBANA_URL="${KIBANA_URL:-http://kibana:5601}"

# MAX_TRIES=60   # 60 * 5초 = 최대 5분 대기
# i=0
# KIBANA_STATUS_JSON=""

# while [ $i -lt $MAX_TRIES ]; do
#   # Kibana status 호출 (실패해도 스크립트 안 죽게 || true)
#   KIBANA_STATUS_JSON=$(curl -s -u "elastic:${ELASTIC_PASSWORD}" "${KIBANA_URL}/api/status" || true)

#   # 응답 안에 green/available 비슷한 상태가 있는지 확인
#   if printf '%s' "$KIBANA_STATUS_JSON" | grep -q '"state":"green"\|"level":"available"'; then
#     echo "[setup] Kibana status looks OK."
#     break
#   fi

#   i=$((i+1))
#   echo "[setup] Kibana not ready yet (${i}/${MAX_TRIES})..."
#   sleep 5
# done

# --------------------------------------------------------
# [추가] Kibana 설정 및 룰 임포트
# --------------------------------------------------------

# echo "[setup] Kibana /api/status last response:"
# echo "$KIBANA_STATUS_JSON"

# echo "[setup] Initializing detection engine index (if needed)..."
# curl -s -u "elastic:${ELASTIC_PASSWORD}" \
#   -H "Content-Type: application/json" \
#   -H "kbn-xsrf: true" \
#   -X POST "${KIBANA_URL}/api/detection_engine/index" || true

# echo "[setup] Importing detection rules from /rules/*.ndjson ..."
# for f in /rules/*.ndjson; do
#   [ -e "$f" ] || continue
#   echo "  -> importing $(basename "$f")"
#   curl -s -u "elastic:${ELASTIC_PASSWORD}" \
#     -H "kbn-xsrf: true" \
#     -F "file=@${f}" \
#     "${KIBANA_URL}/api/detection_engine/rules/_import?overwrite=true&overwrite_exceptions=true" || true
# done

# echo "[setup] Rules import finished."

# --------------------------------------------------------
# [추가] Kibana 설정 및 룰 임포트
# --------------------------------------------------------

# log 'Waiting for Kibana to be ready...'

# # Kibana가 켜질 때까지 최대 30번(약 2분 30초) 대기
# declare -i kibana_ready=0
# for _ in {1..30}; do
#     # API 상태 체크 (200 OK가 나오면 성공)
#     response=$(curl -s -o /dev/null -w "%{http_code}" -u "elastic:${ELASTIC_PASSWORD}" "http://kibana:5601/api/status" || true)
    
#     if [[ "$response" == "200" ]]; then
#         kibana_ready=1
#         break
#     fi
#     sleep 5
# done

# if ((kibana_ready)); then
#     sublog 'Kibana is running'

#     # 1. Security Rules (.ndjson) 임포트
#     log 'Importing Security Rules from /rules'
    
#     # /rules 폴더에 있는 모든 ndjson 파일을 찾음
#     # nullglob: 파일이 없으면 루프를 돌지 않게 함
#     shopt -s nullglob
#     for rule_file in /rules/*.ndjson; do
#         sublog "Importing: $rule_file"
        
#         # 룰 임포트 API 호출
#         curl -X POST "http://kibana:5601/api/detection_engine/rules/_import?overwrite=true" \
#             -s -o /dev/null \
#             -H "kbn-xsrf: true" \
#             -H "Content-Type: multipart/form-data" \
#             -u "elastic:${ELASTIC_PASSWORD}" \
#             -F "file=@$rule_file"
#     done
#     shopt -u nullglob

# 	echo "[Kibana] Data View 생성 시도: my-mac-*"

# 	# 2. API를 날려서 Data View 생성 (이미 있으면 409 에러 나고 무시됨)
# 	curl -X POST "http://kibana:5601/api/data_views/data_view" \
# 	-H "kbn-xsrf: true" \
# 	-H "Content-Type: application/json" \
# 	-u elastic:${ELASTIC_PASSWORD} \
# 	-d '{
# 			"data_view": {
# 			"title": "my-mac-*",
# 			"name": "My Mac Logs",
# 			"timeFieldName": "@timestamp"
# 			}
# 		}'

# 	echo -e "\n[Kibana] Data View 설정 완료!"

# else
#     suberr 'Timed out waiting for Kibana. Skipping rule import.'
# fi