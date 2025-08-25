#!/bin/bash

# Exit immediately if a command exits with a non-zero status.
set -e

echo "Build script started..."

# Create the directory where the binary will be placed.
# This directory will be included in the serverless function bundle.
mkdir -p api/bin

# Download the latest yt-dlp binary into the 'api/bin' directory.
echo "Downloading yt-dlp..."
curl -L https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp -o api/bin/yt-dlp

# Make the binary executable for all users.
chmod a+rx api/bin/yt-dlp

echo "yt-dlp downloaded and made executable."
echo "Build script finished successfully."
