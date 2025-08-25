#!/bin/bash

set -eo pipefail

# ==============================================================================
# BUILD FUNCTION
# Executed by the vercel-bash builder AT BUILD TIME.
# ==============================================================================
build() {
  echo "Build function started..."
  
  # --- 1. Download the file ---
  echo "Downloading yt-dlp to the current directory..."
  # The '-o ./yt-dlp' flag explicitly tells curl to save the file
  # with the name 'yt-dlp' in the current working directory.
  curl -L https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp -o ./yt-dlp

  # --- 2. Make it executable ---
  chmod a+rx ./yt-dlp
  echo "Made ./yt-dlp executable."

  # --- 3. PROVIDE DETAILED INFORMATION (NEW LOGGING) ---
  echo "" # Add a blank line for readability
  echo "--- Build Environment & File Information ---"
  
  # Print the absolute path of the current working directory.
  # This will show you exactly where the build is happening on the Vercel server.
  # Example output: /vercel/path/to/your-project/api
  echo "Current Working Directory (pwd): $(pwd)"
  
  # List all files in this directory with details (permissions, size, date).
  # This will visually confirm that 'yt-dlp' exists and has execute permissions ('x').
  echo "Listing contents of this directory:"
  ls -la
  
  # Use the 'file' command to inspect the downloaded binary.
  # This confirms it's a valid executable and not an HTML error page.
  # Example output: ./yt-dlp: ELF 64-bit LSB executable...
  echo "Checking file type of the downloaded binary:"
  file ./yt-dlp
  
  echo "--- End of Build Information ---"
  echo ""

  echo "Build function finished successfully."
}


# ==============================================================================
# HANDLER FUNCTION
# Executed AT RUNTIME when the API endpoint is requested.
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
  
  # The path is relative to the script's location at runtime.
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
