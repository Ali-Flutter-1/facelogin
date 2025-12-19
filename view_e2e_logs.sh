#!/bin/bash

# Script to view E2E logs in real-time from Flutter app
# Run this in a separate terminal while your app is running

echo "═══════════════════════════════════════════════════════"
echo "🔐 E2E Encryption Debug Log Viewer"
echo "═══════════════════════════════════════════════════════"
echo ""
echo "This will show only E2E-related logs with clear formatting"
echo "Make sure your Flutter app is running on iPhone"
echo ""
echo "Press Ctrl+C to stop"
echo "═══════════════════════════════════════════════════════"
echo ""

# Filter Flutter logs for E2E-related content
flutter logs 2>&1 | grep --line-buffered -E "(🔐|E2E|\[E2E|\[AUTH\]|Device ID|wrappedKu|PKd|SKd|Ku|Bootstrap|Registration|Login|COMPLETE|Error|❌|✅|Starting)" | while IFS= read -r line; do
  # Color code different types of logs
  if echo "$line" | grep -q "\[E2E REGISTRATION\]"; then
    echo -e "\033[1;36m$line\033[0m"  # Cyan for registration
  elif echo "$line" | grep -q "\[E2E LOGIN\]"; then
    echo -e "\033[1;35m$line\033[0m"  # Magenta for login
  elif echo "$line" | grep -q "\[AUTH\]"; then
    echo -e "\033[1;33m$line\033[0m"  # Yellow for auth
  elif echo "$line" | grep -q "✅"; then
    echo -e "\033[1;32m$line\033[0m"  # Green for success
  elif echo "$line" | grep -q "❌"; then
    echo -e "\033[1;31m$line\033[0m"  # Red for errors
  elif echo "$line" | grep -q "════════"; then
    echo -e "\033[1;37m$line\033[0m"  # White for separators
  else
    echo "$line"
  fi
done

