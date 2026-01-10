#!/bin/bash

echo "🧹 Cleaning Xcode build artifacts..."

# Clean Flutter
flutter clean

# Clean pods
cd ios
rm -rf Pods Podfile.lock
pod cache clean --all

# Reinstall
cd ..
flutter pub get
cd ios
pod install

# Clean Xcode derived data (if accessible)
if [ -d ~/Library/Developer/Xcode/DerivedData ]; then
    echo "🧹 Cleaning Xcode DerivedData..."
    rm -rf ~/Library/Developer/Xcode/DerivedData/*
fi

echo "✅ Done! Now:"
echo "1. Close Xcode completely"
echo "2. Open ios/Runner.xcworkspace (NOT .xcodeproj)"
echo "3. Product → Clean Build Folder (Cmd+Shift+K)"
echo "4. Product → Build (Cmd+B)"
