#!/bin/sh
# Fetches pinned, read-only test deps into ./.deps (not shipped to Kindle).
set -e
D="$(cd "$(dirname "$0")" && pwd)/.deps"; mkdir -p "$D"; cd "$D"
[ -d weread ] || git clone -q --depth 1 -b v1.6.0 https://github.com/finlater/weread.koplugin weread
[ -d kb ] || git clone -q --depth 1 https://github.com/koreader/koreader-base kb
[ -f json.lua ] || curl -sL https://raw.githubusercontent.com/LuaDist/dkjson/master/dkjson.lua -o json.lua
echo "deps ok: $D (needs luajit + libsqlite3.so.0)"
