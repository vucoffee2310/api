# FILE: build.sh

# Tạo các thư mục cần thiết
mkdir -p public api/bin

# TẠO MỘT FILE GIẢ ĐỂ VERCEL KHÔNG CẢNH BÁO
# Cách 1: Tạo một file index.html đơn giản
echo "API Endpoint is running." > public/index.html

# Cách 2 (phổ biến hơn): Tạo một file rỗng để giữ thư mục
# touch public/.gitkeep

# Tải phiên bản yt-dlp mới nhất vào thư mục api/bin
curl -L https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp -o api/bin/yt-dlp

# Cấp quyền thực thi cho file vừa tải
chmod +x api/bin/yt-dlp
