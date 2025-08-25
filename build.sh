#!/bin/bash

# Exit immediately if a command exits with a non-zero status.
set -e

echo "--- Creating directories ---"
# The serverless function will be built inside the `api` directory
mkdir -p api/bin
mkdir -p public

echo "--- Downloading yt-dlp ---"
# Download the latest yt-dlp binary into the function's bin folder
curl -L "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp" -o api/bin/yt-dlp

echo "--- Making yt-dlp executable ---"
# Grant execute permissions
chmod +x api/bin/yt-dlp

echo "--- Build complete ---"
