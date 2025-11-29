# macOS AUL ELK Server

본 프로젝트는 과학기술정보통신부가 지원하는 차세대보안리더양성과정(Best of the Best) 디지털포렌식 트랙에서 **막내온탑 팀**이 수행한 교육·연구 과제의 일환으로 진행되었습니다.

이 리포지토리는 연구 및 학습 목적의 예제로, [MIT License](LICENSE) 하에 제공되며 사용에 따른 모든 책임은 사용자에게 있습니다.  
(GitHub: <hhttps://github.com/deviantony/docker-elk)

> ⚠️ `brew install docker` 방식으로 Docker를 설치할 경우, 환경에 따라 Docker Desktop과 충돌하거나 오류가 발생할 수 있습니다.  

---

## ELK 접속 정보

- Kibana: <http://localhost:5601>
- 기본 계정  
  - ID: `elastic`  
  - PW: `changeme`

---

## 실행 방법

    git clone https://github.com/MACNEONTOP/macker.git

    cd macker
    chmod +x run.sh
    ./run.sh

---

## ⚠️ 주의사항

### 1. 룰 / 데이터 뷰 / 대시보드 추가 방법

Kibana에서 NDJSON으로 내보낸 파일은 아래 경로에만 추가해 주시면 됩니다.

- **탐지 룰 (Detection Rules)**  
  - 경로: `setup/rule/`  
  - 내용: Security → Detection rules 에서 **Export** 한 `*.ndjson` 파일

- **데이터 뷰 (Data Views)**  
  - 경로: `setup/dataview/`  
  - 내용: Stack Management → Saved Objects 에서 **Data view** 선택 후 **Export** 한 `*.ndjson` 파일

- **대시보드 (Dashboards)**  
  - 경로: `setup/dashboard/`  
  - 내용: Stack Management → Saved Objects 에서 **Dashboard** 선택 후 **Export** 한 `*.ndjson` 파일

> 파일 이름은 자유롭게 지정해도 되지만, **확장자는 반드시 `.ndjson`** 이어야 자동 import 대상에 포함됩니다.

---

### 2. 자동 Import 동작 방식

- `docker compose up -d` 실행 시, `kibana-importer` 컨테이너가 한 번 실행됩니다.
- 이때 다음 폴더의 파일이 자동으로 import 됩니다.
  - `/dataview/*.ndjson` → 데이터 뷰
  - `/dashboard/*.ndjson` → 대시보드
  - `/rules/*.ndjson` → 탐지 룰 (Detection Engine)
- 동일 ID를 가진 객체는 `_import?overwrite=true` 옵션으로 **자동 덮어쓰기** 됩니다.

---

### 3. 환경 변수 / 비밀번호 관련

- `.env` 파일에 정의된 비밀번호와 설정 값은 **로컬 개발·연구 목적**으로만 사용하는 것을 전제로 합니다.
- 이 리포지토리를 공개 저장소에서 사용할 때는, 실제 운영 환경의 비밀번호나 민감한 값이 커밋되지 않도록 주의해 주십시오.