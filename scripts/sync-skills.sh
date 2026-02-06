#!/bin/bash
# Sync skills between project and OpenClaw workspace
# Usage: ./sync-skills.sh [to-openclaw|from-openclaw]

PROJECT_SKILLS="/Users/RaviKiran/Documents/snowflake_test/.claude/skills"
OPENCLAW_SKILLS="/Users/ravikiran/.openclaw/workspace/skills"

SKILLS="sql-migration-planner sql-migration sql-migration-verify test-data-generator"

case "${1:-to-openclaw}" in
  to-openclaw)
    echo "Syncing: Project → OpenClaw"
    for skill in $SKILLS; do
      echo "  📦 $skill"
      cp -r "$PROJECT_SKILLS/$skill/"* "$OPENCLAW_SKILLS/$skill/" 2>/dev/null || mkdir -p "$OPENCLAW_SKILLS/$skill" && cp -r "$PROJECT_SKILLS/$skill/"* "$OPENCLAW_SKILLS/$skill/"
    done
    echo "✅ Done: Skills synced to OpenClaw"
    ;;
  from-openclaw)
    echo "Syncing: OpenClaw → Project"
    for skill in $SKILLS; do
      echo "  📦 $skill"
      cp -r "$OPENCLAW_SKILLS/$skill/"* "$PROJECT_SKILLS/$skill/" 2>/dev/null || mkdir -p "$PROJECT_SKILLS/$skill" && cp -r "$OPENCLAW_SKILLS/$skill/"* "$PROJECT_SKILLS/$skill/"
    done
    echo "✅ Done: Skills synced to Project"
    ;;
  *)
    echo "Usage: $0 [to-openclaw|from-openclaw]"
    echo "  to-openclaw   - Copy from project to OpenClaw workspace"
    echo "  from-openclaw - Copy from OpenClaw to project"
    exit 1
    ;;
esac
