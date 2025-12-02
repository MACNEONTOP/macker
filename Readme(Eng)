# macOS AUL-based anomaly detection

This project was conducted as part of the education/research assignment by the **MakneOnTop Team** in the Digital Forensic Track of the Best of the Best (BoB) program supported by the Ministry of Science and ICT.

This repository is an example for research and study purposes, provided under the [MIT License](LICENSE), and the user bears all responsibility for its use.
(GitHub: <hhttps://github.com/deviantony/docker-elk)

> ⚠️ If you install Docker using `brew install docker`, conflicts with Docker Desktop or errors may occur depending on the environment. Please use the official Docker Desktop installer if possible.

## Overview

This project detects user anomalies based on macOS AUL (Apple Unified Logs).

---

## Minimum System Requirements

- RAM: 8GB or higher
- CPU: M1 or later
- OS: macOS (Sonoma or later)
- Docker: Docker Desktop for Mac (Latest version)
- Docker Compose: v2.0 or later

## ELK Connection Information

- Kibana: <http://localhost:5601>
- Default Account
  - ID: `elastic`
  - PW: `changeme`

---

## How to Run

    git clone https://github.com/MACNEONTOP/macker.git

    cd macker
    chmod +x run.sh
    ./run.sh

---

## ⚠️ Cautions && Notes

### 1. How to Add Rules / Data Views / Dashboards

Files exported as NDJSON from Kibana should only be added to the paths below.

- **Detection Rules**
  - Path: `setup/rule/`
  - Content: `*.ndjson` files exported from **Security → Detection rules**

- **Data Views**
  - Path: `setup/dataview/`
  - Content: `*.ndjson` files exported after selecting **Data view** in **Stack Management → Saved Objects**

- **Dashboards**
  - Path: `setup/dashboard/`
  - Content: `*.ndjson` files exported after selecting **Dashboard** in **Stack Management → Saved Objects**

> You can name the files freely, but **the extension must be `.ndjson`** to be included in the automatic import.

---

### 2. Automatic Import Mechanism

- When running `docker compose up -d`, the `kibana-importer` container runs once.
- At this time, files in the following folders are automatically imported:
  - `/dataview/*.ndjson` → Data Views
  - `/dashboard/*.ndjson` → Dashboards
  - `/rules/*.ndjson` → Detection Rules (Detection Engine)
- Objects with the same ID are **automatically overwritten** using the `_import?overwrite=true` option.

---

### 3. Environment Variables / Passwords

- Passwords and settings defined in the `.env` file are assumed to be used for **local development/research purposes only**.
- When using this repository in a public repo, please be careful not to commit passwords or sensitive values from the actual operating environment.

### 4. Manual Operation
- If run.sh does not work, you must use the following commands.
```bash
docker-compose up setup
docker-compose up -d
chown root: * filebeat.yml
./filebeat -c filebeat.yml
