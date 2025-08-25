#!/bin/bash

set -eo pipefail

# --- Các hàm helper cho HTTP Response (không thay đổi) ---
http_response_header() {
  printf '%s: %s\r\n' "$1" "$2"
}
http_response_code() {
  printf 'HTTP/1.1 %s\r\n' "$1"
}
http_response_json() {
  http_response_header "Content-Type" "application/json; charset=utf-8"
  echo ""
  echo "$1"
}
json_error() {
  http_response_code "${2:-400}"
  http_response_json "{\"error\": \"$1\"}"
  exit 0
}

# --- Logic chính của Endpoint ---

if [[ "$REQUEST_METHOD" != "POST" ]]; then
  json_error "This endpoint requires a POST request." 405
fi

if [[ -z "$DEEPGRAM_API_KEY" ]]; then
  json_error "DEEPGRAM_API_KEY environment variable not set on the server." 500
fi

# Xác định đường dẫn đến các file thực thi
# $(dirname "$0") là thư mục chứa script này (api/)
base_dir="$(dirname "$0")"
yt_dlp_executable="$base_dir/bin/yt-dlp"
jq_executable="$base_dir/bin/jq" ## <<< THAY ĐỔI Ở ĐÂY

json_body=$(cat)
# Sử dụng biến jq_executable thay vì chỉ `jq`
if ! video_url=$("$jq_executable" -r '.video_url' <<< "$json_body"); then ## <<< THAY ĐỔI Ở ĐÂY
  json_error "Invalid JSON body."
fi

cookies_content=$("$jq_executable" -r '.cookies' <<< "$json_body") ## <<< THAY ĐỔI Ở ĐÂY
extractor_args=$("$jq_executable" -r '.extractor_args' <<< "$json_body") ## <<< THAY ĐỔI Ở ĐÂY

if [[ "$video_url" == "null" || "$cookies_content" == "null" || "$extractor_args" == "null" ]]; then
  json_error "Missing required fields. 'video_url', 'cookies', and 'extractor_args' are required."
fi

temp_cookie_file=$(mktemp)
trap 'rm -f "$temp_cookie_file"' EXIT
printf '%s' "$cookies_content" > "$temp_cookie_file"

upload_url='https://manage.deepgram.com/storage/assets'
echo "Starting audio download and stream for: $video_url" >&2

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

if [[ -z "$deepgram_response" ]]; then
  json_error "Failed to download or upload audio. Check server logs for details from yt-dlp." 500
fi

http_response_code 200
http_response_json "$deepgram_response"
