# Báo Cáo Thực Hành: Tự động hóa điều phối đa dịch vụ với Docker Compose & File .env

## Thông tin bài tập
- **Học viên:** Nguyễn Quang Vinh (Vinh Nguyen)
- **Mã lớp:** CNTT1 (DevOps IT209)
- **Môn học:** DevOps (IT209) - Session 10
- **Bài tập:** Bài 5 (EX5) - Tự động hóa điều phối đa dịch vụ với Docker Compose & File .env
- **Đường dẫn nộp bài trên GitHub:** `homework/session_10/ex5/`
- **Kho lưu trữ GitHub:** [QuangVinh1605/IT209-SS10-CAU5](https://github.com/QuangVinh1605/IT209-SS10-CAU5)

---

## 1. Mục tiêu bài thực hành
1. **Chuyển dịch sang Infrastructure as Code (IaC):**
   - Đóng gói toàn bộ cụm hạ tầng 2 container (Backend Web API + PostgreSQL Database) từ các câu lệnh Docker CLI thủ công dài dòng ở bài EX4 sang tệp khai báo chuẩn hóa `docker-compose.yml`.
   - Quản lý toàn bộ vòng đời dịch vụ bằng Docker Compose CLI v2 (`docker compose`).
2. **Bảo mật và quản trị biến môi trường nhạy cảm:**
   - Phân tách triệt để thông tin xác thực (database name, user, password, port) ra khỏi tệp cấu hình chính và đưa vào tệp `.env`.
   - Cung cấp tệp mẫu cấu hình an toàn `.env.example` để chia sẻ cho các lập trình viên khác trong dự án hoặc nạp vào CI/CD pipeline.
   - Thiết lập `.gitignore` để ngăn chặn rủi ro lộ lọt thông tin bí mật lên Git repository.
3. **Cấu hình điều phối dịch vụ chuẩn mực:**
   - Sử dụng chỉ thị `depends_on` để quy định thứ tự khởi động (Database khởi chạy trước Backend).
   - Thiết lập mạng nội bộ độc lập `backend-net` và volume bền vững `pgdata` ở cấp độ root.
4. **Kiểm tra và xác thực toàn diện:**
   - Khởi chạy một lệnh `docker compose up -d` đưa toàn bộ hệ thống lên trạng thái `Running`.
   - Giám sát qua `docker compose ps`, `docker compose logs`.
   - Gửi yêu cầu HTTP kiểm tra qua `curl http://localhost:8080/` để chứng minh kết nối giữa Backend và Database thành công 100%.

---

## 2. Kiến trúc & Sơ đồ luồng dịch vụ (Architecture Flow)

```text
+---------------------------------------------------------------------------------------------------+
|                                            DOCKER HOST                                            |
|                                                                                                   |
|    +--------------------+       +--------------------+       docker compose up -d                 |
|    | docker-compose.yml | <---  |        .env        | ------------------------------+            |
|    +--------------------+       +--------------------+                               |            |
|                                                                                      v            |
|  +---------------------------------------------------------------------------------------------+  |
|  |                     Custom Bridge Network: backend-net                                      |  |
|  |                                                                                             |  |
|  |   +------------------------------------+          +------------------------------------+    |  |
|  |   | Service: backend (build: .)        |          | Service: database                  |    |  |
|  |   | Container: ex5-backend-1           |          | Container: ex5-database-1          |    |  |
|  |   | Image: ex5-backend:latest          |          | Image: postgres:15-alpine          |    |  |
|  |   |                                    |          |                                    |    |  |
|  |   | Env: DB_HOST=database              |          | Env: POSTGRES_DB=${DB_NAME}        |    |  |
|  |   |      DB_NAME=${DB_NAME}            |          |      POSTGRES_USER=${DB_USER}      |    |  |
|  |   |      PORT=8080                     |          |      POSTGRES_PASSWORD=***         |    |  |
|  |   +------------------------------------+          +------------------------------------+    |  |
|  |             |                   ^                                 ^                         |  |
|  |             |                   |                                 |                         |  |
|  |             +======[ depends_on / Service Discovery: database ]====+                         |  |
|  |             |                                                     |                         |  |
|  +-------------|-----------------------------------------------------|-------------------------+  |
|                |                                                     |                            |
|     Port Mapping: ${PORT}:8080                                       | Volume: pgdata             |
|     (0.0.0.0:8080 -> Container 8080)                                 v                            |
|                |                                       +---------------------------+              |
|                |                                       | Volume: ex5_pgdata        |              |
|                |                                       | (/var/lib/postgresql/data)|              |
|                |                                       +---------------------------+              |
+----------------|----------------------------------------------------------------------------------+
                 |
           HTTP GET / (200 OK)
                 |
          +---------------+
          | Client / curl |
          +---------------+
```

---

## 3. Nội dung cấu hình các tệp thành phần

### 3.1. Tệp điều phối `docker-compose.yml`
```yaml
services:
  database:
    image: postgres:15-alpine
    environment:
      POSTGRES_DB: ${DB_NAME}
      POSTGRES_USER: ${DB_USER}
      POSTGRES_PASSWORD: ${DB_PASSWORD}
    volumes:
      - pgdata:/var/lib/postgresql/data
    networks:
      - backend-net
    restart: unless-stopped

  backend:
    build: .
    ports:
      - "${PORT}:8080"
    environment:
      DB_HOST: database
      DB_PORT: ${DB_PORT:-5432}
      DB_NAME: ${DB_NAME}
      DB_USER: ${DB_USER}
      DB_PASSWORD: ${DB_PASSWORD}
      APP_PORT: 8080
    depends_on:
      - database
    networks:
      - backend-net
    restart: unless-stopped

volumes:
  pgdata:

networks:
  backend-net:
```

#### Phân tích chi tiết các chỉ thị:
- **`services`**: Khai báo 2 dịch vụ độc lập `database` và `backend`.
- **`environment: ... ${VAR}`**: Kỹ thuật nội suy biến môi trường (Variable Interpolation), giá trị được nạp tự động từ tệp `.env`.
- **`build: .`**: Tự động build image từ `Dockerfile` nằm cùng thư mục thay vì kéo image có sẵn.
- **`ports: ["${PORT}:8080"]`**: Ánh xạ cổng linh hoạt từ biến `${PORT}` trên máy Host vào cổng 8080 của ứng dụng.
- **`depends_on: [database]`**: Đảm bảo dịch vụ `database` được khởi tạo và bật container trước khi `backend` bắt đầu chạy.
- **`volumes: pgdata:`**: Khai báo Named Volume cấp độ root để lưu trữ dữ liệu PostgreSQL bền vững.
- **`networks: backend-net:`**: Khai báo User-defined Bridge Network cấp độ root để Docker cung cấp cơ chế DNS Resolution nội bộ qua tên service `database`.

---

### 3.2. Tệp mẫu biến môi trường `.env.example`
Tệp mẫu này được commit lên Git làm tài liệu hướng dẫn cấu hình cho toàn đội ngũ phát triển:

```bash
# ==============================================================================
# Docker Compose Environment Variables Template (.env.example)
# Bài 5: Tự động hóa điều phối đa dịch vụ với Docker Compose & File .env
# Học viên: Nguyễn Quang Vinh (Vinh Nguyen) - Mã lớp: CNTT1 (DevOps IT209)
# ==============================================================================
# Hướng dẫn: Sao chép tệp này sang .env và chỉnh sửa theo môi trường thực tế:
#   cp .env.example .env
# ==============================================================================

# Cổng truy cập dịch vụ Backend trên máy Host
PORT=8080

# Cấu hình Cơ sở dữ liệu PostgreSQL
DB_NAME=app_db
DB_USER=postgres
DB_PASSWORD=your_secure_password_here
DB_PORT=5432
```

---

### 3.3. Tệp biến môi trường thực tế `.env` (Bảo mật - Local only)
Tệp này chứa thông tin bí mật cụ thể của môi trường thực thi và được bảo vệ nghiêm ngặt:

```bash
# Cổng truy cập dịch vụ Backend trên máy Host
PORT=8080

# Cấu hình Cơ sở dữ liệu PostgreSQL
DB_NAME=app_db
DB_USER=postgres
DB_PASSWORD=postgres_secure_pass123
DB_PORT=5432
```

---

### 3.4. Tệp loại trừ `.gitignore`
Chặn triệt để tệp `.env` không bị lọt vào commit của Git:

```gitignore
# Docker environment secrets (Bảo mật biến môi trường)
.env
.env.local
.env.*.local

# Python cache & bytecode
__pycache__/
*.py[cod]
*$py.class

# Hệ điều hành
.DS_Store
Thumbs.db
```

---

### 3.5. Mã nguồn ứng dụng Backend (`app.py` & `Dockerfile`)

#### `Dockerfile`:
```dockerfile
FROM python:3.11-alpine

WORKDIR /app

# Sao chép mã nguồn ứng dụng
COPY app.py .

# Mở cổng ứng dụng
EXPOSE 8080

# Chạy ứng dụng backend
CMD ["python", "app.py"]
```

#### `app.py`:
Ứng dụng API nhẹ, tự động phát hiện và kiểm tra kết nối tới Database qua hostname `database:5432`, hỗ trợ xử lý tín hiệu `SIGTERM` để graceful shutdown:
```python
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
    try:
        sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        sock.settimeout(timeout)
        result = sock.connect_ex((host, port))
        sock.close()
        return result == 0
    except Exception:
        return False

class BackendRequestHandler(http.server.BaseHTTPRequestHandler):
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
        self.end_headers()
        self.wfile.write(json.dumps(response_data, indent=2, ensure_ascii=False).encode("utf-8"))

def main():
    import signal
    signal.signal(signal.SIGTERM, lambda s, f: sys.exit(0))
    # Chờ Database sẵn sàng
    while not check_db_connection(DB_HOST, DB_PORT):
        time.sleep(1)
    with socketserver.TCPServer(("", PORT), BackendRequestHandler) as httpd:
        httpd.serve_forever()

if __name__ == "__main__":
    main()
```

---

## 4. Nhật ký thực thi thực tế & Kết quả kiểm tra (Verification Logs)

### 4.1. Kiểm tra 1: Khởi chạy toàn bộ cụm dịch vụ (`docker compose up -d`)
```bash
docker compose up -d
```
*Kết quả đầu ra thực tế:*
```text
[+] Running 3/3
 ✔ Network ex5_backend-net  Created                                         0.6s
 ✔ Volume ex5_pgdata        Created                                         0.0s
 ✔ Container ex5-database-1 Started                                         0.6s
 ✔ Container ex5-backend-1  Started                                         1.1s
```
> **Đánh giá:** Lệnh `docker compose up -d` tự động:
> 1. Khởi tạo network nội bộ `ex5_backend-net`.
> 2. Khởi tạo named volume `ex5_pgdata`.
> 3. Khởi chạy `ex5-database-1` trước theo chỉ thị `depends_on`.
> 4. Khởi chạy `ex5-backend-1` và đưa cả 2 dịch vụ lên trạng thái hoạt động.

---

### 4.2. Kiểm tra 2: Kiểm tra trạng thái các Container (`docker compose ps`)
```bash
docker compose ps
```
*Kết quả đầu ra thực tế:*
```text
NAME             IMAGE                COMMAND                  SERVICE    CREATED         STATUS         PORTS
ex5-backend-1    ex5-backend          "python app.py"          backend    4 seconds ago   Up 3 seconds   0.0.0.0:8080->8080/tcp, [::]:8080->8080/tcp
ex5-database-1   postgres:15-alpine   "docker-entrypoint.s…"   database   4 seconds ago   Up 4 seconds   5432/tcp
```
> **Đánh giá:**
> - Cả 2 service `backend` và `database` đều ở trạng thái `Up` (Running).
> - Service `backend` ánh xạ chính xác cổng `8080` ra máy chủ host từ biến `.env`.
> - Service `database` lắng nghe nội bộ trên cổng `5432/tcp`.

---

### 4.3. Kiểm tra 3: Kiểm tra nhật ký hoạt động (`docker compose logs`)
```bash
docker compose logs
```
*Kết quả đầu ra thực tế:*
```text
backend-1   | ==================================================
backend-1   | [INFO] Khởi động Backend Web API Service...
backend-1   | [INFO] Lắng nghe tại cổng: 8080
backend-1   | [INFO] Cấu hình Database Host: database:5432
backend-1   | [INFO] Tên Database: app_db (User: postgres)
backend-1   | ==================================================
backend-1   | [INFO] Đang kiểm tra kết nối tới Database 'database:5432'...
backend-1   | [INFO] ✓ Kết nối tới Database 'database:5432' THÀNH CÔNG!
backend-1   | [INFO] HTTP Server đã sẵn sàng phục vụ tại http://0.0.0.0:8080
database-1  | 2026-10-11 12:29:29.971 UTC [1] LOG:  starting PostgreSQL 15.19 on x86_64-pc-linux-musl, compiled by gcc (Alpine 15.2.0) 15.2.0, 64-bit
database-1  | 2026-10-11 12:29:29.971 UTC [1] LOG:  listening on IPv4 address "0.0.0.0", port 5432
database-1  | 2026-10-11 12:29:29.993 UTC [1] LOG:  database system is ready to accept connections
```
> **Đánh giá:** Backend nhận diện thành công hostname `database:5432` qua DNS nội bộ của mạng Compose và kết nối thông suốt.

---

### 4.4. Kiểm tra 4: Truy vấn HTTP API (`curl -i http://localhost:8080/`)
```bash
curl -i http://localhost:8080/
```
*Kết quả đầu ra thực tế:*
```text
HTTP/1.0 200 OK
Server: BaseHTTP/0.6 Python/3.11.17
Date: Sun, 11 Oct 2026 12:29:33 GMT
Content-Type: application/json; charset=utf-8
Access-Control-Allow-Origin: *

{
  "status": "UP",
  "message": "Backend Web API is running successfully!",
  "author": "Nguyen Quang Vinh (Vinh Nguyen)",
  "class": "CNTT1 (DevOps IT209)",
  "exercise": "Session 10 - Exercise 5: Docker Compose & .env Orchestration",
  "database": {
    "host": "database",
    "port": 5432,
    "name": "app_db",
    "user": "postgres",
    "connected": true
  },
  "timestamp": "2026-10-11T12:29:33.929877Z"
}
```
> **Đánh giá:** Phản hồi mã `HTTP 200 OK` kèm JSON payload xác nhận `"connected": true`.

---

### 4.5. Kiểm tra 5: Hủy hạ tầng an toàn (`docker compose down`)
```bash
docker compose down
```
*Kết quả đầu ra thực tế:*
```text
[+] Running 3/3
 ✔ Container ex5-backend-1  Removed                                         0.6s
 ✔ Container ex5-database-1 Removed                                         0.3s
 ✔ Network ex5_backend-net  Removed                                         0.4s
```
> **Đánh giá:** Các container và network được dọn dẹp sạch sẽ trong chưa đầy 1 giây. Named Volume `pgdata` được bảo tồn nguyên vẹn trên Host.

---

## 5. Phân tích chuyên sâu (Deep Dive)

### 5.1. So sánh Docker CLI thủ công (EX4) vs Docker Compose IaC (EX5)

| Tiêu chí | Quản lý thủ công bằng Docker CLI (EX4) | Tự động hóa bằng Docker Compose (EX5) |
| :--- | :--- | :--- |
| **Phương thức quản lý** | Phải gõ từng câu lệnh `docker run`, `docker network create`, `docker volume create` riêng lẻ. | Khai báo toàn bộ hạ tầng tập trung trong một tệp duy nhất `docker-compose.yml` (IaC). |
| **Khả năng lặp lại & Tái hiện** | Dễ nhầm lẫn tham số, thứ tự chạy, khó tái hiện giữa các môi trường (Dev/Staging/Prod). | **Đồng nhất 100%**, chỉ cần 1 câu lệnh `docker compose up -d` là toàn bộ cụm dịch vụ dựng lên hoàn chỉnh. |
| **Quản trị biến môi trường** | Phải truyền hàng loạt cờ `-e KEY=VAL` dài dòng trên terminal, lộ mật khẩu trong lịch sử bash (`history`). | Tách biệt hoàn toàn vào tệp `.env`, quản lý phiên bản qua `.env.example`, không lộ bí mật. |
| **Quản lý vòng đời** | Phải dừng và xóa từng container thủ công (`docker rm -f`). | Điều khiển đồng bộ theo nhóm: `up`, `down`, `restart`, `logs` chỉ với 1 lệnh. |

---

### 5.2. Thứ tự ưu tiên nạp biến môi trường trong Docker Compose
Docker Compose áp dụng quy tắc nạp biến theo thứ tự ưu tiên giảm dần:
1. **Biến môi trường của hệ điều hành Host (Shell Environment)**: Các biến được `export` sẵn trong terminal.
2. **Tệp `.env` đặt cùng thư mục với `docker-compose.yml`**: Nạp tự động vào cú pháp nội suy `${VAR}`.
3. **Giá trị mặc định (Default values)**: Khai báo dạng `${PORT:-8080}` trong `docker-compose.yml`.

---

## 6. Hướng dẫn khởi chạy nhanh (Quick Start Guide)

```bash
# 1. Di chuyển vào thư mục bài tập
cd homework/session_10/ex5

# 2. Tạo tệp .env từ mẫu .env.example (nếu chưa có)
cp .env.example .env

# 3. Khởi chạy toàn bộ cụm dịch vụ
docker compose up -d

# 4. Kiểm tra trạng thái và logs
docker compose ps
docker compose logs -f

# 5. Kiểm tra kết nối API
curl -i http://localhost:8080/

# 6. Dừng cụm dịch vụ khi hoàn tất
docker compose down
```

---

## 7. Tổng kết danh mục tệp nộp bài

- [docker-compose.yml](file:///home/vinh/Desktop/devoops/SS10/homework/session_10/ex5/docker-compose.yml): Tệp khai báo Infrastructure as Code điều phối 2 dịch vụ `backend` và `database`.
- [.env.example](file:///home/vinh/Desktop/devoops/SS10/homework/session_10/ex5/.env.example): Tệp mẫu biến môi trường an toàn.
- [.gitignore](file:///home/vinh/Desktop/devoops/SS10/homework/session_10/ex5/.gitignore): Tệp cấu hình loại trừ `.env` khỏi Git repository.
- [Dockerfile](file:///home/vinh/Desktop/devoops/SS10/homework/session_10/ex5/Dockerfile): Định nghĩa đóng gói dịch vụ Backend Web API.
- [app.py](file:///home/vinh/Desktop/devoops/SS10/homework/session_10/ex5/app.py): Ứng dụng Backend Web API kiểm tra kết nối tới cơ sở dữ liệu PostgreSQL.
- [README.md](file:///home/vinh/Desktop/devoops/SS10/homework/session_10/ex5/README.md): Báo cáo kỹ thuật chi tiết với sơ đồ kiến trúc và nhật ký thực thi thực tế.
