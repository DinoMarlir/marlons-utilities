#!/usr/bin/env bash

set -e

USER="DinoMarlir" # Change your user here
TARGET_ORG="DinoMarlirArchive" # Change your target organization here

echo "🔍 Loading repositories of $USER …"
repos=$(gh repo list "$USER" --limit 1000 --json name -q '.[].name')

echo
for repo in $repos; do
  echo "Repository: $repo"
  read -rp "➡️  Migrate to $TARGET_ORG? (y/n): " choice

  if [[ "$choice" == "y" ]]; then
    echo "🚀 Migrate $repo …"
    gh api \
      -X POST \
      "repos/$USER/$repo/transfer" \
      -f new_owner="$TARGET_ORG"
    echo "✅ Transfer initiated"
  else
    echo "⏭️  Skipped"
  fi

  echo "----------------------------------"
done