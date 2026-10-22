#!/bin/sh
# Box-only: render the shelf grid in the official KOReader v2026.07.1 Linux
# build (SDL emulator, 1236x1648 @300dpi) with SimpleUI 2.7.5 + a fake
# logged-in weread (synthetic covers). Never copy this harness to the Kindle.
set -e
HERE="$(cd "$(dirname "$0")" && pwd)"; ROOT="$HERE/../.."; KW="$ROOT/.."
K=/tmp/kor; R=/tmp/korprev
[ -x $K/lib/koreader/luajit ] || { mkdir -p $K; curl -sL https://github.com/koreader/koreader/releases/download/v2026.07.1/koreader-linux-x86_64-v2026.07.1.tar.xz | tar xJ -C $K; }
mkdir -p $R/covers
python3 - <<'PY'
from PIL import Image, ImageDraw, ImageFont
import random
f=ImageFont.truetype("/usr/share/fonts/opentype/noto/NotoSerifCJK-Bold.ttc",34)
titles=["平凡的世界","杀死一只知更鸟","小王子","蛤蟆先生去看心理医生","狂人日记","神的孩子全跳舞","漫游在雨中池塘","自卑与超越","海边的卡夫卡","我是落花生","厌女","追风筝的人"]
random.seed(1)
for i,t in enumerate(titles):
    if i in (4,9): continue
    g=random.choice([235,200,90,40]); im=Image.new("L",(300,450),g); d=ImageDraw.Draw(im); fg=0 if g>128 else 255
    for k in range(6): d.rectangle([20+k*7,300+k*12,280-k*9,310+k*12],fill=(g+60)%256)
    y=60
    for j in range(0,len(t),5): d.text((30,y),t[j:j+5],font=f,fill=fg); y+=48
    im.save(f"/tmp/korprev/covers/{i}.png")
PY
python3 - <<'PY'
import zipfile
body=''.join('<p>%s</p>'%t for t in ["时，一个灰袍和尚进了院子，笑嘻嘻地先合掌诵声佛号，然后从袖子里取出两份香积钱契，口称功德。"*2,"李善德伸手接过，只觉得两撇胡须抖了一抖。"*3]*8)
with zipfile.ZipFile('/tmp/korprev/sample.epub','w') as z:
    z.writestr('mimetype','application/epub+zip',compress_type=zipfile.ZIP_STORED)
    z.writestr('META-INF/container.xml','<?xml version="1.0"?><container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container"><rootfiles><rootfile full-path="OEBPS/c.opf" media-type="application/oebps-package+xml"/></rootfiles></container>')
    z.writestr('OEBPS/c.opf','<?xml version="1.0"?><package xmlns="http://www.idpf.org/2007/opf" version="2.0" unique-identifier="id"><metadata xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:title>长安的荔枝</dc:title><dc:language>zh</dc:language><dc:identifier id="id">x1</dc:identifier></metadata><manifest><item id="c1" href="c1.xhtml" media-type="application/xhtml+xml"/><item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/></manifest><spine toc="ncx"><itemref idref="c1"/></spine></package>')
    z.writestr('OEBPS/toc.ncx','<?xml version="1.0"?><ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1"><head/><docTitle><text>长安的荔枝</text></docTitle><navMap><navPoint id="n1" playOrder="1"><navLabel><text>第一章</text></navLabel><content src="c1.xhtml"/></navPoint></navMap></ncx>')
    z.writestr('OEBPS/c1.xhtml','<?xml version="1.0" encoding="utf-8"?><html xmlns="http://www.w3.org/1999/xhtml"><head><title>第一章</title></head><body><h2>第一章</h2>%s</body></html>'%body)
PY
rm -rf /tmp/korprev/sample.sdr
P=$K/lib/koreader/plugins
rm -rf $P/simpleui.koplugin $P/wereadshelf.koplugin $P/zzwsprev.koplugin
cp -r "$KW/vendor/simpleui.koplugin" "$ROOT/wereadshelf.koplugin" $P/
mkdir -p $P/zzwsprev.koplugin && cp "$HERE/main.lua" "$HERE/_meta.lua" $P/zzwsprev.koplugin/
S=$K/lib/koreader/settings/simpleui; mkdir -p $S
rm -f $K/lib/koreader/settings/wereadshelf.lua # fresh install: no plugin settings at all
[ -n "$WSPREV_FRESH" ] && rm -f $S/sui_settings.lua && FRESH=1
[ -n "$FRESH" ] || [ -f $S/sui_settings.lua ] || printf 'return {\n ["simpleui_bar_tabs"] = { "wereadshelf_discover", "wereadshelf_open", "wereadshelf_me" },\n ["simpleui_bar_mode"] = "icons",\n ["simpleui_bar_navpager_enabled"] = true,\n}\n' > $S/sui_settings.lua
OUT="${WSPREV_DIR:-$KW/preview}"; mkdir -p "$OUT"; cd $K/lib/koreader
for mode in ${WSPREV_MODES:-shelf shelf2 discover me reader font}; do
  SDL_VIDEODRIVER=dummy EMULATE_READER_W=1236 EMULATE_READER_H=1648 EMULATE_READER_DPI=300 \
  WSPREV_WEREAD="$KW/vendor/weread.koplugin" WSPREV_MODE=$mode WSPREV_OUT="$OUT/$mode-1236x1648.png" timeout 60 ./luajit reader.lua -d $R >/dev/null 2>&1 || true
done
ls -la "$OUT"
