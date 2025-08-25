#!/bin/bash

# This makes the script exit immediately if a command fails (`-e`),
# and ensures that a pipeline's exit code is the status of the last
# command to exit with a non-zero status (`-o pipefail`).
set -eo pipefail

# ==============================================================================
# BUILD FUNCTION (Executed at Build Time)
# This function is executed by the vercel-bash builder when you deploy.
# Any files it creates in the current directory will be bundled with the function.
# ==============================================================================
build() {
  echo "Build function started..."
  
  # Create a 'bin' directory relative to this script.
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
# HANDLER FUNCTION (Executed at Runtime)
# This function is executed when the API endpoint is requested.
# Vercel provides request metadata in the file at $1 and the body in the file at $2.
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
  local body
  body=$(cat "$2")

  # Extract values using jq. The `// ""` provides a default empty string if a key is missing.
  local video_url
  local cookies_content
  local extractor_args
  video_url=$(echo "$body" | jq -r '.video_url // ""')
  cookies_content=$(echo "$body" | jq -r '.cookies // ""')
  extractor_args=$(echo "$body" | jq -r '.extractor_args // ""')

  # Check if any of the required fields are empty.
  if [ -z "$video_url" ] || [ -z "$cookies_content" ] || [ -z "$extractor_args" ]; then
    http_response_code 400 # Bad Request
    http_response_json
    echo '{ "error": "Missing required fields. '\''video_url'\'', '\''cookies'\'', and '\''extractor_args'\'' are all required." }'
    return 0
  fi

  # --- 4. Securely Handle Cookies in a Temporary File ---
  # mktemp creates a secure temporary file and returns its path.
  local cookie_file
  cookie_file=$(mktemp)

  # 'trap' sets up a command that will run when the script exits for any reason
  # (success, failure, or interrupt). This ensures our temp file is always deleted.
  trap 'rm -f "$cookie_file"' EXIT

  # Write the cookie content from the JSON payload into the temporary file.
  echo "$cookies_content" > "$cookie_file"

  # --- 5. Execute the Streaming Pipeline ---
  # The standard output of yt-dlp is directly piped as the standard input to curl.
  # The standard error from yt-dlp (which includes progress) goes to the Vercel function logs.

  # Tell the client we are returning a JSON response.
  http_response_json

  # Define the path to the executable we downloaded during the build step.
  local yt_dlp_executable="./bin/yt-dlp"

  # The pipeline: Download audio from YouTube and immediately upload to Deepgram.
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

  # The output of the final curl command (the response from Deepgram) becomes the
  # final output of this function. Because of 'set -eo pipefail', if either
  # yt-dlp or curl fails, the script will stop and Vercel will report an error.
}
