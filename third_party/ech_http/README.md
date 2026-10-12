# ech_http (vendored)

Vendored copy of pub.dev `ech_http 0.2.1` (https://github.com/ech-research/ech_http),
wired in via `dependency_overrides` in `pubspec.yaml` — same pattern as
`third_party/libtorrent_flutter`.

## Why vendored

The upstream build hook embeds the whole Mozilla CA bundle (~186 KB) as a single
C++ raw string literal (`src/ca_bundle.h.in`). MSVC (VS 2022) rejects any string
literal larger than 65,535 bytes with C2026, so the C++ bridge fails to compile
on Windows builds using that toolchain (newer CI toolchains happen to accept it).

## Local patch

`src/CMakeLists.txt` now splits the CA bundle into ~14 KB raw-string chunks
joined by adjacent string concatenation. The generated `ca_bundle.h` is
semantically identical to upstream's. Everything else matches upstream 0.2.1.
If a future ech_http release fixes the chunking upstream, the vendored copy can
be dropped and the pub dependency restored.
