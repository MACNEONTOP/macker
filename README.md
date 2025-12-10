# MacneOnTop 프로젝트

# AUL 기반 macOS 이상행위 탐지

--- 

# [사용 설명서 보기](https://github.com/MACNEONTOP/macker/blob/main/macker%20%E1%84%89%E1%85%A1%E1%84%8B%E1%85%AD%E1%86%BC%E1%84%89%E1%85%A5%E1%86%AF%E1%84%86%E1%85%A7%E1%86%BC%E1%84%89%E1%85%A5.pdf)

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
  
## 2. 주요 탐지 룰
Threshold, Sequence 기반 탐지 룰 모음입니다. 각 룰은 특정 공격 패턴이나 이상 행위가 임계값을 초과할 때 알림을 생성합니다.

---

### 1. Discovery Storm (내부 정찰 급증)

**Rule ID**: `threshold-001-discovery-storm-v2`

**설명**: 짧은 시간 내에 여러 Discovery 유형의 보안 알림이 발생했습니다. 공격자가 시스템 정보를 수집하고 있을 가능성이 있습니다.

**심각도**: Medium (Risk Score: 50)

**탐지 조건**:
- 쿼리: `kibana.alert.rule.tags: "attack.discovery"`
- Threshold: 동일 호스트에서 10회 이상 발생
- 시간 범위: 6분 이내
- 검사 주기: 5분

**관련 태그**: 
- attack.discovery
- Meta_Alert

---

### 2. Critical Impact Sequence (치명적 영향 연속 활동)

**Rule ID**: `threshold-002-impact-activity-v2`

**설명**: 시스템 복구 비활성화 및 서비스 중단과 같은 Impact 유형 알림이 연속적으로 발생했습니다. 랜섬웨어의 징후일 수 있습니다.

**심각도**: Critical (Risk Score: 90)

**탐지 조건**:
- 쿼리: `kibana.alert.rule.tags: "attack.impact"`
- Threshold: 동일 호스트에서 2회 이상 발생
- 시간 범위: 11분 이내
- 검사 주기: 10분

**관련 태그**: 
- attack.impact
- Ransomware_Detection

---

### 3. Credential Access Spike (자격증명 탈취 시도 급증)

**Rule ID**: `threshold-003-credential-spike-v2`

**설명**: 짧은 시간 내에 Credential Access 관련 알림이 급증했습니다.

**심각도**: High (Risk Score: 70)

**탐지 조건**:
- 쿼리: `kibana.alert.rule.tags: "attack.credential_access"`
- Threshold: 동일 호스트에서 5회 이상 발생
- 시간 범위: 6분 이내
- 검사 주기: 5분

**관련 태그**: 
- attack.credential_access
- Meta_Alert

---

### 4. High Risk Alert Cluster (고위험 알림 클러스터)

**Rule ID**: `threshold-004-high-risk-cluster-v2`

**설명**: 짧은 시간 내에 CRITICAL 또는 HIGH Risk Level을 가진 여러 알림이 발생했습니다.

**심각도**: High (Risk Score: 85)

**탐지 조건**:
- 쿼리: `threat_score_1_risk_level: ("CRITICAL" OR "HIGH")`
- Threshold: 동일 호스트에서 3회 이상 발생
- 시간 범위: 11분 이내
- 검사 주기: 10분

**관련 태그**: 
- Risk_Based_Detection

---

### 5. SSH Brute Force Attack Detection (SSH 브루트 포스 공격 탐지)

**Rule ID**: `threshold-005-ssh-brute-force`

**설명**: SSH 브루트 포스 공격으로 인해 단일 호스트(대상 서버)에서 5분 이내에 Credential Access 알림이 5회 이상 발생했습니다. 즉각적인 대응이 필요합니다.

**심각도**: High (Risk Score: 75)

**탐지 조건**:
- 쿼리: `kibana.alert.rule.tags: "attack.credential_access" AND kibana.alert.rule.name: "*Brute Force via ssh*"`
- Threshold: 동일 호스트에서 5회 이상 발생
- 시간 범위: 6분 이내
- 검사 주기: 5분

**관련 태그**: 
- attack.credential_access
- Brute_Force_SSH

---

### 6. Lateral Movement Indicators (측면 이동 지표)

**Rule ID**: `threshold-lateral-movement-001`

**설명**: 10분 이내에 동일 호스트에서 Lateral Movement 또는 Remote Services 관련 알림이 3회 이상 발생했습니다. APT 공격의 측면 이동 단계입니다.

**심각도**: High (Risk Score: 80)

**탐지 조건**:
- 쿼리: `kibana.alert.rule.tags: "attack.lateral_movement"`
- Threshold: 동일 호스트에서 3회 이상 발생
- 시간 범위: 10분 이내
- 검사 주기: 5분

