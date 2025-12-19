#!/bin/bash

# Script to run Flutter app wirelessly on iPhone and show E2E debug logs

echo "📱 Setting up wireless debugging for iPhone..."
echo ""
echo "Step 1: Make sure your iPhone is connected via USB first"
echo "Step 2: In Xcode, go to Window > Devices and Simulators"
echo "Step 3: Select your iPhone and check 'Connect via network'"
echo "Step 4: Wait for wireless connection to establish"
echo ""
read -p "Press Enter when wireless connection is established..."

echo ""
echo "🔍 Checking for wireless devices..."
flutter devices

echo ""
echo "🚀 Starting Flutter app on iPhone with E2E debug logs..."
echo "═══════════════════════════════════════════════════════"
echo "Look for lines starting with: 🔐 [E2E"
echo "═══════════════════════════════════════════════════════"
echo ""

# Run Flutter and filter for E2E logs
flutter run -d "00008030-000224D10C86402E" 2>&1 | grep --line-buffered -E "(🔐|E2E|Starting|COMPLETE|Error|❌|✅|Device ID|wrappedKu|PKd|SKd|Ku)" || flutter run -d "00008030-000224D10C86402E"

