#!/bin/bash

# This makes the script exit immediately if a command fails (`-e`),
# and ensures that a pipeline's exit code is the status of the last
# command to exit with a non-zero status (`-o pipefail`).
set -eo pipefail

# The main entrypoint for the serverless function.
# Vercel provides request metadata in the file specified by $1
# and the request body in the file specified by $2.
handler() {
  # --- 1. Check Request Method ---
  # Read the method from the Vercel request metadata file.
  local method
  method=$(jq -r '.method' < "$1")

  if [ "$method" != "POST" ]; then
    http_response_code 405 # Method Not Allowed
    http_response_json
    echo '{ "error": "This endpoint only accepts POST requests." }'
    return 0
  fi

  # --- 2. Check for API Key Environment Variable ---
  if [ -z "$DEEPGRAM_API_KEY" ]; then
    http_response_code 500 # Internal Server Error
    http_response_json
    echo '{ "error": "DEEPGRAM_API_KEY environment variable not set on the server." }'
    return 0
  fi

  # --- 3. Parse and Validate JSON Body ---
  # Read the body and extract values using jq.
  # The `// ""` provides a default empty string if the key is null or missing.
  local body
  body=$(cat "$2")

  local video_url
  local cookies_content
  local extractor_args
  video_url=$(echo "$body" | jq -r '.video_url // ""')
  cookies_content=$(echo "$body" | jq -r '.cookies // ""')
  extractor_args=$(echo "$body" | jq -r '.extractor_args // ""')

  if [ -z "$video_url" ] || [ -z "$cookies_content" ] || [ -z "$extractor_args" ]; then
    http_response_code 400 # Bad Request
    http_response_json
    echo '{ "error": "Missing required fields. '\''video_url'\'', '\''cookies'\'', and '\''extractor_args'\'' are all required." }'
    return 0
  fi

  # --- 4. Create a temporary file for cookies ---
  # mktemp creates a secure temporary file and returns its path.
  local cookie_file
  cookie_file=$(mktemp)

  # 'trap' ensures the temporary file is deleted when the script exits,
  # for any reason (success, failure, or interrupt).
  trap 'rm -f "$cookie_file"' EXIT

  # Write the cookie content from the JSON payload to the temporary file.
  echo "$cookies_content" > "$cookie_file"

  # --- 5. Execute the streaming pipeline ---
  # This is the core of the function. The standard output of yt-dlp is
  # directly piped as the standard input to curl's POST body. Standard error
  # from yt-dlp (which includes progress) goes directly to Vercel function logs.

  # Tell the client we are returning a JSON response.
  http_response_json

  # The path to the executable we downloaded during the build step.
  local yt_dlp_executable="./bin/yt-dlp"

  # The pipeline: Download from YouTube and immediately upload to Deepgram.
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

  # The output of the curl command (the response from Deepgram) becomes the
  # final output of this function. Because of 'set -eo pipefail',
  # if either yt-dlp or curl fails, the script will stop and Vercel will
  # report a function error, showing the stderr in the logs.
}
