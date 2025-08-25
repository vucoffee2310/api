#!/bin/bash

set -e

# Đảm bảo thư mục 'api' tồn tại
mkdir -p api

echo "Downloading latest yt-dlp into the function directory..."
# Tải yt-dlp trực tiếp vào thư mục /api để nó được gói cùng với function
curl -L https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp -o api/yt-dlp

# Cấp quyền thực thi
chmod +x api/yt-dlp

echo "Build script completed successfully."
