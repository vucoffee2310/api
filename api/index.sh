#!/bin/bash

set -eo pipefail

# ==============================================================================
# BUILD FUNCTION
# Executed by the vercel-bash builder AT BUILD TIME.
# ==============================================================================
build() {
  echo "Build function started..."
  
  # --- 1. Determine the correct location to save the file ---
  # '$0' is the path to this script (e.g., /vercel/path/api/index.sh).
  # 'dirname "$0"' gets the directory part (e.g., /vercel/path/api).
  # This is the location we MUST save our files to so they get bundled.
  local SCRIPT_DIR
  SCRIPT_DIR=$(dirname "$0")

  echo "Current Working Directory (pwd): $(pwd)"
  echo "Script's Source Directory (where files must be saved): $SCRIPT_DIR"

  # --- 2. Download the file to the SCRIPT's directory ---
  local OUTPUT_PATH="$SCRIPT_DIR/yt-dlp"
  echo "Downloading yt-dlp to: $OUTPUT_PATH"
  curl -L https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp -o "$OUTPUT_PATH"

  # --- 3. Make it executable in its final location ---
  chmod a+rx "$OUTPUT_PATH"
  echo "Made $OUTPUT_PATH executable."

  # --- 4. Provide DETAILED INFORMATION for verification ---
  echo ""
  echo "--- Verifying Files in Source Directory ---"
  
  # List the contents of the SCRIPT's directory to confirm the file is there.
  echo "Listing contents of '$SCRIPT_DIR':"
  ls -la "$SCRIPT_DIR"
  
  # Use the 'file' command to inspect the downloaded binary.
  echo "Checking file type of the downloaded binary:"
  file "$OUTPUT_PATH"
  
  echo "--- End of Verification ---"
  echo ""

  echo "Build function finished successfully."
}


# ==============================================================================
# HANDLER FUNCTION
# Executed AT RUNTIME. No changes needed here.
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

  local video_url cookies_content extractor_args
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
  
  # At runtime, './yt-dlp' is correct because all bundled files are
  # in the same directory (/var/task/).
  local yt_dlp_executable="./yt-dlp"

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
