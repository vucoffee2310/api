#!/bin/bash
# Thoát ngay lập tức nếu có bất kỳ lệnh nào thất bại
set -e

echo "--- Starting build process ---"

# Tạo thư mục bin bên trong thư mục api
# Vercel sẽ copy thư mục này vào môi trường chạy của function
mkdir -p api/bin

echo "--- Downloading yt-dlp ---"
curl -L https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp -o api/bin/yt-dlp

echo "--- Setting permissions for yt-dlp ---"
chmod +x api/bin/yt-dlp

echo "--- Build process finished successfully ---"
