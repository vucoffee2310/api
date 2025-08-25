#!/bin/bash
# Thoát ngay lập tức nếu có bất kỳ lệnh nào thất bại
set -e

# Import các hàm helper của vercel-bash
source vercel-bash-helper

handler() {
  local request_body_file="$1"

  # Kiểm tra xem jq có tồn tại không
  if ! command -v jq &> /dev/null
  then
      http_response_code 500
      http_response_json
      echo '{ "error": "jq is not available in the runtime" }'
      return
  fi

  local video_url
  video_url=$(jq -r '.video_url' < "$request_body_file")
  local cookies_content
  cookies_content=$(jq -r '.cookies' < "$request_body_file")
  local extractor_args
  extractor_args=$(jq -r '.extractor_args' < "$request_body_file")

  if [[ "$video_url" == "null" || "$cookies_content" == "null" || "$extractor_args" == "null" ]]; then
    http_response_code 400
    http_response_json
    echo '{ "error": "Missing required fields. '\''video_url'\'', '\''cookies'\'', and '\''extractor_args'\'' are all required." }'
    return
  fi

  local temp_cookie_file
  temp_cookie_file=$(mktemp)
  echo "$cookies_content" > "$temp_cookie_file"

  # Đường dẫn tới file yt-dlp sẽ là tương đối so với file script này
  local yt_dlp_executable="./bin/yt-dlp"

  "$yt_dlp_executable" \
    --progress \
    --no-warnings \
    -f 'ba' \
    -S '+abr,+tbr,+size' \
    -o - \
    --cookies "$temp_cookie_file" \
    --extractor-args "$extractor_args" \
    "$video_url" 2>/dev/stderr | \
  curl --fail -X POST "$UPLOAD_URL" \
    -H "Authorization: Token $DEEPGRAM_API_KEY" \
    -H "Content-Type: audio/webm" \
    -H "accept: application/json" \
    --data-binary @-

  local curl_exit_code=$?
  rm "$temp_cookie_file"

  if [ $curl_exit_code -ne 0 ]; then
    # Nếu curl thất bại, chúng ta sẽ không có output JSON hợp lệ.
    # Vercel sẽ log lỗi từ stderr của curl.
    # Chúng ta không cần echo gì ở đây, chỉ cần để function kết thúc.
    return 1
  fi
}
