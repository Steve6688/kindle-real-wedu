# Real微读 0.6.0 — download timing (box measurements, no real WeRead account)

Method: synthetic book (prose-entropy CJK, ~40 KB xhtml/chapter, valid weread shards),
weread's own Client + Content.fetch_chapter_xhtml (reader page + e_0/e_1/e_3 + decrypt)
against mock_weread.py, which simulates per-request connection setup (LuaSocket: no
keep-alive, new TCP+TLS each request), RTT, server time and a shared downlink.
Box x86 CPU; Kindle CPU numbers are ESTIMATES (x10–15 slower LuaJIT on a PW5-class ARM).

## Measured (box)
Decrypt per chapter (bench_decrypt.lua): weread 17 ms (20 KB) / 51 ms (60 KB) / 166 ms (200 KB);
fast 0.4 / 1.0 / 3.5 ms (~45–100x), output byte-identical.
EPUB packaging (save_book_epub, 20 ch): 0.05 s. Chapter checkpoint write: <1 ms. Reader-state JSON parse: ~1 ms.

Link A (setup 350 ms, RTT 50, server 80, 600 KB/s), 20 chapters:
| workers | 0.5.1 | 0.6.0 |
|---|---|---|
| 1 | 43.8 s | 40.1 s (-9%) |
| 4 | 11.5 s | 10.3 s (-11%) |
Wire bytes: reader pages 1441 -> 99 KB, shards 1076 -> 597 KB.

Link B (weak: setup 350, RTT 120, server 80, 150 KB/s), 12 chapters:
| workers | 0.5.1 | 0.6.0 |
|---|---|---|
| 1 | 36.8 s | 29.5 s (-20%) |
| 4 | 12.3 s | 7.8 s (-37%) |

Per-chapter phases (link A, serial): reader page 0.49–0.60 s, 3 shards 1.5 s, decrypt 34 ms (box),
parse 1 ms, disk <1 ms. Requests (4/chapter, each with its own handshake) dominate.

## Estimated on Kindle (not measured)
weread decrypt ~0.3–0.6 s per 40 KB chapter on device, run inside the 3–5 parallel workers
that share one CPU -> for a 100-chapter book ~30–60 s of CPU removed by the fast decoder.
Expected total gain on device: ~25–45% (decrypt + gzip), more on weak Wi-Fi.
Gzip ratios are synthetic (reader page 0.07, shards 0.55); real pages likely 0.15–0.3.
