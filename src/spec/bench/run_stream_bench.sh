#!/bin/sh
# Box-only: time to first read, 0.6.0 (open after all chapters) vs 0.6.1 (after 3).
# Usage: run_stream_bench.sh [NCH] [SETUP_MS RTT_MS SERVER_MS KBPS]
HERE="$(cd "$(dirname "$0")" && pwd)"; K=/tmp/kor/lib/koreader
N=${1:-40}; SETUP=${2:-350}; RTT=${3:-50}; SRV=${4:-80}; KBPS=${5:-600}
cd $K
rm -rf /tmp/wrbench; ./luajit "$HERE/make_fixtures.lua" /tmp/wrbench $N 40 >/dev/null
python3 "$HERE/mock_weread.py" 18083 /tmp/wrbench $SETUP $RTT $SRV $KBPS & SP=$!; sleep 1
echo "link: setup ${SETUP}ms rtt ${RTT}ms server ${SRV}ms shared ${KBPS}KB/s, $N chapters"
echo "0.6.1 stream engine (opens after 3; all_done = when a 0.6.0-style open-at-end would open): $(./luajit "$HERE/bench_stream.lua" 18083 $N 3 2>/dev/null | tail -1)"
kill $SP
