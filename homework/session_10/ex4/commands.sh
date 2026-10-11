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
