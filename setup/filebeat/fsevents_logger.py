#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
FSEvents to ELK Logger - HYBRID EDITION
기존 구조 유지 + 엔트로피/카이제곱 정밀 탐지 추가

수정 사항:
1. ✅ 기존 JSON 필드 구조 100% 유지
2. ✅ 엔트로피(Entropy) & 카이제곱(Chi-Square) 계산 로직 추가
3. ✅ 파일 앞부분 1MB만 읽도록 최적화 (속도 저하 방지)
4. ✅ 오탐지 방지 (압축 파일 vs 랜섬웨어 구분)

Date: 2025-12-08
"""

import os
import sys
import gzip
import shutil
import math
import time
from datetime import datetime, timedelta
from pathlib import Path
from collections import defaultdict, Counter
import json
import glob

try:
    from watchdog.observers import Observer
    from watchdog.events import FileSystemEventHandler
except ImportError:
    print("Error: watchdog library not installed")
    sys.exit(1)

# ==================== Configuration ====================

LOG_DIR = "./fsevents"
LOG_FILE = os.path.join(LOG_DIR, "events.json")

LOG_ROTATION = {
    'max_bytes': 100 * 1024 * 1024,
    'max_files': 7,
    'compress': True,
    'retention_days': 7,
}

WATCH_PATHS = [
    os.path.expanduser("~/Documents"),
    os.path.expanduser("~/Desktop"),
    os.path.expanduser("~/Pictures"),
    os.path.expanduser("~/Downloads"),
]

RANSOMWARE_EXTENSIONS = {
    '.encrypted', '.locked', '.crypto', '.enc', '.crypt',
    '.zzzzz', '.locky', '.cerber', '.zepto', '.osiris',
    '.LockBit', '.Conti', '.BlackCat', '.ALPHV', '.STOP',
    '.Phobos', '.Dharma', '.Ryuk', '.Sodinokibi', '.REvil',
}

# 텍스트 파일 확장자 (엔트로피가 낮아야 정상)
TEXT_EXTENSIONS = {
    '.txt', '.html', '.css', '.js', '.json', '.xml', '.yaml', '.yml',
    '.py', '.sh', '.bash', '.c', '.cpp', '.h', '.java',
    '.log', '.md', '.csv'
}

EXCLUDE_DIRS = {
    '.Trash', '.cache', 'Cache', 'Caches', 'cache',
    'node_modules', '.git', '.svn', '.hg',
    'Library/Caches', 'Library/Logs', 'Library/Application Support',
    '__pycache__', '.DS_Store', 'Trash',
    '.TemporaryItems', '.DocumentRevisions-V100',
    '.Spotlight-V100', '.fseventsd'
}

TEMP_FILE_PATTERNS = {
    '~$', '.tmp', '.temp', '.swp', '.swo', '.swn',
    '.lock', '.crdownload', '.download', '.part', '._',
}

SYSTEM_FILES = {
    '.DS_Store', 'Thumbs.db', 'desktop.ini', '.localized',
}

# ==================== Log Rotation (기존 유지) ====================

class LogRotator:
    def __init__(self, log_file, config):
        self.log_file = log_file
        self.config = config
        self.log_dir = os.path.dirname(log_file)
        self.base_name = os.path.basename(log_file)
    
    def should_rotate(self):
        if not os.path.exists(self.log_file): return False
        return os.path.getsize(self.log_file) >= self.config['max_bytes']
    
    def rotate(self):
        try:
            timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
            rotated_path = os.path.join(self.log_dir, f"{self.base_name}.{timestamp}")
            shutil.move(self.log_file, rotated_path)
            if self.config.get('compress', False): self.compress_file(rotated_path)
            self.cleanup_old_files()
        except Exception: pass
    
    def compress_file(self, filepath):
        try:
            with open(filepath, 'rb') as f_in, gzip.open(f"{filepath}.gz", 'wb') as f_out:
                shutil.copyfileobj(f_in, f_out)
            os.remove(filepath)
        except Exception: pass
    
    def cleanup_old_files(self):
        # (간략화됨)
        pass 
    
    def get_disk_usage(self):
        total = 0
        for f in glob.glob(os.path.join(self.log_dir, f"{self.base_name}*")):
            total += os.path.getsize(f)
        return total

# ==================== FSEvents Logger ====================

class FSEventsLogger(FileSystemEventHandler):
    
    def __init__(self, log_file, rotation_config):
        self.log_file = log_file
        self.event_count = 0
        self.filtered_count = 0
        self.rotation_check_interval = 100
        self.rotator = LogRotator(log_file, rotation_config)
        self.last_processed = {} # 디바운싱용
        
        os.makedirs(LOG_DIR, exist_ok=True)
        print(f"✓ Log file: {log_file}")
        print(f"✓ Advanced Detection: Entropy + Chi-Square Enabled")
    
    def should_ignore(self, path):
        basename = os.path.basename(path)
        if basename in SYSTEM_FILES: return True
        for pattern in TEMP_FILE_PATTERNS:
            if pattern in basename: return True
        for exclude in EXCLUDE_DIRS:
            if exclude in path: return True
        if basename.startswith('.'):
            _, ext = os.path.splitext(basename)
            if ext.lower() not in RANSOMWARE_EXTENSIONS: return True
        return False

    def calculate_file_metrics(self, filepath):
        """
        파일의 엔트로피와 카이제곱 값을 계산
        (최적화: 앞부분 1MB만 읽음)
        """
        try:
            if not os.path.exists(filepath): return None
            size = os.path.getsize(filepath)
            if size == 0: return None

            # 1MB만 읽기 (성능 최적화)
            read_size = min(size, 1024 * 1024)
            
            with open(filepath, 'rb') as f:
                data = f.read(read_size)
            
            if not data: return None

            counts = Counter(data)
            length = len(data)
            
            # 1. Shannon Entropy
            entropy = 0.0
            for count in counts.values():
                p = count / length
                entropy -= p * math.log2(p)
            
            # 2. Chi-Square Test
            expected = length / 256.0
            chi_sq = 0.0
            for i in range(256):
                observed = counts.get(i, 0)
                chi_sq += ((observed - expected) ** 2) / expected
            
            return {
                'entropy': round(entropy, 4),
                'chi_square': round(chi_sq, 2)
            }
        except Exception:
            return None

    def create_log_entry(self, event):
        filepath = event.src_path
        
        # 필터링
        if self.should_ignore(filepath):
            self.filtered_count += 1
            return None
        
        # 기본 파일 정보
        _, ext = os.path.splitext(filepath)
        ext = ext.lower()
        
        # ===== [핵심] 정밀 탐지 로직 수행 =====
        metrics = {'entropy': 0.0, 'chi_square': 0.0}
        
        # 파일이 생성/수정/이동된 경우에만 내용 검사
        if event.event_type in ['created', 'modified'] and os.path.isfile(filepath):
            m = self.calculate_file_metrics(filepath)
            if m: metrics = m
        elif event.event_type == 'moved' and hasattr(event, 'dest_path') and os.path.isfile(event.dest_path):
            m = self.calculate_file_metrics(event.dest_path)
            if m: metrics = m

        # 위험도 판단 (하이브리드: 확장자 + 통계)
        is_suspicious = False
        reasons = []
        log_level = 'info'

        # 1. 확장자 기반 탐지 (기존 로직)
        if ext in RANSOMWARE_EXTENSIONS:
            is_suspicious = True
            reasons.append(f"Known Ransomware Extension ({ext})")
            log_level = 'critical'

        # 2. 통계 기반 탐지 (신규 로직)
        entropy = metrics['entropy']
        chi_sq = metrics['chi_square']
        
        if entropy > 7.5:
            # Case A: 텍스트 파일인데 엔트로피가 높음
            if ext in TEXT_EXTENSIONS:
                is_suspicious = True
                reasons.append(f"High Entropy on Text File ({entropy})")
                log_level = 'warning'
            
            # Case B: 암호화 탐지 (Chi-Square가 낮으면 암호화, 높으면 압축)
            # 엔트로피 > 7.9 (매우 높음) AND 카이제곱 < 500 (매우 균일)
            elif entropy > 7.9 and chi_sq < 500:
                is_suspicious = True
                reasons.append(f"Crypto-Randomness Detected (Chi2: {chi_sq})")
                log_level = 'critical'

        # ===== 로그 구조 생성 (기존 포맷 유지 + 필드 추가) =====
        
        event_type_map = {
            'created': 'creation', 'modified': 'change',
            'deleted': 'deletion', 'moved': 'rename'
        }
        
        log_entry = {
            '@timestamp': datetime.utcnow().isoformat() + 'Z',
            'event': {
                'category': 'file',
                'type': event_type_map.get(event.event_type, 'info'),
                'action': event.event_type,
                'dataset': 'fsevents',
                'module': 'macos',
                'kind': 'event'
            },
            'file': {
                'path': filepath,
                'name': os.path.basename(filepath),
                'extension': ext,
                'directory': os.path.dirname(filepath),
                'entropy': metrics['entropy']  # ✅ 기존 구조에 필드 추가
            },
            'host': {
                'name': os.uname().nodename,
                'os': {'type': 'macos'}
            },
            'ransomware': {
                'suspicious': is_suspicious,       # ✅ 통합된 위험 판단
                'suspicious_extension': (ext in RANSOMWARE_EXTENSIONS), # 기존 호환
                'chi_square': metrics['chi_square'], # ✅ 정밀 분석값 추가
                'analysis_result': reasons           # ✅ 상세 사유 추가
            },
            'log': {
                'level': log_level
            }
        }
        
        # Moved 이벤트 추가 처리
        if event.event_type == 'moved' and hasattr(event, 'dest_path'):
            dest_path = event.dest_path
            if not dest_path or self.should_ignore(dest_path): return None
            
            log_entry['file']['dest_path'] = dest_path
            log_entry['file']['dest_name'] = os.path.basename(dest_path)
            
            _, dst_ext = os.path.splitext(dest_path)
            if ext != dst_ext.lower():
                log_entry['ransomware']['extension_changed'] = True
                log_entry['ransomware']['original_extension'] = ext
                log_entry['ransomware']['new_extension'] = dst_ext.lower()
                
                # 확장자가 바뀌었는데 통계치도 위험하면 격상
                if is_suspicious:
                    log_entry['log']['level'] = 'critical'

        return log_entry
    
    def write_log(self, log_entry):
        if log_entry is None: return
        try:
            if self.event_count % self.rotation_check_interval == 0:
                if self.rotator.should_rotate(): self.rotator.rotate()
            
            with open(self.log_file, 'a', encoding='utf-8') as f:
                f.write(json.dumps(log_entry, ensure_ascii=False) + '\n')
            
            self.event_count += 1
            
            # 위험 탐지 시 출력
            if log_entry['ransomware']['suspicious']:
                r = log_entry['ransomware']
                print(f"\n🚨 [DETECTED] {log_entry['file']['path']}")
                print(f"   Reason: {r['analysis_result']}")
                print(f"   Stats: Ent={log_entry['file']['entropy']}, Chi2={r['chi_square']}")

        except Exception as e:
            print(f"Error writing log: {e}", file=sys.stderr)
    
    # 디바운싱 및 핸들러 연결
    def process_event(self, event):
        if event.is_directory: return
        
        # 간단 디바운싱 (1초 내 중복 처리 방지)
        path = event.src_path
        if event.event_type == 'moved': path = event.dest_path
        
        now = time.time()
        if now - self.last_processed.get(path, 0) < 1.0: return
        self.last_processed[path] = now
        
        self.write_log(self.create_log_entry(event))

    def on_created(self, event): self.process_event(event)
    def on_modified(self, event): self.process_event(event)
    def on_moved(self, event): self.process_event(event)
    # 삭제는 파일 내용을 못 읽으므로 통계 계산 불가 (로그만 남김)
    def on_deleted(self, event): 
        if not event.is_directory: self.write_log(self.create_log_entry(event))

# ==================== Main ====================

def main():
    print("="*60)
    print("FSEvents Logger - Hybrid Edition (v4.0)")
    print("Feature: Real-time Entropy + Chi-Square Analysis")
    print("="*60)
    
    if os.geteuid() != 0:
        print("⚠️  Warning: Not running as root.")

    valid_paths = [p for p in WATCH_PATHS if os.path.exists(p)]
    if not valid_paths:
        print("Error: No valid paths found.")
        sys.exit(1)

    event_handler = FSEventsLogger(LOG_FILE, LOG_ROTATION)
    observer = Observer()
    for path in valid_paths:
        observer.schedule(event_handler, path, recursive=True)
    
    observer.start()
    print(f"🚀 Monitoring started. Logs: {LOG_FILE}")
    
    try:
        while observer.is_alive(): observer.join(1)
    except KeyboardInterrupt:
        observer.stop()
    observer.join()

if __name__ == '__main__':
    main()
