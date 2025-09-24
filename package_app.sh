#!/bin/bash

# Build the application in release mode
swift build -c release

# Create the app bundle structure
mkdir -p SystemMonitor.app/Contents/MacOS
mkdir -p SystemMonitor.app/Contents/Resources

# Copy the executable
cp .build/release/SystemMonitor SystemMonitor.app/Contents/MacOS/

# Copy the Info.plist
cp Sources/SystemMonitor/Info.plist SystemMonitor.app/Contents/

# Create a simple icon (this is just a placeholder, you should replace with a real icon)
echo "Creating a placeholder icon..."

# Create a zip file for distribution
zip -r SystemMonitor.zip SystemMonitor.app

echo "App bundle created at SystemMonitor.app"
echo "Zip archive created at SystemMonitor.zip"
