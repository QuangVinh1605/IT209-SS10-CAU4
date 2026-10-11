# Báo Cáo Thực Hành: Thiết lập Custom Network & Named Volume bằng Docker CLI

## Thông tin bài tập
- **Học viên:** Nguyễn Quang Vinh (Vinh Nguyen)
- **Mã lớp:** CNTT1 (DevOps IT209)
- **Môn học:** DevOps (IT209) - Session 10
- **Bài tập:** Bài 4 (EX4) - Thiết lập Custom Network & Named Volume bằng Docker CLI
- **Đường dẫn nộp bài trên GitHub:** `homework/session_10/ex4/`
- **Kho lưu trữ GitHub:** [QuangVinh1605/IT209-SS10-CAU4](https://github.com/QuangVinh1605/IT209-SS10-CAU4)

---

## 1. Mục tiêu bài thực hành
1. **Thiết lập mạng tùy chỉnh (Custom Bridge Network `app-net`):**
   - Thay thế mạng mặc định (`docker0`) bằng User-defined Bridge Network do người dùng định nghĩa.
   - Kích hoạt tính năng **Automatic Service Discovery / DNS Resolution** nội bộ của Docker: Cho phép các container trong cùng network có thể giao tiếp với nhau bằng chính tên container (hostname / service name) thay vì địa chỉ IP động dễ thay đổi.
2. **Khởi tạo và cấu hình bộ lưu trữ bền vững (Named Volume `db-data`):**
   - Tạo Docker Named Volume độc lập với vòng đời của container (Container Lifecycle Decoupling).
   - Mount Volume vào đường dẫn lưu trữ cơ sở dữ liệu PostgreSQL (`/var/lib/postgresql/data`).
3. **Kết nối cụm 2 Container qua Docker CLI:**
   - Database Container: `db-server` (`postgres:15-alpine`), mount volume `db-data`, tham gia `app-net`.
   - Backend Container: `app-container`, tham gia `app-net`, cấu hình biến môi trường kết nối trỏ trực tiếp tới hostname `db-server`.
4. **Kiểm chứng tính toàn vẹn và bền vững của dữ liệu (Data Persistence Verification):**
   - Ghi dữ liệu mẫu vào cơ sở dữ liệu PostgreSQL.
   - Xóa cưỡng bức container DB bằng lệnh `docker rm -f db-server` (mô phỏng sự cố sập container hoặc nâng cấp hệ thống).
   - Khởi chạy một container DB hoàn toàn mới gắn cùng Named Volume `db-data` và xác minh 100% dữ liệu không bị thất thoát.

---

## 2. Kiến trúc & Sơ đồ luồng dịch vụ (System & Network Architecture)

### 2.1. Sơ đồ tương tác mạng và lưu trữ

```text
+---------------------------------------------------------------------------------------------------+
|                                            DOCKER HOST                                            |
|                                                                                                   |
|  +---------------------------------------------------------------------------------------------+  |
|  |                     Custom Bridge Network: app-net (Subnet: 172.18.0.0/16)                  |  |
|  |                                                                                             |  |
|  |   +------------------------------------+          +------------------------------------+    |  |
|  |   |    Backend: app-container          |          |     Database: db-server            |    |  |
|  |   |    Image: alpine:latest            |          |     Image: postgres:15-alpine      |    |  |
|  |   |    IP: 172.18.0.3                  |          |     IP: 172.18.0.2                 |    |  |
|  |   |                                    |          |                                    |    |  |
|  |   |    Env: DB_HOST=db-server          |          |    Port: 5432 (Internal)           |    |  |
|  |   +------------------------------------+          +------------------------------------+    |  |
|  |             |                   ^                                 ^                         |  |
|  |             | DNS Lookup        | IP Response                     |                         |  |
|  |             | "db-server"       | 172.18.0.2                      |                         |  |
|  |             v                   |                                 |                         |  |
|  |      +------------------------------+                             |                         |  |
|  |      |   Docker Embedded DNS Server |                             |                         |  |
|  |      |   (127.0.0.11:53)            |                             |                         |  |
|  |      +------------------------------+                             |                         |  |
|  |                                                                   |                         |  |
|  |             =====[ TCP 5432 / ICMP Ping (Service Name Resolution) ]====>                    |  |
|  |                                                                                             |  |
|  +-------------------------------------------------------------------|-------------------------+  |
|                                                                      |                            |
|                                            Mount: -v db-data:/var/lib/postgresql/data             |
|                                                                      |                            |
|                                                                      v                            |
|                                                        +---------------------------+              |
|                                                        | Named Volume: db-data     |              |
|                                                        | (/var/lib/docker/volumes/ |              |
|                                                        |  db-data/_data)           |              |
|                                                        +---------------------------+              |
|                                                                      |                            |
|                                                      [ Persistent Data on Host Disk ]             |
+---------------------------------------------------------------------------------------------------+
```

### 2.2. Sơ đồ kiểm thử tính bền vững dữ liệu (Data Persistence Flow)

```text
  [1. db-server (ID: A)]  --->  Ghi dữ liệu (INSERT 3 rows)  ---> [Named Volume: db-data]
            |
            | docker rm -f db-server (XÓA CỨNG CONTAINER)
            v
  [Container A BỊ TIÊU HỦY]                                       [Named Volume: db-data]
                                                                  (DỮ LIỆU VẪN AN TOÀN TRÊN HOST)
            |
            | docker run -d --name db-server -v db-data:...
            v
  [2. db-server (ID: B)]  <---  Tự động nạp dữ liệu cũ  <======== [Named Volume: db-data]
            |
            v
  [XÁC MINH: SELECT * FROM products] ===> 3/3 bản ghi nguyên vẹn 100%!
```

---

## 3. Nội dung mã nguồn script tự động hóa (`commands.sh`)

Toàn bộ quá trình tạo hạ tầng mạng, volume, khởi chạy các container và thực hiện bài test data persistence được lập trình tự động trong tệp `commands.sh`:

```bash
#!/usr/bin/env bash
# ==============================================================================
# DevOps IT209 - Session 10 - Bài 4 (EX4)
# Thiết lập Custom Network & Named Volume bằng Docker CLI
# Học viên: Nguyễn Quang Vinh (Vinh Nguyen)
# Mã lớp:   CNTT1 (DevOps IT209)
# ==============================================================================

set -eo pipefail

# Màu hiển thị terminal
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${BLUE}=====================================================================${NC}"
echo -e "${GREEN}      DevOps IT209 - Session 10 - Bài 4 (EX4)                         ${NC}"
echo -e "${GREEN}      Thiết lập Custom Network & Named Volume bằng Docker CLI         ${NC}"
echo -e "${BLUE}=====================================================================${NC}\n"

# ------------------------------------------------------------------------------
# 0. Dọn dẹp tài nguyên cũ (nếu có) để đảm bảo môi trường sạch
# ------------------------------------------------------------------------------
echo -e "${YELLOW}[BƯỚC 0] Dọn dẹp tài nguyên container/network/volume cũ...${NC}"
docker rm -f db-server app-container 2>/dev/null || true
docker network rm app-net 2>/dev/null || true
docker volume rm db-data 2>/dev/null || true
echo -e "${GREEN}✓ Môi trường đã sẵn sàng!${NC}\n"

# ------------------------------------------------------------------------------
# 1. Tạo Custom Bridge Network tên app-net
# ------------------------------------------------------------------------------
echo -e "${YELLOW}[BƯỚC 1] Tạo Custom Bridge Network 'app-net'...${NC}"
docker network create app-net
echo -e "${GREEN}✓ Đã tạo thành công network 'app-net'${NC}\n"

# ------------------------------------------------------------------------------
# 2. Tạo Named Volume tên db-data
# ------------------------------------------------------------------------------
echo -e "${YELLOW}[BƯỚC 2] Tạo Named Volume 'db-data'...${NC}"
docker volume create db-data
echo -e "${GREEN}✓ Đã tạo thành công volume 'db-data'${NC}\n"

# ------------------------------------------------------------------------------
# 3. Khởi chạy Database Container (postgres:15-alpine) tên db-server
#    - Tham gia network: app-net
#    - Mount volume: db-data vào /var/lib/postgresql/data
#    - Biến môi trường cấu hình DB
# ------------------------------------------------------------------------------
echo -e "${YELLOW}[BƯỚC 3] Khởi chạy Database Container 'db-server' (postgres:15-alpine)...${NC}"
docker run -d \
  --name db-server \
  --network app-net \
  -v db-data:/var/lib/postgresql/data \
  -e POSTGRES_DB=app_db \
  -e POSTGRES_USER=postgres \
  -e POSTGRES_PASSWORD=postgres_password \
  postgres:15-alpine
echo -e "${GREEN}✓ Container 'db-server' đã khởi chạy thành công!${NC}\n"

# ------------------------------------------------------------------------------
# 4. Khởi chạy Backend Container tên app-container
#    - Tham gia network: app-net
#    - Truyền biến kết nối DB bằng hostname db-server
# ------------------------------------------------------------------------------
echo -e "${YELLOW}[BƯỚC 4] Khởi chạy Backend Container 'app-container'...${NC}"
docker run -d \
  --name app-container \
  --network app-net \
  -e DB_HOST=db-server \
  -e DB_PORT=5432 \
  -e DB_NAME=app_db \
  -e DB_USER=postgres \
  -e DB_PASSWORD=postgres_password \
  alpine:latest \
  sleep infinity
echo -e "${GREEN}✓ Container 'app-container' đã khởi chạy thành công!${NC}\n"

# ------------------------------------------------------------------------------
# 5. Kiểm tra trạng thái Network, Volume và kết nối DNS nội bộ
# ------------------------------------------------------------------------------
echo -e "${BLUE}=====================================================================${NC}"
echo -e "${CYAN}KIỂM TRA 1: Xác nhận network 'app-net' đã tồn tại${NC}"
echo -e "${BLUE}=====================================================================${NC}"
docker network ls | grep app-net
echo ""

echo -e "${BLUE}=====================================================================${NC}"
echo -e "${CYAN}KIỂM TRA 2: Xác nhận volume 'db-data' đã tồn tại${NC}"
echo -e "${BLUE}=====================================================================${NC}"
docker volume ls | grep db-data
echo ""

echo -e "${BLUE}=====================================================================${NC}"
echo -e "${CYAN}KIỂM TRA 3: Kiểm tra chi tiết cấu hình network 'app-net' (inspect)${NC}"
echo -e "${BLUE}=====================================================================${NC}"
docker network inspect app-net
echo ""

echo -e "${BLUE}=====================================================================${NC}"
echo -e "${CYAN}KIỂM TRA 4: Kiểm tra DNS Resolution & Ping từ Backend tới Database${NC}"
echo -e "${CYAN}Lệnh: docker exec app-container ping -c 2 db-server${NC}"
echo -e "${BLUE}=====================================================================${NC}"
docker exec app-container ping -c 2 db-server
echo -e "${GREEN}✓ Ping thành công! DNS nội bộ của Docker đã phân giải hostname 'db-server' chính xác.${NC}\n"

# ------------------------------------------------------------------------------
# 6. Thực hiện kiểm tra Data Persistence (Lưu trữ bền vững)
# ------------------------------------------------------------------------------
echo -e "${BLUE}=====================================================================${NC}"
echo -e "${YELLOW}[BƯỚC 5] THỬ NGHIỆM DATA PERSISTENCE (LƯU TRỮ BỀN VỮNG)${NC}"
echo -e "${BLUE}=====================================================================${NC}"

echo -e "${CYAN}1. Chờ PostgreSQL sẵn sàng tiếp nhận kết nối...${NC}"
until docker exec db-server pg_isready -U postgres >/dev/null 2>&1; do
  sleep 1
done
echo -e "${GREEN}✓ PostgreSQL đã sẵn sàng!${NC}\n"

echo -e "${CYAN}2. Tạo bảng và thêm dữ liệu vào Database qua container 'db-server'...${NC}"
docker exec -i db-server psql -U postgres -d app_db << 'EOF'
CREATE TABLE IF NOT EXISTS products (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    price NUMERIC(10, 2) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

INSERT INTO products (name, price) VALUES
    ('Laptop Dell XPS 15', 1899.99),
    ('Mechanical Keyboard RGB', 129.50),
    ('Logitech Wireless Mouse', 49.99);
EOF

echo -e "\n${CYAN}Dữ liệu hiện có trong Database trước khi xóa container:${NC}"
docker exec -i db-server psql -U postgres -d app_db -c "SELECT id, name, price, created_at FROM products;"
echo ""

echo -e "${YELLOW}3. Xóa CỨNG container DB: docker rm -f db-server...${NC}"
docker rm -f db-server
echo -e "${RED}✓ Container 'db-server' đã bị xóa hoàn toàn khỏi Docker engine!${NC}\n"

echo -e "${CYAN}4. Khởi chạy lại container DB mới, gắn cùng Named Volume 'db-data'...${NC}"
docker run -d \
  --name db-server \
  --network app-net \
  -v db-data:/var/lib/postgresql/data \
  -e POSTGRES_DB=app_db \
  -e POSTGRES_USER=postgres \
  -e POSTGRES_PASSWORD=postgres_password \
  postgres:15-alpine
echo -e "${GREEN}✓ Container 'db-server' mới đã được khởi chạy thành công!${NC}\n"

echo -e "${CYAN}5. Chờ PostgreSQL container mới khởi động và nạp dữ liệu từ Named Volume...${NC}"
until docker exec db-server pg_isready -U postgres >/dev/null 2>&1; do
  sleep 1
done
echo -e "${GREEN}✓ PostgreSQL mới đã sẵn sàng!${NC}\n"

echo -e "${BLUE}=====================================================================${NC}"
echo -e "${GREEN}XÁC MINH DỮ LIỆU SAU KHI TÁI TẠO CONTAINER DB:${NC}"
echo -e "${BLUE}=====================================================================${NC}"
docker exec -i db-server psql -U postgres -d app_db -c "SELECT id, name, price, created_at FROM products;"
echo ""

echo -e "${BLUE}=====================================================================${NC}"
echo -e "${GREEN}XÁC MINH KẾT NỐI MẠNG TỪ APP-CONTAINER TỚI DB-SERVER MỚI:${NC}"
echo -e "${BLUE}=====================================================================${NC}"
docker exec app-container ping -c 2 db-server
echo ""

echo -e "${GREEN}=====================================================================${NC}"
echo -e "${GREEN}           HOÀN THÀNH TOÀN BỘ KỊCH BẢN THỰC HÀNH BÀI 4!              ${NC}"
echo -e "${GREEN}  - Custom Bridge Network 'app-net': Hoạt động, DNS phân giải chuẩn   ${NC}"
echo -e "${GREEN}  - Named Volume 'db-data': Lưu trữ bền vững, 100% dữ liệu bảo toàn   ${NC}"
echo -e "${GREEN}=====================================================================${NC}"
```

---

## 4. Nhật ký thực thi thực tế & Kết quả kiểm tra (Execution Logs & Verification)

Dưới đây là kết quả thực thi thực tế của từng câu lệnh theo đúng yêu cầu kiểm tra bài tập:

### 4.1. Kiểm tra 1: Xác nhận mạng `app-net` đã được tạo thành công
```bash
docker network ls | grep app-net
```
*Kết quả đầu ra thực tế:*
```text
da99a90dfc0a   app-net   bridge   local
```
> **Đánh giá:** Mạng `app-net` đã được tạo thành công với driver `bridge` và phạm vi `local`.

---

### 4.2. Kiểm tra 2: Xác nhận Named Volume `db-data` đã được tạo thành công
```bash
docker volume ls | grep db-data
```
*Kết quả đầu ra thực tế:*
```text
local     db-data
```
> **Đánh giá:** Named Volume `db-data` tồn tại trên Docker host, sẵn sàng phục vụ việc mount dữ liệu cho PostgreSQL.

---

### 4.3. Kiểm tra 3: Kiểm tra chi tiết cấu hình mạng (`docker network inspect app-net`)
```bash
docker network inspect app-net
```
*Kết quả đầu ra thực tế:*
```json
[
    {
        "Name": "app-net",
        "Id": "da99a90dfc0a13fbd9e58766422d24c48b1acb6ffce6412b45995a96ccbeea57",
        "Created": "2026-10-11T19:18:07.82611818+07:00",
        "Scope": "local",
        "Driver": "bridge",
        "EnableIPv4": true,
        "EnableIPv6": false,
        "IPAM": {
            "Driver": "default",
            "Options": {},
            "Config": [
                {
                    "Subnet": "172.18.0.0/16",
                    "Gateway": "172.18.0.1"
                }
            ]
        },
        "Internal": false,
        "Attachable": false,
        "Ingress": false,
        "ConfigFrom": {
            "Network": ""
        },
        "ConfigOnly": false,
        "Options": {},
        "Labels": {},
        "Containers": {
            "9a0a3b81f6d96b3f258f5d5065dcd11ddd9562f8f2bf5e7bd7f106bec022e8bf": {
                "Name": "db-server",
                "EndpointID": "0770558f16c1781501f21ad805c109bd74f5d336870c1786a191dee9209be439",
                "MacAddress": "32:72:22:fa:20:21",
                "IPv4Address": "172.18.0.2/16",
                "IPv6Address": ""
            },
            "9f0daa84982bd361b0a0c78f83936a88a9ba9effe0df17eb424e7eed36a0761d": {
                "Name": "app-container",
                "EndpointID": "06444b8d725dd1c04cff1e487e8036c3ddbb51a93edf93533111a51d7b286828",
                "MacAddress": "ca:93:bc:7a:7b:02",
                "IPv4Address": "172.18.0.3/16",
                "IPv6Address": ""
            }
        },
        "Status": {
            "IPAM": {
                "Subnets": {
                    "172.18.0.0/16": {
                        "IPsInUse": 5,
                        "DynamicIPsAvailable": 65531
                    }
                }
            }
        }
    }
]
```
> **Phân tích kết quả:**
> - Cả 2 container `db-server` và `app-container` đều đang hoạt động và tham gia cùng subnet `172.18.0.0/16`.
> - `db-server` nhận IP nội bộ: `172.18.0.2`.
> - `app-container` nhận IP nội bộ: `172.18.0.3`.

---

### 4.4. Kiểm tra 4: Xác thực DNS Resolution & Ping từ `app-container` tới `db-server`
```bash
docker exec -it app-container ping -c 2 db-server
```
*Kết quả đầu ra thực tế:*
```text
PING db-server (172.18.0.2): 56 data bytes
64 bytes from 172.18.0.2: seq=0 ttl=64 time=0.110 ms
64 bytes from 172.18.0.2: seq=1 ttl=64 time=0.116 ms

--- db-server ping statistics ---
2 packets transmitted, 2 packets received, 0% packet loss
round-trip min/avg/max = 0.110/0.113/0.116 ms
```
> **Đánh giá:**
> - Máy chủ DNS nội bộ nhúng của Docker (`127.0.0.11`) đã phân giải chính xác hostname `db-server` thành địa chỉ IP `172.18.0.2`.
> - Tỷ lệ mất gói tin là `0%` (`0% packet loss`), thời gian phản hồi trung bình chỉ `0.113 ms`.

---

### 4.5. Kiểm tra 5: Ghi dữ liệu mẫu vào PostgreSQL
```bash
docker exec -i db-server psql -U postgres -d app_db -c "SELECT id, name, price, created_at FROM products;"
```
*Kết quả trước khi xóa container:*
```text
 id |          name           |  price  |         created_at         
----+-------------------------+---------+----------------------------
  1 | Laptop Dell XPS 15      | 1899.99 | 2026-10-11 12:18:11.012349
  2 | Mechanical Keyboard RGB |  129.50 | 2026-10-11 12:18:11.012349
  3 | Logitech Wireless Mouse |   49.99 | 2026-10-11 12:18:11.012349
(3 rows)
```

---

### 4.6. Kiểm tra 6: Xóa cứng Container Database (`docker rm -f db-server`)
```bash
docker rm -f db-server
```
*Kết quả:*
```text
db-server
```
Container `db-server` cũ mang ID `9a0a3b81f6d9` đã bị xóa hoàn toàn khỏi Docker engine. Mọi dữ liệu nằm trong tầng ghi chép tạm thời (Writable layer) của container đã biến mất vĩnh viễn.

---

### 4.7. Kiểm tra 7: Khởi chạy Container DB mới và xác minh Data Persistence
Khởi chạy container mới gắn cùng volume `db-data`:
```bash
docker run -d \
  --name db-server \
  --network app-net \
  -v db-data:/var/lib/postgresql/data \
  -e POSTGRES_DB=app_db \
  -e POSTGRES_USER=postgres \
  -e POSTGRES_PASSWORD=postgres_password \
  postgres:15-alpine
```

Truy vấn xác minh dữ liệu từ container mới:
```bash
docker exec -i db-server psql -U postgres -d app_db -c "SELECT id, name, price, created_at FROM products;"
```
*Kết quả đầu ra thực tế:*
```text
 id |          name           |  price  |         created_at         
----+-------------------------+---------+----------------------------
  1 | Laptop Dell XPS 15      | 1899.99 | 2026-10-11 12:18:11.012349
  2 | Mechanical Keyboard RGB |  129.50 | 2026-10-11 12:18:11.012349
  3 | Logitech Wireless Mouse |   49.99 | 2026-10-11 12:18:11.012349
(3 rows)
```
> **Đánh giá:**
> - Toàn bộ 3 bản ghi dữ liệu và cấu trúc bảng `products` vẫn được bảo toàn nguyên vẹn 100%.
> - Điều này chứng minh rằng dữ liệu không nằm trong vòng đời sống còn của container mà được lưu giữ độc lập và an toàn tại Named Volume `db-data` trên máy chủ host.

---

### 4.8. Kiểm tra 8: Kiểm tra DNS Resolution tới container DB mới
```bash
docker exec app-container ping -c 2 db-server
```
*Kết quả đầu ra thực tế:*
```text
PING db-server (172.18.0.2): 56 data bytes
64 bytes from 172.18.0.2: seq=0 ttl=64 time=0.151 ms
64 bytes from 172.18.0.2: seq=1 ttl=64 time=0.121 ms

--- db-server ping statistics ---
2 packets transmitted, 2 packets received, 0% packet loss
round-trip min/avg/max = 0.121/0.136/0.151 ms
```
> **Đánh giá:** Container DB mới tự động đăng ký với Docker Embedded DNS, và `app-container` tiếp tục ping thành công bằng hostname `db-server` mà không cần khởi động lại `app-container`!

---

## 5. Phân tích chuyên sâu (Deep Dive)

### 5.1. So sánh Default Bridge Network (`docker0`) vs Custom Bridge Network (`app-net`)

| Tiêu chí so sánh | Default Bridge Network (`docker0`) | Custom Bridge Network (`app-net`) |
| :--- | :--- | :--- |
| **Cơ chế phân giải DNS** | **Không hỗ trợ**. Các container chỉ giao tiếp được qua IP hoặc phải dùng cờ `--link` (đã lỗi thời / deprecated). | **Hỗ trợ tự động (Automatic Service Discovery)** thông qua Docker Embedded DNS Server (`127.0.0.11`). |
| **Cách giao tiếp giữa Container** | Buộc phải tra cứu IP động (VD: `172.17.0.2`). Nếu container crash và nhận IP mới, kết nối bị gãy. | Giao tiếp ổn định qua **Container Name / Alias** (VD: `db-server`), IP thay đổi không ảnh hưởng. |
| **Tính cô lập & Bảo mật** | Mọi container không chỉ định network sẽ tự động rơi vào `docker0`, tiềm ẩn nguy cơ xung đột và nghe lén. | **Cô lập hoàn toàn (Network Isolation)**. Chỉ các container được kết nối vào `app-net` mới nhìn thấy nhau. |
| **Khả năng cấu hình (Hot Connect)** | Không thể ngắt/gắn kết nối container khi đang chạy. | Có thể kết nối nóng hoặc ngắt kết nối linh hoạt bằng `docker network connect` / `disconnect`. |

---

### 5.2. So sánh Named Volume vs Bind Mount vs Container Writable Layer

| Cơ chế lưu trữ | Vị trí lưu dữ liệu | Vòng đời dữ liệu (Lifecycle) | Trường hợp sử dụng tối ưu |
| :--- | :--- | :--- | :--- |
| **Container Writable Layer** | Tầng ghi chép tạm của container trên UnionFS | Mất sạch dữ liệu ngay khi container bị xóa (`docker rm`) | File log tạm thời, cache ngắn hạn |
| **Named Volume** | Thư mục quản lý riêng của Docker trên Host (`/var/lib/docker/volumes/<name>/_data`) | **Bền vững**, hoàn toàn độc lập với container, an toàn khi cập nhật image/recreate | Cơ sở dữ liệu (PostgreSQL, MySQL, MongoDB), dữ liệu sản xuất |
| **Bind Mount** | Bất kỳ thư mục nào trên máy Host do người dùng chỉ định (`/home/user/app`) | Bền vững, phụ thuộc vào hệ thống tệp và phân quyền của máy Host | Mount mã nguồn phát triển (Hot reload), file cấu hình tĩnh (`nginx.conf`) |

---

## 6. Hướng dẫn thực thi & Tái hiện (Step-by-Step Guide)

Để chạy thử nghiệm toàn bộ bài thực hành, thực hiện các bước sau:

1. Di chuyển vào thư mục bài tập:
   ```bash
   cd homework/session_10/ex4
   ```
2. Cấp quyền thực thi và khởi chạy script `commands.sh`:
   ```bash
   chmod +x commands.sh
   ./commands.sh
   ```
3. Chạy các lệnh kiểm tra độc lập (nếu cần):
   ```bash
   # Kiểm tra mạng
   docker network ls | grep app-net
   docker network inspect app-net

   # Kiểm tra volume
   docker volume ls | grep db-data

   # Kiểm tra DNS resolution và Ping từ Backend sang Database
   docker exec -it app-container ping -c 2 db-server
   ```

---

## 7. Tổng kết danh mục tệp nộp bài

- [commands.sh](file:///home/vinh/Desktop/devoops/SS10/homework/session_10/ex4/commands.sh): Kịch bản bash tự động hóa tạo Network, Volume, khởi chạy 2 container và kiểm thử Data Persistence.
- [README.md](file:///home/vinh/Desktop/devoops/SS10/homework/session_10/ex4/README.md): Báo cáo kỹ thuật chi tiết với sơ đồ kiến trúc, giải thích chuyên sâu và nhật ký kiểm thử thực tế.
