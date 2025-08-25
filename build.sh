#!/bin/bash

# Dừng ngay lập tức nếu có lỗi
set -e

echo "----> Creating binaries directory..."
# Tạo thư mục bin để chứa các file thực thi
mkdir -p api/bin

echo "----> Downloading jq..."
# Tải file binary của jq cho Linux 64-bit (môi trường của Vercel)
curl -L https://github.com/stedolan/jq/releases/download/jq-1.6/jq-linux64 -o api/bin/jq

echo "----> Downloading yt-dlp..."
# Tải phiên bản yt-dlp mới nhất
curl -L https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp -o api/bin/yt-dlp

echo "----> Setting permissions..."
# Cấp quyền thực thi cho cả hai file
chmod +x api/bin/jq
chmod +x api/bin/yt-dlp

echo "Build complete."
