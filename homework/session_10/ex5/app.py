#!/usr/bin/env python3
import http.server
import socketserver
import json
import os
import socket
import sys
import time
from datetime import datetime

PORT = int(os.environ.get("APP_PORT", 8080))
DB_HOST = os.environ.get("DB_HOST", "database")
DB_PORT = int(os.environ.get("DB_PORT", 5432))
DB_NAME = os.environ.get("DB_NAME", "app_db")
DB_USER = os.environ.get("DB_USER", "postgres")

def check_db_connection(host, port, timeout=2):
    """Kiểm tra kết nối TCP tới PostgreSQL server."""
    try:
        sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        sock.settimeout(timeout)
        result = sock.connect_ex((host, port))
        sock.close()
        return result == 0
    except Exception as e:
        print(f"[ERROR] Exception checking DB connection: {e}", file=sys.stderr)
        return False

class BackendRequestHandler(http.server.BaseHTTPRequestHandler):
    def log_message(self, format, *args):
        # Format log chuẩn ra STDOUT cho docker compose logs
        print(f"[{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}] {self.address_string()} - {format % args}", flush=True)

    def do_GET(self):
        is_db_ok = check_db_connection(DB_HOST, DB_PORT)
        
        response_data = {
            "status": "UP" if is_db_ok else "DEGRADED",
            "message": "Backend Web API is running successfully!",
            "author": "Nguyen Quang Vinh (Vinh Nguyen)",
            "class": "CNTT1 (DevOps IT209)",
            "exercise": "Session 10 - Exercise 5: Docker Compose & .env Orchestration",
            "database": {
                "host": DB_HOST,
                "port": DB_PORT,
                "name": DB_NAME,
                "user": DB_USER,
                "connected": is_db_ok
            },
            "timestamp": datetime.utcnow().isoformat() + "Z"
        }

        self.send_response(200 if is_db_ok else 503)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Access-Control-Allow-Origin", "*")
        self.end_headers()
        self.wfile.write(json.dumps(response_data, indent=2, ensure_ascii=False).encode("utf-8"))

def main():
    import signal
    signal.signal(signal.SIGTERM, lambda signum, frame: sys.exit(0))

    print(f"==================================================", flush=True)
    print(f"[INFO] Khởi động Backend Web API Service...", flush=True)
    print(f"[INFO] Lắng nghe tại cổng: {PORT}", flush=True)
    print(f"[INFO] Cấu hình Database Host: {DB_HOST}:{DB_PORT}", flush=True)
    print(f"[INFO] Tên Database: {DB_NAME} (User: {DB_USER})", flush=True)
    print(f"==================================================", flush=True)

    # Chờ Database khởi động nếu cần
    print(f"[INFO] Đang kiểm tra kết nối tới Database '{DB_HOST}:{DB_PORT}'...", flush=True)
    retries = 15
    while retries > 0:
        if check_db_connection(DB_HOST, DB_PORT):
            print(f"[INFO] ✓ Kết nối tới Database '{DB_HOST}:{DB_PORT}' THÀNH CÔNG!", flush=True)
            break
        print(f"[WAIT] Database chưa sẵn sàng, thử lại sau 2 giây... (còn {retries} lần)", flush=True)
        time.sleep(2)
        retries -= 1

    server_address = ("", PORT)
    with socketserver.TCPServer(server_address, BackendRequestHandler) as httpd:
        print(f"[INFO] HTTP Server đã sẵn sàng phục vụ tại http://0.0.0.0:{PORT}", flush=True)
        try:
            httpd.serve_forever()
        except KeyboardInterrupt:
            print(f"[INFO] Đang tắt máy chủ...", flush=True)
            httpd.server_close()

if __name__ == "__main__":
    main()
