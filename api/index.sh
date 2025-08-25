#!/bin/bash

# This makes the script exit immediately if a command fails (`-e`),
# and ensures that a pipeline's exit code is the status of the last
# command to exit with a non-zero status (`-o pipefail`).
set -eo pipefail

# ==============================================================================
# BUILD FUNCTION
# This function is executed by the vercel-bash builder AT BUILD TIME.
# Any files it creates in the current directory will be bundled with the function.
# ==============================================================================
build() {
  echo "Build function started..."
  
  # Create a 'bin' directory relative to this script.
  # This will become 'api/bin' in the project structure.
  mkdir -p ./bin

  # Download the latest yt-dlp binary into the './bin' directory.
  echo "Downloading yt-dlp..."
  curl -L https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp -o ./bin/yt-dlp

  # Make the binary executable for all users.
  chmod a+rx ./bin/yt-dlp

  echo "yt-dlp downloaded and made executable."
  echo "Build function finished successfully."
}


# ==============================================================================
# HANDLER FUNCTION
# This function is executed AT RUNTIME when the API endpoint is requested.
# ==============================================================================
handler() {
  # --- 1. Check Request Method ---
  local method
  method=$(jq -r '.method' < "$1")

  if [ "$method" != "POST" ]; then
    http_response_code 405
    http_response_json
    echo '{ "error": "This endpoint only accepts POST requests." }'
    return 0
  fi

  # --- 2. Check for API Key Environment Variable ---
  if [ -z "$DEEPGRAM_API_KEY" ]; then
    http_response_code 500
    http_response_json
    echo '{ "error": "DEEPGRAM_API_KEY environment variable not set on the server." }'
    return 0
  fi

  # --- 3. Parse and Validate JSON Body ---
  local body
  body=$(cat "$2")

  local video_url
  local cookies_content
  local extractor_args
  video_url=$(echo "$body" | jq -r '.video_url // ""')
  cookies_content=$(echo "$body" | jq -r '.cookies // ""')
  extractor_args=$(echo "$body" | jq -r '.extractor_args // ""')

  if [ -z "$video_url" ] || [ -z "$cookies_content" ] || [ -z "$extractor_args" ]; then
    http_response_code 400
    http_response_json
    echo '{ "error": "Missing required fields. '\''video_url'\'', '\''cookies'\'', and '\''extractor_args'\'' are all required." }'
    return 0
  fi

  # --- 4. Create a temporary file for cookies ---
  local cookie_file
  cookie_file=$(mktemp)
  trap 'rm -f "$cookie_file"' EXIT
  echo "$cookies_content" > "$cookie_file"

  # --- 5. Execute the streaming pipeline ---
  http_response_json
  
  # The path to the executable we downloaded during the build step.
  # It is now located in a 'bin' directory alongside this script.
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
