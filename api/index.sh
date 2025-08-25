#!/bin/bash

# This makes the script exit immediately if a command fails (`-e`),
# and ensures that a pipeline's exit code is the status of the last
# command to exit with a non-zero status (`-o pipefail`).
set -eo pipefail

# ==============================================================================
# BUILD FUNCTION (Executed at Build Time)
# ==============================================================================
build() {
  echo "Build function started..."
  mkdir -p ./bin
  echo "Downloading yt-dlp..."
  curl -L https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp -o ./bin/yt-dlp
  chmod a+rx ./bin/yt-dlp
  echo "yt-dlp downloaded and made executable."
  echo "Build function finished successfully."
}


# ==============================================================================
# HANDLER FUNCTION (Executed at Runtime)
# ==============================================================================
handler() {
  # --- 1. Validate Request Method ---
  local method
  method=$(jq -r '.method' < "$1")

  if [ "$method" != "POST" ]; then
    http_response_code 405 # Method Not Allowed
    http_response_json
    echo '{ "error": "This endpoint only accepts POST requests." }'
    return 0
  fi

  # --- 2. Validate Server Configuration ---
  if [ -z "$DEEPGRAM_API_KEY" ]; then
    http_response_code 500 # Internal Server Error
    http_response_json
    echo '{ "error": "DEEPGRAM_API_KEY environment variable not set on the server." }'
    return 0
  fi

  # --- 3. Parse and Validate JSON Request Body ---
  local body="" # Default to an empty string

  # --- FIX STARTS HERE ---
  # Check if the second argument (the path to the body file) was provided AND if it is a valid file.
  # This robustly handles requests that do not have a body.
  if [ -n "$2" ] && [ -f "$2" ]; then
    body=$(cat "$2")
  fi
  # --- FIX ENDS HERE ---

  # Extract values using jq. The `// ""` provides a default empty string if a key is missing.
  local video_url
  local cookies_content
  local extractor_args
  video_url=$(echo "$body" | jq -r '.video_url // ""')
  cookies_content=$(echo "$body" | jq -r '.cookies // ""')
  extractor_args=$(echo "$body" | jq -r '.extractor_args // ""')

  # Check if any of the required fields are empty.
  # This check will now correctly fail for requests with no body, as `video_url` will be empty.
  if [ -z "$video_url" ] || [ -z "$cookies_content" ] || [ -z "$extractor_args" ]; then
    http_response_code 400 # Bad Request
    http_response_json
    echo '{ "error": "Missing required fields. '\''video_url'\'', '\''cookies'\'', and '\''extractor_args'\'' are all required." }'
    return 0
  fi

  # --- 4. Securely Handle Cookies in a Temporary File ---
  local cookie_file
  cookie_file=$(mktemp)
  trap 'rm -f "$cookie_file"' EXIT
  echo "$cookies_content" > "$cookie_file"

  # --- 5. Execute the Streaming Pipeline ---
  http_response_json
  local yt_dlp_executable="./bin/yt-dlp"

  "$yt_dlp_executable" \
    --progress \
    --no-warnings \
    -f 'ba' \
    -S '+abr,+tbr,+size' \
    '--http-chunk-size' '9M' \
    '--limit-rate' '29M' \
    '--cookies' "$cookie_file" \
    '--extractor-args' "$extractor_args" \
    -o - \
    "$video_url" | \
  curl -s -X POST \
    -H "Authorization: Token $DEEPGRAM_API_KEY" \
    -H "Content-Type: audio/webm" \
    -H "accept: application/json" \
    --data-binary @- \
    "https://manage.deepgram.com/storage/assets"
}
