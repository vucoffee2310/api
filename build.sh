#!/bin/bash

# Stop immediately if any command fails
set -e

# Create the necessary directories
mkdir -p public api/bin

# Create an empty placeholder file in the 'public' directory.
# This is REQUIRED to prevent Vercel from throwing an "Output Directory is empty" error.
# The file itself has no content and serves no other purpose.
touch public/.gitkeep

echo "Downloading latest yt-dlp..."
# Download the latest version of yt-dlp into the api/bin directory
curl -L https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp -o api/bin/yt-dlp

# Grant execute permissions to the downloaded file
chmod +x api/bin/yt-dlp

echo "Build script completed successfully."
