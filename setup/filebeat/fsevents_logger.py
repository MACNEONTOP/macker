#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
FSEvents to ELK Logger - FINAL VERSION with Log Rotation
완전 수정 버전: 한글 지원 + False Positive 최소화 + 로그 로테이션

수정 사항:
1. ✅ extension_changed 버그 수정 (moved 이벤트만)
2. ✅ 한글 깨짐 수정 (ensure_ascii=False)
3. ✅ UTF-8 인코딩 명시
4. ✅ 임시 파일 필터링 강화
5. ✅ 시스템 파일 제외
6. ✅ 로그 로테이션 (크기/시간 기반)
7. ✅ 자동 압축 및 삭제

Author: Security Team
Date: 2025-12-06 (Final with Rotation)
"""

import os
import sys
import gzip
import shutil
from datetime import datetime, timedelta
from pathlib import Path
from collections import defaultdict
import json
import glob

try:
    from watchdog.observers import Observer
    from watchdog.events import FileSystemEventHandler
except ImportError:
    print("Error: watchdog library not installed")
    print("Run: pip3 install watchdog --break-system-packages")
    sys.exit(1)

# ==================== Configuration ====================

LOG_DIR = "./fsevents"
LOG_FILE = os.path.join(LOG_DIR, "events.json")

# 로그 로테이션 설정
LOG_ROTATION = {
    'max_bytes': 100 * 1024 * 1024,  # 100MB (파일 크기 제한)
    'max_files': 7,                   # 최대 7개 파일 보관 (7일)
    'compress': True,                 # 압축 사용 (gzip)
    'retention_days': 7,              # 7일 이상 된 파일 삭제
}

WATCH_PATHS = [
    os.path.expanduser("~/Documents"),
    os.path.expanduser("~/Desktop"),
    os.path.expanduser("~/Pictures"),
    os.path.expanduser("~/Downloads"),
]

# Ransomware extensions
RANSOMWARE_EXTENSIONS = {
    '.encrypted', '.locked', '.crypto', '.enc', '.crypt',
    '.zzzzz', '.locky', '.cerber', '.zepto', '.osiris',
    '.LockBit', '.Conti', '.BlackCat', '.ALPHV', '.STOP',
    '.Phobos', '.Dharma', '.Ryuk', '.Sodinokibi', '.REvil',
    '.Maze', '.Egregor', '.DoppelPaymer', '.NetWalker',
}

# Normal extensions
NORMAL_EXTENSIONS = {
    '.txt', '.pdf', '.doc', '.docx', '.xls', '.xlsx', '.ppt', '.pptx',
    '.jpg', '.jpeg', '.png', '.gif', '.bmp', '.svg', '.webp',
    '.mp4', '.avi', '.mov', '.mp3', '.wav', '.flac',
    '.zip', '.tar', '.gz', '.7z', '.rar',
    '.html', '.css', '.js', '.json', '.xml', '.yaml', '.yml',
    '.py', '.sh', '.bash', '.c', '.cpp', '.h', '.java',
    '.log', '.tmp', '.cache', '.bak', '.swp'
}

# Directories to exclude
EXCLUDE_DIRS = {
    '.Trash', '.cache', 'Cache', 'Caches', 'cache',
    'node_modules', '.git', '.svn', '.hg',
    'Library/Caches', 'Library/Logs', 'Library/Application Support',
    '__pycache__', '.DS_Store', 'Trash',
    '.TemporaryItems', '.DocumentRevisions-V100',
    '.Spotlight-V100', '.fseventsd'
}

# Temporary file patterns
TEMP_FILE_PATTERNS = {
    '~$', '.tmp', '.temp', '.swp', '.swo', '.swn',
    '.lock', '.crdownload', '.download', '.part', '._',
}

# System files
SYSTEM_FILES = {
    '.DS_Store', 'Thumbs.db', 'desktop.ini', '.localized',
}

# ==================== Log Rotation ====================

class LogRotator:
    """로그 파일 로테이션 관리"""
    
    def __init__(self, log_file, config):
        self.log_file = log_file
        self.config = config
        self.log_dir = os.path.dirname(log_file)
        self.base_name = os.path.basename(log_file)
    
    def should_rotate(self):
        """로테이션 필요 여부 확인"""
        if not os.path.exists(self.log_file):
            return False
        
        # 파일 크기 확인
        file_size = os.path.getsize(self.log_file)
        if file_size >= self.config['max_bytes']:
            return True
        
        return False
    
    def rotate(self):
        """로그 파일 로테이션 실행"""
        if not os.path.exists(self.log_file):
            return
        
        timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
        rotated_name = f"{self.base_name}.{timestamp}"
        rotated_path = os.path.join(self.log_dir, rotated_name)
        
        try:
            # 현재 로그 파일 이름 변경
            shutil.move(self.log_file, rotated_path)
            print(f"✓ Log rotated: {rotated_name}")
            
            # 압축 (선택)
            if self.config.get('compress', False):
                self.compress_file(rotated_path)
            
            # 오래된 파일 정리
            self.cleanup_old_files()
            
        except Exception as e:
            print(f"Error rotating log: {e}", file=sys.stderr)
    
    def compress_file(self, filepath):
        """파일 gzip 압축"""
        try:
            gz_path = f"{filepath}.gz"
            
            with open(filepath, 'rb') as f_in:
                with gzip.open(gz_path, 'wb') as f_out:
                    shutil.copyfileobj(f_in, f_out)
            
            # 원본 파일 삭제
            os.remove(filepath)
            print(f"✓ Compressed: {os.path.basename(gz_path)}")
            
        except Exception as e:
            print(f"Error compressing file: {e}", file=sys.stderr)
    
    def cleanup_old_files(self):
        """오래된 로그 파일 삭제"""
        try:
            # 로그 파일 패턴
            pattern = os.path.join(self.log_dir, f"{self.base_name}.*")
            log_files = glob.glob(pattern)
            
            # 시간 기준 삭제
            retention_days = self.config.get('retention_days', 7)
            cutoff_time = datetime.now() - timedelta(days=retention_days)
            
            deleted_count = 0
            for log_file in log_files:
                # 파일 수정 시간 확인
                mtime = datetime.fromtimestamp(os.path.getmtime(log_file))
                
                if mtime < cutoff_time:
                    os.remove(log_file)
                    print(f"✓ Deleted old log: {os.path.basename(log_file)}")
                    deleted_count += 1
            
            # 개수 기준 삭제
            max_files = self.config.get('max_files', 7)
            log_files = sorted(glob.glob(pattern), key=os.path.getmtime, reverse=True)
            
            if len(log_files) > max_files:
                for old_file in log_files[max_files:]:
                    os.remove(old_file)
                    print(f"✓ Deleted excess log: {os.path.basename(old_file)}")
                    deleted_count += 1
            
            if deleted_count > 0:
                print(f"✓ Total deleted: {deleted_count} files")
        
        except Exception as e:
            print(f"Error cleaning up old files: {e}", file=sys.stderr)
    
    def get_disk_usage(self):
        """로그 디렉토리 디스크 사용량"""
        total_size = 0
        pattern = os.path.join(self.log_dir, f"{self.base_name}*")
        
        for log_file in glob.glob(pattern):
            total_size += os.path.getsize(log_file)
        
        return total_size

# ==================== FSEvents Logger ====================

class FSEventsLogger(FileSystemEventHandler):
    """File system event logger with ransomware detection and log rotation"""
    
    def __init__(self, log_file, rotation_config):
        self.log_file = log_file
        self.event_count = 0
        self.filtered_count = 0
        self.rotation_check_interval = 100  # 100개 이벤트마다 로테이션 체크
        
        # 로그 디렉토리 생성
        os.makedirs(LOG_DIR, exist_ok=True)
        
        # 로그 로테이터 초기화
        self.rotator = LogRotator(log_file, rotation_config)
        
        print(f"✓ Log file: {log_file}")
        print(f"✓ Max size: {rotation_config['max_bytes'] / 1024 / 1024:.0f} MB")
        print(f"✓ Retention: {rotation_config['retention_days']} days")
        print(f"✓ Compression: {'enabled' if rotation_config['compress'] else 'disabled'}")
    
    def should_ignore(self, path):
        """Check if path should be ignored"""
        basename = os.path.basename(path)
        
        if basename in SYSTEM_FILES:
            return True
        
        for pattern in TEMP_FILE_PATTERNS:
            if pattern in basename:
                return True
        
        for exclude in EXCLUDE_DIRS:
            if exclude in path:
                return True
        
        if basename.startswith('.'):
            _, ext = os.path.splitext(basename)
            if ext.lower() not in RANSOMWARE_EXTENSIONS:
                return True
        
        return False
    
    def analyze_extension(self, filepath):
        """Analyze file extension for ransomware indicators"""
        _, ext = os.path.splitext(filepath)
        ext = ext.lower()
        
        # 객관적인 정보만 반환: suspicious_extension만
        if ext in RANSOMWARE_EXTENSIONS:
            return {
                'extension': ext,
                'suspicious': True
            }
        
        return {
            'extension': ext,
            'suspicious': False
        }
    
    def create_log_entry(self, event):
        """Create ECS-formatted JSON log entry"""
        filepath = event.src_path
        
        if self.should_ignore(filepath):
            self.filtered_count += 1
            return None
        
        ext_info = self.analyze_extension(filepath)
        
        event_type_map = {
            'created': 'creation',
            'modified': 'change',
            'deleted': 'deletion',
            'moved': 'rename'
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
                'extension': ext_info['extension'],
                'directory': os.path.dirname(filepath)
            },
            'host': {
                'name': os.uname().nodename,
                'os': {
                    'type': 'macos',
                    'family': 'macos',
                    'version': os.uname().release
                }
            },
            'ransomware': {
                'suspicious_extension': ext_info['suspicious']
            },
            'log': {
                'level': 'info' if not ext_info['suspicious'] else 'warning'
            }
        }
        
        if event.event_type == 'moved' and hasattr(event, 'dest_path'):
            dest_path = event.dest_path
            
            if not dest_path or self.should_ignore(dest_path):
                self.filtered_count += 1
                return None
            
            log_entry['file']['dest_path'] = dest_path
            log_entry['file']['dest_name'] = os.path.basename(dest_path)
            
            _, src_ext = os.path.splitext(filepath)
            _, dst_ext = os.path.splitext(dest_path)
            
            # 확장자가 변경된 경우
            if src_ext.lower() != dst_ext.lower():
                log_entry['ransomware']['extension_changed'] = True
                log_entry['ransomware']['original_extension'] = src_ext.lower()
                log_entry['ransomware']['new_extension'] = dst_ext.lower()
                
                # 랜섬웨어 확장자로 변경된 경우
                if dst_ext.lower() in RANSOMWARE_EXTENSIONS:
                    log_entry['ransomware']['suspicious_extension'] = True
                    log_entry['log']['level'] = 'critical'
        
        return log_entry
    
    def write_log(self, log_entry):
        """Write JSON log entry to file with rotation check"""
        if log_entry is None:
            return
        
        try:
            # 로그 로테이션 체크 (주기적)
            if self.event_count % self.rotation_check_interval == 0:
                if self.rotator.should_rotate():
                    self.rotator.rotate()
            
            # UTF-8 + ensure_ascii=False for Korean support
            with open(self.log_file, 'a', encoding='utf-8') as f:
                f.write(json.dumps(log_entry, ensure_ascii=False) + '\n')
            
            self.event_count += 1
            
            # Print high-severity events
            ransomware = log_entry.get('ransomware', {})
            if ransomware.get('suspicious_extension', False):
                if log_entry.get('log', {}).get('level') == 'critical':
                    print(f"\n🚨 CRITICAL EVENT:")
                    print(f"   File: {log_entry['file']['path']}")
                    print(f"   Extension: {log_entry['file']['extension']}")
                    if 'extension_changed' in ransomware:
                        print(f"   Changed: {ransomware['original_extension']} → {ransomware['new_extension']}")
                    print()
                else:
                    print(f"⚠️  Suspicious: {log_entry['file']['path']} ({log_entry['file']['extension']})")
        
        except Exception as e:
            print(f"Error writing log: {e}", file=sys.stderr)
    
    def on_created(self, event):
        if not event.is_directory:
            log_entry = self.create_log_entry(event)
            self.write_log(log_entry)
    
    def on_modified(self, event):
        if not event.is_directory:
            log_entry = self.create_log_entry(event)
            self.write_log(log_entry)
    
    def on_deleted(self, event):
        if not event.is_directory:
            log_entry = self.create_log_entry(event)
            self.write_log(log_entry)
    
    def on_moved(self, event):
        if not event.is_directory:
            log_entry = self.create_log_entry(event)
            self.write_log(log_entry)

# ==================== Main ====================

def main():
    """Main entry point"""
    print("="*60)
    print("FSEvents to ELK Logger (FINAL - 로그 로테이션)")
    print("="*60)
    print()
    
    if os.geteuid() != 0:
        print("⚠️  Warning: Not running as root")
        print("   Some directories may not be accessible")
        print()
    
    # Validate watch paths
    valid_paths = []
    for path in WATCH_PATHS:
        if os.path.exists(path):
            valid_paths.append(path)
            print(f"✓ Monitoring: {path}")
        else:
            print(f"✗ Path not found: {path}")
    
    if not valid_paths:
        print("\nError: No valid paths to monitor!")
        sys.exit(1)
    
    print()
    print("Filtering:")
    print(f"  - {len(EXCLUDE_DIRS)} excluded directories")
    print(f"  - {len(TEMP_FILE_PATTERNS)} temp file patterns")
    print(f"  - {len(SYSTEM_FILES)} system files")
    print(f"  - {len(RANSOMWARE_EXTENSIONS)} ransomware extensions")
    print()
    print("Features:")
    print("  ✅ 한글 파일명 지원 (UTF-8)")
    print("  ✅ extension_changed 버그 수정")
    print("  ✅ False Positive 최소화")
    print("  ✅ 로그 로테이션 (크기/시간 기반)")
    print("  ✅ 자동 압축 및 삭제")
    print()
    
    # Create event handler with rotation
    event_handler = FSEventsLogger(LOG_FILE, LOG_ROTATION)
    
    # Create observer
    observer = Observer()
    
    # Schedule monitoring
    for path in valid_paths:
        observer.schedule(event_handler, path, recursive=True)
    
    # Start monitoring
    observer.start()
    
    print("🔍 FSEvents monitoring started!")
    print(f"📝 Logging to: {LOG_FILE}")
    print(f"🗂️  Log rotation: {LOG_ROTATION['max_bytes'] / 1024 / 1024:.0f} MB")
    print(f"🛑 Press Ctrl+C to stop")
    print()
    
    try:
        while observer.is_alive():
            observer.join(1)
    except KeyboardInterrupt:
        print("\n\nStopping monitor...")
        observer.stop()
    
    observer.join()
    
    print()
    print(f"Total events logged: {event_handler.event_count}")
    print(f"Total events filtered: {event_handler.filtered_count}")
    
    # 최종 디스크 사용량 출력
    disk_usage = event_handler.rotator.get_disk_usage()
    print(f"Total disk usage: {disk_usage / 1024 / 1024:.2f} MB")
    print("FSEvents monitor stopped.")

if __name__ == '__main__':
    main()
