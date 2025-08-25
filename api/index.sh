#!/bin/bash

# ==============================================================================
# BASH SERVERLESS FUNCTION FOR VERCEL
# Chức năng: Nhận URL Youtube, tải audio và stream trực tiếp lên Deepgram.
# ==============================================================================

# Hàm handler() là entrypoint chính mà Vercel sẽ gọi.
# $1 là đường dẫn đến file chứa thông tin request (JSON format).
handler() {
  # Kiểm tra phương thức request, chỉ chấp nhận POST
  local method
  method=$(jq -r '.method' < "$1")
  if [ "$method" != "POST" ]; then
    http_response_code 405 # Method Not Allowed
    http_response_json
    echo '{"error": "This endpoint requires a POST request."}'
    return
  fi

  # Đọc và giải mã body của request (Vercel mã hóa body bằng base64)
  local decoded_body
  decoded_body=$(jq -r '.body' < "$1" | base64 --decode)

  # Trích xuất các tham số từ JSON body
  local video_url cookies_content extractor_args
  video_url=$(echo "$decoded_body" | jq -r '.video_url')
  cookies_content=$(echo "$decoded_body" | jq -r '.cookies')
  extractor_args=$(echo "$decoded_body" | jq -r '.extractor_args')

  # Kiểm tra xem các tham số bắt buộc có tồn tại không
  if [ -z "$video_url" ] || [ -z "$cookies_content" ] || [ -z "$extractor_args" ]; then
    http_response_code 400 # Bad Request
    http_response_json
    echo '{"error": "Missing required fields. '\''video_url'\'', '\''cookies'\'', and '\''extractor_args'\'' are all required."}'
    return
  fi

  # Tạo một file tạm để chứa nội dung cookies
  local cookie_file
  cookie_file=$(mktemp)
  # Đảm bảo file tạm sẽ được xóa khi script kết thúc (kể cả khi có lỗi)
  trap 'rm -f "$cookie_file"' EXIT
  # Ghi nội dung cookies vào file tạm
  echo "$cookies_content" > "$cookie_file"

  # Đường dẫn đến file thực thi yt-dlp (đã được tải về bởi build.sh)
  local yt_dlp_executable="./api/bin/yt-dlp"

  # Ghi log để debug
  echo "INFO: Starting yt-dlp stream for URL: $video_url" >&2
  
  # --- CORE LOGIC ---
  # Thực thi yt-dlp và pipe ( | ) output của nó trực tiếp vào curl
  # stderr của yt-dlp (tiến trình download) sẽ được in ra log của Vercel
  local deepgram_response
  deepgram_response=$($yt_dlp_executable \
      --progress \
      --no-warnings \
      -f 'ba' \
      -S '+abr,+tbr,+size' \
      --http-chunk-size '9M' \
      --limit-rate '29M' \
      --cookies "$cookie_file" \
      --extractor-args "$extractor_args" \
      -o - \
      "$video_url" \
      2>&1 | tee /dev/stderr | \
      curl -s -X POST \
        -H "Authorization: Token $DEEPGRAM_API_KEY" \
        -H "Content-Type: audio/webm" \
        -H "accept: application/json" \
        --data-binary @- \
        "$UPLOAD_URL"
  )
  
  # Lấy mã thoát (exit code) của các lệnh trong pipeline
  # ${PIPESTATUS[0]} là của yt-dlp, ${PIPESTATUS[1]} là của curl
  local yt_dlp_exit_code=${PIPESTATUS[0]}
  local curl_exit_code=${PIPESTATUS[2]}

  # Ghi log exit code để debug
  echo "INFO: yt-dlp exit code: $yt_dlp_exit_code" >&2
  echo "INFO: curl exit code: $curl_exit_code" >&2

  # Kiểm tra xem yt-dlp có chạy thành công không
  if [ "$yt_dlp_exit_code" -ne 0 ]; then
    http_response_code 500 # Internal Server Error
    http_response_json
    echo '{"error": "Failed to download audio from YouTube. Check server logs for details."}'
    return
  fi

  # Kiểm tra xem curl có upload thành công không
  if [ "$curl_exit_code" -ne 0 ]; then
    http_response_code 500 # Internal Server Error
    http_response_json
    echo '{"error": "Failed to upload data to Deepgram. Check server logs for details."}'
    return
  fi

  # Nếu mọi thứ thành công, trả về phản hồi từ Deepgram
  http_response_code 200 # OK
  http_response_json
  echo "$deepgram_response"
}
