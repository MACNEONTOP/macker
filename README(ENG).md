# MacneOnTop Project

# macOS Anomaly Detection Based on AUL

---

# [View User Manual](https://github.com/MACNEONTOP/macker/blob/main/Macker%20%EC%82%AC%EC%9A%A9%EC%84%A4%EB%AA%85%EC%84%9C.pdf)

---

## 📌 Project Overview
This is a monitoring system that utilizes macOS AUL (Apple Unified Logging System) and FSEvents to detect anomalous behaviors such as Ransomware and InfoStealer.

# 🔗 Deployment Links
**ELK & Agent:** [[Link]](https://github.com/MACNEONTOP/macker)

**Guidelines:** [[Link]](https://github.com/MACNEONTOP/macOS_Guideline)

---

# 📚 Table of Contents
- [Project Introduction](#project-introduction)
- [Writing Detection Rules](#writing-detection-rules)
- [Anomaly Detection Methods](#anomaly-detection-methods)
- [Tool Configuration](#tool-configuration)

---

# 🚀 Project Introduction

## 1. Background and Purpose

In 2025, the number of macOS users (OS X + macOS) accounts for 13.1% of the market, showing a significant user base. [[Source]](https://gs.statcounter.com/os-market-share/desktop/worldwide/#yearly-2020-2025)

While macOS is evaluated as relatively safer compared to other operating systems, it has recently become a target for various threats such as Ransomware, Spear Phishing, Supply Chain Attacks, and Spyware. [[Source 1]](https://www.infosecurity-magazine.com/news/proofpoint-frigidstealer-new-mac/)[[Source 2]](https://www.infosecurity-magazine.com/news/macos-infostealer-amos-backdoor/)[[Source 3]](https://www.tomshardware.com/tech-industry/cyber-security/the-first-ai-powered-ransomware-has-been-discovered-promptlock-uses-local-ai-to-foil-heuristic-detection-and-evade-api-tracking)

At the 2016 WWDC (Apple Worldwide Developers Conference), Apple introduced the AUL (Apple Unified Logging System), which integrates the existing `syslog` and the Apple-developed ASL (Apple System Log).

Team 'MacneOnTop' has developed a monitoring tool capable of detecting various anomalous behaviors, including ransomware, in the macOS environment by utilizing this AUL.

## 2. Outputs

### ✔ 1) Anomaly Monitoring Tool - **macker**
An Agent/ELK-based system that analyzes behaviors based on macOS AUL logs to detect anomalies (InfoStealer, Ransomware, etc.).

### ✔ 2) Papers
1. macOS AUL-based Behavior Detection System
2. Analysis of AUL Differences by macOS Version

### ✔ 3) Guidelines
- macOS Information Leakage Analysis Guideline

---

# 🛡️ Writing Detection Rules
## 1. MITRE ATT&CK Mapping
We reproduced behaviors for MITRE ATT&CK Techniques applicable to the macOS platform, collected the resulting AUL logs, and mapped each technique to a single log.

Additionally, we standardized the rules based on the **Sigma Rule Format** so that security experts can easily read, modify, and share them.

---

# 🔍 Anomaly Detection Methods
## 1. Scoring-Based Detection
This project applies **Technique Scoring** based on the following two papers:

- Cho Seong-young, Park Yong-woo, Lee Geon-ho, Choi Chang-hee, Shin Chan-ho, and Lee Kyung-sik. (2022). *A Study on APT Attack Scoring Method Using MITRE ATT&CK*. Journal of the Korea Institute of Information Security & Cryptology, 32(4), 673-689.
- Manocha, H., Srivastava, A., Verma, C., Gupta, R., & Bansal, B. (2021). *Security Assessment Rating Framework for Enterprises using MITRE ATT&CK® Matrix*. arXiv preprint arXiv:2108.06559.

## 2. Key Detection Rules
A collection of Threshold and Sequence-based detection rules. Each rule generates an alert when a specific attack pattern or anomalous behavior exceeds a defined threshold.

---

### 1. Discovery Storm (Surge in Internal Reconnaissance)

**Rule ID**: `threshold-001-discovery-storm-v2`

**Description**: Multiple Discovery-type security alerts occurred within a short period. An attacker may be collecting system information.

**Severity**: Medium (Risk Score: 50)

**Detection Conditions**:
- Query: `kibana.alert.rule.tags: "attack.discovery"`
- Threshold: Occurs 10 or more times on the same host
- Time Range: Within 6 minutes
- Check Interval: 5 minutes

**Related Tags**:
- attack.discovery
- Meta_Alert

---

### 2. Critical Impact Sequence (Continuous Impact Activity)

**Rule ID**: `threshold-002-impact-activity-v2`

**Description**: Continuous Impact-type alerts, such as disabling system recovery or service interruption, have occurred. This may be a sign of ransomware.

**Severity**: Critical (Risk Score: 90)

**Detection Conditions**:
- Query: `kibana.alert.rule.tags: "attack.impact"`
- Threshold: Occurs 2 or more times on the same host
- Time Range: Within 11 minutes
- Check Interval: 10 minutes

**Related Tags**:
- attack.impact
- Ransomware_Detection

---

### 3. Credential Access Spike (Surge in Credential Theft Attempts)

**Rule ID**: `threshold-003-credential-spike-v2`

**Description**: Alerts related to Credential Access surged within a short period.

**Severity**: High (Risk Score: 70)

**Detection Conditions**:
- Query: `kibana.alert.rule.tags: "attack.credential_access"`
- Threshold: Occurs 5 or more times on the same host
- Time Range: Within 6 minutes
- Check Interval: 5 minutes

**Related Tags**:
- attack.credential_access
- Meta_Alert

---

### 4. High Risk Alert Cluster

**Rule ID**: `threshold-004-high-risk-cluster-v2`

**Description**: Multiple alerts with a CRITICAL or HIGH Risk Level occurred within a short period.

**Severity**: High (Risk Score: 85)

**Detection Conditions**:
- Query: `threat_score_1_risk_level: ("CRITICAL" OR "HIGH")`
- Threshold: Occurs 3 or more times on the same host
- Time Range: Within 11 minutes
- Check Interval: 10 minutes

**Related Tags**:
- Risk_Based_Detection

---

### 5. SSH Brute Force Attack Detection

**Rule ID**: `threshold-005-ssh-brute-force`

**Description**: Credential Access alerts caused by SSH Brute Force attacks occurred 5 or more times on a single host (target server) within 5 minutes. Immediate response is required.

**Severity**: High (Risk Score: 75)

**Detection Conditions**:
- Query: `kibana.alert.rule.tags: "attack.credential_access" AND kibana.alert.rule.name: "*Brute Force via ssh*"`
- Threshold: Occurs 5 or more times on the same host
- Time Range: Within 6 minutes
- Check Interval: 5 minutes

**Related Tags**:
- attack.credential_access
- Brute_Force_SSH

---

### 6. Lateral Movement Indicators

**Rule ID**: `threshold-lateral-movement-001`

**Description**: Alerts related to Lateral Movement or Remote Services occurred 3 or more times on the same host within 10 minutes. This indicates the lateral movement phase of an APT attack.

**Severity**: High (Risk Score: 80)

**Detection Conditions**:
- Query: `kibana.alert.rule.tags: "attack.lateral_movement"`
- Threshold: Occurs 3 or more times on the same host
- Time Range: Within 10 minutes
- Check Interval: 5 minutes

**Related Tags**:
- attack.lateral_movement

---

### 7. Privilege Escalation Attempts

**Rule ID**: `threshold-privilege-escalation-001`

**Description**: Alerts related to Privilege Escalation occurred 3 or more times on the same host within 15 minutes. Repeated privilege escalation attempts were detected.

**Severity**: High (Risk Score: 70)

**Detection Conditions**:
- Query: `kibana.alert.rule.tags: "attack.privilege_escalation"`
- Threshold: Occurs 3 or more times on the same host
- Time Range: Within 16 minutes
- Check Interval: 5 minutes

**Related Tags**:
- attack.privilege_escalation

---

### 8. Persistence Establishment Attempts

**Rule ID**: `threshold-persistence-attempts-001`

**Description**: Alerts related to Persistence occurred 3 or more times on the same host within 20 minutes. Attempts to establish system persistence were detected.

**Severity**: High (Risk Score: 75)

**Detection Conditions**:
- Query: `kibana.alert.rule.tags: "attack.persistence"`
- Threshold: Occurs 3 or more times on the same host
- Time Range: Within 10 minutes
- Check Interval: 5 minutes

**Related Tags**:
- attack.persistence

---

### 9. Rapid Encryption Activity Detected

**Rule ID**: `ransomware-entropy-threshold-001`

**Description**: Detects potential ransomware activity characterized by high entropy (>= 7.5) and low chi-square scores (<= 300). This rule excludes compressed files and triggers when 5 or more events occur on a single host within a 5-minute window.

**Severity**: Critical (Risk Score: 99)

**Detection Conditions**:
- Query: `fsevents.file.entropy >= 7.5 and fsevents.ransomware.chi_square <= 300`
- Threshold: Occurs 5 or more times on the same host
- Time Range: Within 6 minutes
- Check Interval: 5 minutes

**MITRE ATT&CK**:
- Technique: Data Encrypted for Impact (T1486)

**Related Tags**:
- Ransomware
- Entropy
- Chi-Square
- macOS
- Impact
- T1486

---

### 10. Malware Kill Chain Pattern

**Rule ID**: `eql-malware-killchain-high-risk-001`

**Description**: Detected when alerts for Initial Access → Execution → Persistence stages occur sequentially on the same host within 30 minutes, and the risk_score for each alert is High or above.

**Severity**: Critical (Risk Score: 95)

**Detection Conditions**:
