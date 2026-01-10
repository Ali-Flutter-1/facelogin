#!/bin/bash
# Complete iOS setup reinstall
# Run this when network connectivity is restored

set -e

echo "🧹 Cleaning everything..."
flutter clean
rm -rf ios/Pods ios/Podfile.lock ios/.symlinks ios/build
rm -rf ~/Library/Developer/Xcode/DerivedData/Runner-*

echo "📦 Getting Flutter dependencies..."
flutter pub get

echo "📦 Installing CocoaPods..."
cd ios
pod deintegrate || true
pod install --repo-update

echo "✅ Setup complete! You can now:"
echo "   - Run from Xcode: open ios/Runner.xcworkspace"
echo "   - Run from terminal: flutter run"
