#!/bin/bash

# Dừng ngay lập tức nếu có lỗi
set -e

echo "----> Installing dependencies..."
# Môi trường Vercel build là Amazon Linux 2, dùng yum
yum install -y jq

echo "----> Downloading yt-dlp..."
# Tạo thư mục bin để chứa các file thực thi
mkdir -p api/bin

# Tải phiên bản yt-dlp mới nhất
curl -L https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp -o api/bin/yt-dlp

# Cấp quyền thực thi cho file
chmod +x api/bin/yt-dlp

echo "Build complete."
