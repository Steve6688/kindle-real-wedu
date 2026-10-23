#!/bin/sh
# Box-only download bench. Usage: run_bench.sh [NCH] [SETUP_MS RTT_MS SERVER_MS KBPS]
HERE="$(cd "$(dirname "$0")" && pwd)"; K=/tmp/kor/lib/koreader
N=${1:-40}; SETUP=${2:-350}; RTT=${3:-50}; SRV=${4:-80}; KBPS=${5:-600}
cd $K
[ -f /tmp/wrbench/cmap.json ] || ./luajit "$HERE/make_fixtures.lua" /tmp/wrbench $N 40 >/dev/null
python3 "$HERE/mock_weread.py" 18082 /tmp/wrbench $SETUP $RTT $SRV $KBPS & SP=$!; sleep 1
echo "link: setup ${SETUP}ms rtt ${RTT}ms server ${SRV}ms shared ${KBPS}KB/s, $N chapters"
for W in 1 4; do for mode in old new; do
  rm -rf /tmp/wrout; t0=$(date +%s.%N)
  P=""
  for k in $(seq 0 $((W-1))); do (./luajit "$HERE/bench_worker.lua" 18082 $mode $k $W $N /tmp/wrout 2>/dev/null | tail -1 > /tmp/wrperf.$k) & P="$P $!"; done
  wait $P
  t1=$(date +%s.%N)
  python3 - "$W" "$mode" "$t0" "$t1" <<'PY'
import json,sys,glob
W,mode,t0,t1=sys.argv[1],sys.argv[2],float(sys.argv[3]),float(sys.argv[4])
agg={}
for f in glob.glob('/tmp/wrperf.*'):
    for k,v in json.load(open(f)).items():
        a=agg.setdefault(k,{'n':0,'s':0,'bytes':0,'wire':0})
        for x in a: a[x]+=v[x]
print("workers=%s %-3s wall=%6.2fs | "%(W,mode,t1-t0)+" | ".join("%s %.2fs/%d wire=%dKB"%(k,v['s'],v['n'],v['wire']//1024) for k,v in sorted(agg.items())))
PY
  rm -f /tmp/wrperf.*
done; done
kill $SP
