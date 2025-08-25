#!/bin/bash

# Cấu hình script chạy an toàn hơn:
# -e: Thoát ngay nếu một lệnh thất bại.
# -o pipefail: Trạng thái thoát của một pipeline là trạng thái của lệnh cuối cùng thất bại.
set -eo pipefail

# --- Các hàm helper cho HTTP Response ---

http_response_header() {
  printf '%s: %s\r\n' "$1" "$2"
}

http_response_code() {
  printf 'HTTP/1.1 %s\r\n' "$1"
}

http_response_json() {
  http_response_header "Content-Type" "application/json; charset=utf-8"
  echo "" # Dòng trống ngăn cách header và body
  echo "$1"
}

# Hàm helper để trả về lỗi dạng JSON và thoát
json_error() {
  http_response_code "${2:-400}"
  http_response_json "{\"error\": \"$1\"}"
  exit 0
}

# --- Logic chính của Endpoint ---

# 1. Chỉ chấp nhận phương thức POST
if [[ "$REQUEST_METHOD" != "POST" ]]; then
  json_error "This endpoint requires a POST request." 405
fi

# 2. Kiểm tra biến môi trường
if [[ -z "$DEEPGRAM_API_KEY" ]]; then
  json_error "DEEPGRAM_API_KEY environment variable not set on the server." 500
fi

# 3. Đọc và parse JSON body từ standard input
# Dữ liệu request được Vercel đưa vào stdin
json_body=$(cat)
if ! video_url=$(jq -r '.video_url' <<< "$json_body"); then
  json_error "Invalid JSON body."
fi

cookies_content=$(jq -r '.cookies' <<< "$json_body")
extractor_args=$(jq -r '.extractor_args' <<< "$json_body")

# 4. Kiểm tra các trường bắt buộc
if [[ "$video_url" == "null" || "$cookies_content" == "null" || "$extractor_args" == "null" ]]; then
  json_error "Missing required fields. 'video_url', 'cookies', and 'extractor_args' are required."
fi

# 5. Tạo file cookie tạm thời
# `mktemp` tạo một file tạm an toàn và trả về đường dẫn
temp_cookie_file=$(mktemp)
# `trap` đảm bảo file tạm sẽ được xóa khi script kết thúc (dù thành công hay thất bại)
trap 'rm -f "$temp_cookie_file"' EXIT
printf '%s' "$cookies_content" > "$temp_cookie_file"

# 6. Chuẩn bị và thực thi lệnh
# Xác định đường dẫn đến yt-dlp đã được tải về ở bước build
# $(dirname "$0") là thư mục chứa script này (api/)
yt_dlp_executable="$(dirname "$0")/bin/yt-dlp"

# URL để upload lên Deepgram
upload_url='https://manage.deepgram.com/storage/assets'

# Ghi log ra stderr để có thể xem trên Vercel logs
echo "Starting audio download and stream for: $video_url" >&2

# Thực thi pipeline:
# - Đầu ra của yt-dlp (audio data) được pipe thẳng vào đầu vào của curl.
# - stderr của yt-dlp được chuyển hướng sang stderr của script để xem log tiến trình.
# - Đầu ra của curl (phản hồi từ Deepgram) được lưu vào biến `deepgram_response`.
deepgram_response=$(
  "$yt_dlp_executable" \
    --progress \
    --no-warnings \
    -f 'ba' \
    -S '+abr,+tbr,+size' \
    --http-chunk-size '9M' \
    --limit-rate '29M' \
    --cookies "$temp_cookie_file" \
    --extractor-args "$extractor_args" \
    -o - \
    "$video_url" \
    2>&1 | tee /dev/stderr | \
  curl -sS -X POST \
    -H "Authorization: Token $DEEPGRAM_API_KEY" \
    -H "Content-Type: audio/webm" \
    -H "Accept: application/json" \
    --data-binary @- \
    "$upload_url"
)

# Kiểm tra xem pipeline có thành công không
# Nhờ `set -eo pipefail`, nếu yt-dlp hoặc curl thất bại, script sẽ thoát ở đây
# Nếu `deepgram_response` trống nghĩa là curl có thể đã thất bại
if [[ -z "$deepgram_response" ]]; then
  json_error "Failed to download or upload audio. Check server logs for details from yt-dlp." 500
fi

# 7. Trả về phản hồi thành công từ Deepgram
http_response_code 200
http_response_json "$deepgram_response"