**관련 태그**: 
- attack.lateral_movement

---

### 7. Privilege Escalation Attempts (권한 상승 시도)

**Rule ID**: `threshold-privilege-escalation-001`

**설명**: 15분 이내에 동일 호스트에서 Privilege Escalation 관련 알림이 3회 이상 발생했습니다. 반복적인 권한 상승 시도가 탐지되었습니다.

**심각도**: High (Risk Score: 70)

**탐지 조건**:
- 쿼리: `kibana.alert.rule.tags: "attack.privilege_escalation"`
- Threshold: 동일 호스트에서 3회 이상 발생
- 시간 범위: 16분 이내
- 검사 주기: 5분

**관련 태그**: 
- attack.privilege_escalation

---

### 8. Persistence Establishment Attempts (지속성 확립 시도)

**Rule ID**: `threshold-persistence-attempts-001`

**설명**: 20분 이내에 동일 호스트에서 Persistence 관련 알림이 3회 이상 발생했습니다. 시스템 지속성 확립 시도가 탐지되었습니다.

**심각도**: High (Risk Score: 75)

**탐지 조건**:
- 쿼리: `kibana.alert.rule.tags: "attack.persistence"`
- Threshold: 동일 호스트에서 3회 이상 발생
- 시간 범위: 10분 이내
- 검사 주기: 5분

**관련 태그**: 
- attack.persistence

---

### 9. Rapid Encryption Activity Detected (고속 암호화 활동)

**Rule ID**: `ransomware-entropy-threshold-001`

**설명**: 높은 엔트로피(>= 7.5)와 낮은 카이제곱 점수(<= 300)로 특징지어지는 잠재적 랜섬웨어 활동을 탐지합니다. 이 룰은 압축 파일을 제외하며, 5분 창 내에 단일 호스트에서 5회 이상의 이벤트가 발생할 때 트리거됩니다.

**심각도**: Critical (Risk Score: 99)

**탐지 조건**:
- 쿼리: `fsevents.file.entropy >= 7.5 and fsevents.ransomware.chi_square <= 300`
- Threshold: 동일 호스트에서 5회 이상 발생
- 시간 범위: 6분 이내
- 검사 주기: 5분

**MITRE ATT&CK**:
- Technique: Data Encrypted for Impact (T1486)

**관련 태그**: 
- Ransomware
- Entropy
- Chi-Square
- macOS
- Impact
- T1486

---


### 10. Malware Kill Chain Pattern

**Rule ID**: `eql-malware-killchain-high-risk-001`

**설명**: 30분 이내에 동일 호스트에서 Initial Access → Execution → Persistence 단계 알림이 순차적으로 발생하고, 각 알림의 risk_score가 high 이상일 때 탐지됩니다.

**심각도**: Critical (Risk Score: 95)

**탐지 조건**:
```
sequence by host.name with maxspan=30m
  [any where kibana.alert.rule.tags : "attack.initial_access" and kibana.alert.risk_score >= 70]
  [any where kibana.alert.rule.tags : "attack.execution" and kibana.alert.risk_score >= 70]
  [any where kibana.alert.rule.tags : "attack.persistence" and kibana.alert.risk_score >= 70]
```

**관련 태그**: 
- Malware_Pattern
- Kill_Chain
- High_Risk
- attack.initial_access
- attack.execution
- attack.persistence

---

### 11. Infostealer Kill Chain Pattern

**Rule ID**: `eql-infostealer-killchain-critical-002`

**설명**: 20분 이내에 동일 호스트에서 Discovery → Collection → Exfiltration 단계 알림이 순차적으로 발생하고, 각 알림의 risk_score가 medium 이상일 때 탐지됩니다.

**심각도**: Critical (Risk Score: 98)

**탐지 조건**:
```
sequence by host.name with maxspan=20m
  [any where kibana.alert.rule.tags : "attack.discovery"]
  [any where kibana.alert.rule.tags : "attack.collection"]
  [any where kibana.alert.rule.tags : "attack.exfiltration"]
```

**관련 태그**: 
- Infostealer_Pattern
- Kill_Chain
- attack.discovery
- attack.collection
- attack.exfiltration
- macOS

---

## 위험도 레벨 정의

| Risk Score | Severity | 설명 |
|-----------|----------|------|
| 76-100 | Critical | 즉각적인 대응 필요, 심각한 보안 위협 |
| 56-75 | High | 높은 우선순위로 조사 필요 |
| 41-55 | Medium | 모니터링 및 검토 필요 |
| 1-40 | Low | 참고용, 정기 검토 |


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
