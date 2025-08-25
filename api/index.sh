#!/bin/bash

handler() {
  # Vercel truyền dữ liệu request vào một file tạm và cung cấp đường dẫn qua $1
  local request_body_file="$1"

  # Đọc các giá trị từ JSON body bằng jq
  # `jq -r` sẽ trả về chuỗi thô (raw string)
  local video_url
  video_url=$(jq -r '.video_url' < "$request_body_file")
  local cookies_content
  cookies_content=$(jq -r '.cookies' < "$request_body_file")
  local extractor_args
  extractor_args=$(jq -r '.extractor_args' < "$request_body_file")

  # Kiểm tra xem các trường bắt buộc có tồn tại không
  if [[ "$video_url" == "null" || "$cookies_content" == "null" || "$extractor_args" == "null" ]]; then
    http_response_code 400
    http_response_json
    echo '{ "error": "Missing required fields. '\''video_url'\'', '\''cookies'\'', and '\''extractor_args'\'' are all required." }'
    return
  fi

  # Tạo một file cookie tạm thời
  local temp_cookie_file
  temp_cookie_file=$(mktemp)
  # Ghi nội dung cookie vào file tạm
  echo "$cookies_content" > "$temp_cookie_file"

  # Lấy đường dẫn tới file thực thi yt-dlp đã được tải về từ build.sh
  # Vercel đặt các file build vào thư mục hiện tại của function
  local yt_dlp_executable="./bin/yt-dlp"

  # Thực thi yt-dlp và truyền (pipe) trực tiếp stdout (dữ liệu audio) của nó
  # vào stdin của curl để upload lên Deepgram.
  # stderr của yt-dlp (log tiến trình) sẽ được chuyển hướng tới stderr của serverless function
  # để bạn có thể xem trong Vercel logs.
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
    "$video_url" 2>/dev/stderr | \
  curl -X POST "$UPLOAD_URL" \
    -H "Authorization: Token $DEEPGRAM_API_KEY" \
    -H "Content-Type: audio/webm" \
    -H "accept: application/json" \
    --data-binary @-

  # Xóa file cookie tạm sau khi sử dụng xong
  rm "$temp_cookie_file"
}
