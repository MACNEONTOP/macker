# MacneOnTop 프로젝트

# AUL 기반 macOS 이상행위 탐지

---

## 📌 프로젝트 개요
macOS의 AUL(Apple Unified Logging System)과 FSEvents 를 활용하여  
랜섬웨어 / InfoStealer 등 이상행위를 탐지하는 모니터링 시스템입니다.

# 🔗 배포 주소
**ELK & Agent:** [[링크]](https://github.com/MACNEONTOP/macker)
 
**가이드라인:** [[링크]](https://github.com/MACNEONTOP/macOS_Guideline)

---

# 📚 목차
- [프로젝트 소개](#프로젝트-소개)
- [탐지 룰 작성](#탐지-룰-작성)
- [이상 행위 탐지 방안](#이상-행위-탐지-방안)
- [도구 구성](#도구-구성)
- [Test Mal](#Test-Mal)

---

# 🚀 프로젝트 소개

## 1. 배경 및 목적

2025년 macOS 사용자 수 (OS X + macOS)는 13.1%로 적지않은 사용자를 보이고 있다. [[출처]](https://gs.statcounter.com/os-market-share/desktop/worldwide/#yearly-2020-2025)

 
macOS는 다른 운영체제에 비해 상대적으로 안전하다는 평가가 있지만, 최근 macOS를 대상으로 랜섬웨어, 스피어피싱, 공급망 공격, 스파이웨어 등 다양한 위협의 표적이 되고 있다. [[출처1]](https://www.infosecurity-magazine.com/news/proofpoint-frigidstealer-new-mac/)[[출처2]](https://www.infosecurity-magazine.com/news/macos-infostealer-amos-backdoor/)[[출처3]](https://www.tomshardware.com/tech-industry/cyber-security/the-first-ai-powered-ransomware-has-been-discovered-promptlock-uses-local-ai-to-foil-heuristic-detection-and-evade-api-tracking)
 
2016년세계 개발자 컨퍼런스 ( WWDC, Apple WorldWide Developers Conference)에서 Apple은 기존에 사용하던 syslog와 Apple이 독자적으로 개발한 ASL(Apple System Log) 을 통합한 AUL (Apple Unified Logging System) 통합 로깅 체제을 소개하였다.

팀 '막내온탑'은 이러한 AUL을 활용하여 macOS 환경에서 랜섬웨어를 포함한 다양한 이상행위를 탐지할 수 있는 모니터링 도구를 개발하였다.


## 2. 산출물

### ✔ 1) 이상행위 모니터링 도구 - **macker**
macOS의 AUL 로그를 기반으로 행위를 분석하고, 이상 징후(InfoStealer, Ransomware 등)를 탐지하는 에이전트/ELK 기반 시스템.

### ✔ 2) 논문
1. macOS AUL 기반 행위 탐지 시스템  
2. macOS 버전별 AUL 차이점 분석

### ✔ 3) 가이드라인
- macOS 정보유출 분석 가이드라인

---

# 🛡️ 탐지 룰 작성
## 1. Mitre att&ck 매핑
macOS 플랫폼에서 발생 가능한 MITRE ATT&CK 기술(Techniques)에 대해 직접 행위를 재현한 뒤, AUL에 남는 로그를 수집하여 각 기술을 단일 로그에 매핑하였다.

또한, Sigma Rule 규칙(Sigma Rule Format)을 기반으로 탐지룰을 작성하여,
보안 전문가들이 쉽게 읽고, 수정하고, 공유할 수 있도록 규칙 표준화를 진행하였다.



---

# 🔍 이상 행위 탐지 방안
## 1. 스코어링 기반 탐지
본 프로젝트는 아래 두 논문을 기반으로 공격기술 단위 스코어링(Technique Scoring)을 적용한다.

- 조성영, 박용우, 이건호, 최창희, 신찬호 and 이경식. (2022). MITRE ATT&CK을 이용한 APT 공격 스코어링 방법 연구. 정보보호학회논문지, 32(4), 673-689.
- Manocha, H., Srivastava, A., Verma, C., Gupta, R., & Bansal, B. (2021). *Security Assessment Rating Framework for Enterprises using MITRE ATT&CK® Matrix*. arXiv preprint arXiv:2108.06559.
  
## 2. 악성 코드 탐지 원리
### 공통
> AUL 로그와 Sigma 기반 탐지룰을 연계하여, macOS에서 발생하는 공격 흐름을 공격 단계(Initial Access → Execution → Persistence) 단위로 분석한다.
특히 동일 호스트에서 공격 단계가 단시간에 순차적으로 발생하는 경우, 침해로 이어질 가능성이 높아 에 이를 탐지 요소로 사용한다.

### 랜섬웨어 탐지 원리
> 랜섬웨어는 파일을 대량으로 암호화하는 과정에서 비정상적으로 높은 엔트로피(entropy) 를 보이며, 암호화 후 데이터 분포가 랜덤화되기 때문에 카이제곱(chi-square) 점수는 낮아지는 특징이 나타난다.
> 
> 본 프로젝트에서는 이러한 파일 변경 특성을 기반으로 FSEvents(File System Events)과 File Entropy를 활용해 실시간 탐지를 수행한다.

### InfoStealer
> InfoStealer는 'Discovery → Collection → Exfiltration'같은 공격 패턴을 가지고 있어 이를 바탕으로 탐지를 진행한다.

### 기타
> 일정 시간 내 과도한 Discovery 탐지, 일정 시간 내 과도한 Credential Access 탐지 등 비정상 패턴 탐지를 진핸한다.


---

# 🔧 시스템 구성 요소
## 1. Agent
- macOS 환경에서 실시간 로그를 수집하여 중앙 서버로 전송하는 구성 요소이다.
### filebeat
> - macOS에서 생성되는 AUL(Apple Unified Log)을 실시간 수집
> - 프로세스 단위로 필터링된 로그를 Elasticsearch로 전송하여 즉각적인 분석이 가능하도록 함
### fsevents_logger
> - macOS 파일 시스템 이벤트(FSEvents)를 실시간 수집
> - 파일 생성, 수정, 삭제, 권한 변경 등 랜섬웨어 탐지의 데이터 제공

---

## 2. ELK
### Elasticsearch
> - Agent가 전송한 AUL 및 FSEvents 로그를 저장
> - Sigma Rule 기반으로 변환된 Detection Rule을 실행하여 이상행위 탐지 결과(alert)를 생성

### Logstash
> - Agent에서 수신한 로그를 Elasticsearch가 이해할 수 있는 형태로 파싱함
> - Agent와 ELK 스택을 연결하는 중간 처리 역할을 수행함

### Kibana
> - 수집된 로그와 탐지 결과를 시각화
> - 대시보드 제공

---

## 3. Test Mal
만들어진 도구 테스트를 위하여 컨트롤 가능한 테스트용 malware 두 종을 제공한다.
- InfoStealer
- Ransomeware

이를 활용하여 도구를 테스트할 수 있다.
