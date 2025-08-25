# ================================================
# FILE: api/build.sh
# ================================================
# Tạo các thư mục cần thiết
mkdir -p public bin

# Tải phiên bản yt-dlp mới nhất vào thư mục bin
curl -L https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp -o bin/yt-dlp

# Cấp quyền thực thi cho file vừa tải
chmod +x bin/yt-dlp
