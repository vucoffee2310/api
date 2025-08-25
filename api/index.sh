#!/bin/bash

# Vercel-Bash runtime provides helper functions.
# We're not using them explicitly here, but the handler depends on the runtime environment.

handler() {
  # --- 1. SETTINGS & PRE-CHECKS ---

  # Exit immediately if a command in a pipeline fails, not just the last one.
  # This is crucial for catching errors from yt-dlp.
  set -o pipefail

  # Check for the required environment variable
  if [[ -z "$DEEPGRAM_API_KEY" ]]; then
    http_response_code 500
    http_response_json
    echo '{ "error": "DEEPGRAM_API_KEY environment variable not set on the server." }'
    return
  fi

  # Get the HTTP method from the request context provided by Vercel
  local method
  method="$(jq -r '.method' < "$1")"

  # We only accept POST requests
  if [[ "$method" != "POST" ]]; then
    http_response_code 405
    http_response_json
    echo '{ "error": "This endpoint requires a POST request." }'
    return
  fi


  # --- 2. PARSE INPUT JSON ---

  # Read the entire POST body from standard input into a variable
  local body
  body="$(cat)"

  # Use jq to safely parse JSON fields from the body
  local video_url cookies_content extractor_args
  video_url=$(echo "$body" | jq -r '.video_url')
  cookies_content=$(echo "$body" | jq -r '.cookies')
  extractor_args=$(echo "$body" | jq -r '.extractor_args')

  # Validate that all required fields were found
  if [[ "$video_url" == "null" || "$cookies_content" == "null" || "$extractor_args" == "null" ]]; then
    http_response_code 400
    http_response_json
    echo '{ "error": "Missing required fields. '\''video_url'\'', '\''cookies'\'', and '\''extractor_args'\'' are all required." }'
    return
  fi


  # --- 3. EXECUTE THE STREAMING LOGIC ---

  # Create a temporary file to store the cookies
  # This is safer than passing a long string on the command line
  local temp_cookie_file
  temp_cookie_file=$(mktemp)
  # Ensure the temporary file is deleted when the script exits, for any reason
  trap 'rm -f "$temp_cookie_file"' EXIT

  # Write the cookie content to the temporary file
  printf '%s' "$cookies_content" > "$temp_cookie_file"

  # Get the path to the yt-dlp executable relative to this script
  local script_dir
  script_dir=$(dirname "$0")
  local yt_dlp_executable="$script_dir/bin/yt-dlp"

  # Execute yt-dlp, piping its standard output directly to curl's standard input.
  # yt-dlp's progress and errors go to stderr, which will be captured in Vercel logs.
  # The output of the final command in the pipe (curl) is stored in DEEPGRAM_RESPONSE.
  local deepgram_response
  deepgram_response=$(
    "$yt_dlp_executable" \
      --progress \
      --no-warnings \
      -f 'ba' \
      -S '+abr,+tbr,+size' \
      '--http-chunk-size' '9M' \
      '--limit-rate' '29M' \
      '--cookies' "$temp_cookie_file" \
      '--extractor-args' "$extractor_args" \
      -o '-' \
      "$video_url" \
    | \
    curl -s -X POST \
      -H "Authorization: Token $DEEPGRAM_API_KEY" \
      -H "Content-Type: audio/webm" \
      -H "accept: application/json" \
      --data-binary @- \
      "$UPLOAD_URL"
  )

  # Check the exit code of the entire pipeline
  local exit_code=$?
  if [[ $exit_code -ne 0 ]]; then
    # An error occurred in either yt-dlp or curl.
    # The stderr from the failed command is in the Vercel function logs.
    http_response_code 500
    http_response_json
    echo '{ "error": "Failed during audio download or upload. Check server logs for details." }'
    return
  fi


  # --- 4. SEND SUCCESS RESPONSE ---

  # If we reach here, the upload was successful.
  # Forward the JSON response from Deepgram to the client.
  http_response_code 200
  http_response_json
  echo "$deepgram_response"
}
