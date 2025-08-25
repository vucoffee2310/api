#!/bin/bash

# Hàm helper để trả về JSON
http_response_json() {
  http_response_header "Content-Type" "application/json; charset=utf-8"
  echo "$1"
}

# Hàm helper để trả về lỗi JSON
json_error() {
  http_response_code "${2:-400}"
  http_response_json "{\"error\": \"$1\"}"
  exit 0
}

if [[ "$REQUEST_METHOD" == "POST" ]]; then
  json_error "This is the root endpoint. Please POST to /api/upload-youtube-audio" 405
fi

http_response_json '{"message": "API is running. Send a POST request to /api/upload-youtube-audio"}'
