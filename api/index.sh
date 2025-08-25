#!/bin/bash

set -eo pipefail

# ==============================================================================
# BASH SERVERLESS FUNCTION FOR VERCEL
# Chức năng: Nhận URL Youtube, tải audio và stream trực tiếp lên Deepgram.
# ==============================================================================

handler() {
  # --- 1. Kiểm tra phương thức request ---
  local method
  method=$(jq -r '.method' < "$1")
  if [ "$method" != "POST" ]; then
    http_response_code 405 # Method Not Allowed
    http_response_json
    echo '{"error": "This endpoint requires a POST request."}'
    return
  fi

  # --- 2. Đọc và giải mã body của request ---
  local decoded_body
  decoded_body=$(jq -r '.body' < "$1" | base64 --decode)

  local video_url cookies_content extractor_args
  video_url=$(echo "$decoded_body" | jq -r '.video_url')
  cookies_content=$(echo "$decoded_body" | jq -r '.cookies')
  extractor_args=$(echo "$decoded_body" | jq -r '.extractor_args')

  # --- 3. Kiểm tra các tham số đầu vào ---
  if [ -z "$video_url" ] || [ -z "$cookies_content" ] || [ -z "$extractor_args" ]; then
    http_response_code 400 # Bad Request
    http_response_json
    echo '{"error": "Missing required fields. '\''video_url'\'', '\''cookies'\'', and '\''extractor_args'\'' are all required."}'
    return
  fi

  # --- 4. Chuẩn bị file cookies tạm thời ---
  local cookie_file
  cookie_file=$(mktemp)
  trap 'rm -f "$cookie_file"' EXIT
  echo "$cookies_content" > "$cookie_file"

  # --- 5. Thực thi quá trình stream ---
  # *** THAY ĐỔI QUAN TRỌNG ***
  # Đường dẫn tới file thực thi bây giờ nằm cùng thư mục với script này.
  # $(dirname "$0") là một cách an toàn để lấy đường dẫn thư mục của script đang chạy.
  local yt_dlp_executable
  yt_dlp_executable="$(dirname "$0")/yt-dlp"

  echo "INFO: Starting stream for URL: $video_url" >&2
  
  local deepgram_response
  deepgram_response=$(
    "$yt_dlp_executable" \
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
    | \
    curl -sS --fail -X POST \
      -H "Authorization: Token $DEEPGRAM_API_KEY" \
      -H "Content-Type: audio/webm" \
      -H "accept: application/json" \
      --data-binary @- \
      "$UPLOAD_URL"
  )
  
  local yt_dlp_exit_code=${PIPESTATUS[0]}
  local curl_exit_code=${PIPESTATUS[1]}

  echo "INFO: yt-dlp exit code: $yt_dlp_exit_code" >&2
  echo "INFO: curl exit code: $curl_exit_code" >&2

  # --- 6. Kiểm tra kết quả và trả về response ---
  if [ "$yt_dlp_exit_code" -ne 0 ]; then
    http_response_code 500
    http_response_json
    echo '{"error": "Failed to download audio from YouTube. Check server logs for details."}'
    return
  fi

  if [ "$curl_exit_code" -ne 0 ]; then
    http_response_code 500
    http_response_json
    echo '{"error": "Failed to upload data to Deepgram. Check server logs for curl error details."}'
    return
  fi

  http_response_code 200
  http_response_json
  echo "$deepgram_response"
}
