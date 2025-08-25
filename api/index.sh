#!/bin/bash

# --- Các hàm helper (đặt bên ngoài là OK) ---
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

# --- Hàm xử lý chính ---
handler() {
  # <<< DI CHUYỂN LOGIC VÀO TRONG HANDLER
  if [[ "$REQUEST_METHOD" == "POST" ]]; then
    json_error "This is the root endpoint. Please POST to /api/upload-youtube-audio" 405
    return
  fi

  http_response_json '{"message": "API is running. Send a POST request to /api/upload-youtube-audio"}'
}
