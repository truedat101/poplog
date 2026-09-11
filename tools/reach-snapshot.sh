#!/bin/sh
# reach-snapshot.sh — append one JSON line of reach metrics for the repo.
#
#   tools/reach-snapshot.sh              (append to the default state file)
#   REACH_DIR=/elsewhere tools/reach-snapshot.sh
#
# GitHub's traffic API (views/clones/referrers/paths) is a ROLLING 14-DAY
# WINDOW — anything not snapshotted is gone forever.  Run this daily from
# cron so outreach (posts, submissions, releases) gets a before/after.
#
# Captures: stars, forks, watchers, 14-day views/clones (+uniques),
# top referrers, top paths, and per-asset release download counts.
#
# Requires: gh (authenticated; traffic endpoints need push access), jq.
# Writes:   $REACH_DIR/reach.jsonl (default ~/.local/state/poplog-reach/).
# No credentials appear in this file or in the data; gh supplies auth.
set -e

repo="IoTone/poplog"
dir="${REACH_DIR:-$HOME/.local/state/poplog-reach}"
mkdir -p "$dir"

ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
meta=$(gh api "repos/$repo")
views=$(gh api "repos/$repo/traffic/views" 2>/dev/null || echo '{}')
clones=$(gh api "repos/$repo/traffic/clones" 2>/dev/null || echo '{}')
referrers=$(gh api "repos/$repo/traffic/popular/referrers" 2>/dev/null || echo '[]')
paths=$(gh api "repos/$repo/traffic/popular/paths" 2>/dev/null || echo '[]')
rels=$(gh api "repos/$repo/releases" --paginate)

jq -cn --arg ts "$ts" \
       --argjson meta "$meta" --argjson views "$views" \
       --argjson clones "$clones" --argjson referrers "$referrers" \
       --argjson paths "$paths" --argjson rels "$rels" '{
  ts: $ts,
  stars: $meta.stargazers_count,
  forks: $meta.forks_count,
  watchers: $meta.subscribers_count,
  views14d: {count: ($views.count // 0), uniques: ($views.uniques // 0)},
  clones14d: {count: ($clones.count // 0), uniques: ($clones.uniques // 0)},
  referrers: [$referrers[] | {ref: .referrer, count: .count, uniques: .uniques}],
  paths: [$paths[] | {path: .path, count: .count, uniques: .uniques}],
  downloads: [$rels[] | {tag: .tag_name,
                         assets: [.assets[] | {name: .name, count: .download_count}]}]
}' >> "$dir/reach.jsonl"

echo "reach-snapshot: appended $(wc -l < "$dir/reach.jsonl" | tr -d ' ') th line to $dir/reach.jsonl"
