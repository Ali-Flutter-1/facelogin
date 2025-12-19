#!/bin/bash

# Script to run Flutter app and show E2E logs in real-time

echo "🚀 Starting Flutter app on iPhone with E2E logging..."
echo "═══════════════════════════════════════════════════════"
echo "📝 NOTE: E2E logs will appear when you:"
echo "   1. Log out and log back in (Login E2E flow)"
echo "   2. Register a new account (Registration E2E flow)"
echo "═══════════════════════════════════════════════════════"
echo ""

# Run Flutter app and filter for E2E logs
flutter run -d "00008030-000224D10C86402E" 2>&1 | while IFS= read -r line; do
  # Show all logs, but highlight E2E logs
  if echo "$line" | grep -qE "(🔐|E2E|\[E2E|\[AUTH\]|Device ID|wrappedKu|PKd|SKd|Ku|Bootstrap|════════)"; then
    # Highlight E2E logs with colors
    if echo "$line" | grep -q "\[E2E REGISTRATION\]"; then
      echo -e "\033[1;36m$line\033[0m"  # Cyan
    elif echo "$line" | grep -q "\[E2E LOGIN\]"; then
      echo -e "\033[1;35m$line\033[0m"  # Magenta
    elif echo "$line" | grep -q "\[AUTH\]"; then
      echo -e "\033[1;33m$line\033[0m"  # Yellow
    elif echo "$line" | grep -q "✅"; then
      echo -e "\033[1;32m$line\033[0m"  # Green
    elif echo "$line" | grep -q "❌"; then
      echo -e "\033[1;31m$line\033[0m"  # Red
    elif echo "$line" | grep -q "════════"; then
      echo -e "\033[1;37m\033[1m$line\033[0m"  # Bold white for separators
    else
      echo -e "\033[0;36m$line\033[0m"  # Light cyan for other E2E logs
    fi
  else
    # Show other logs normally
    echo "$line"
  fi
done

