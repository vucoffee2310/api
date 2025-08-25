#!/bin/bash

# Dừng ngay lập tức nếu có bất kỳ lệnh nào thất bại
set -e

# Chỉ cần tạo thư mục bin bên trong api
mkdir -p api/bin

echo "Downloading latest yt-dlp..."
# Tải phiên bản yt-dlp mới nhất vào thư mục api/bin
curl -L https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp -o api/bin/yt-dlp

# Cấp quyền thực thi cho file vừa tải
chmod +x api/bin/yt-dlp

echo "Build script completed successfully."
