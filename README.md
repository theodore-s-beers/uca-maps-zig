# uca-maps-zig

Generate Unicode collation and normalization tables for `later`.

## Regeneration

From this repository, regenerate all binary and JSON outputs from `data/`:

```sh
zig build run
```

To rebuild only the indexed collation tables from the existing single-character
and contraction binaries:

```sh
zig build compact
zig build test
```

Both generation paths verify every code-point slot and every contraction against
the source maps before writing `bin/collation.bin` (DUCET) and
`bin/collation_cldr.bin` (CLDR). Output ordering is deterministic. The older
single-character and contraction outputs remain available as intermediate data.

Transfer the indexed tables and their shared reader to the sibling `later` repo:

```sh
cp bin/collation.bin bin/collation_cldr.bin ../later/src/bin/
cp src/collation_table.zig ../later/src/collation_table.zig
cd ../later
zig fmt --check .
zig build test
zig build test --release=safe
```

Keep both copies of `src/collation_table.zig` identical when changing the format
or lookup implementation. `later` also consumes `decomp.bin`, `fcd.bin`, and
`variable.bin`, and has separately maintained low-code-point and combining-class
arrays. Updating the Unicode inputs requires updating those products too.

## Indexed collation format (LCT1)

All integers are little-endian; records have no padding. The header contains
`LCT1` followed by five `u32` element counts. The sections follow in this order:

| Section              | Record                                                                                            |
| -------------------- | ------------------------------------------------------------------------------------------------- |
| Page index           | `u16` page number; exactly 4,352 entries                                                          |
| Entries              | `u64` packed entries, in deduplicated 256-code-point pages                                        |
| Contraction metadata | `u32 first_edge`, `u16 edge_len`, `u8 max_len`                                                    |
| Contraction edges    | `u32 codepoint`, `u32 next_first_edge`, `u32 weight_start`, `u16 next_edge_len`, `u16 weight_len` |
| Weights              | `u32` collation weights, with identical rows shared                                               |

An entry contains a two-bit tag (zero: missing, one: single, two: contraction),
a 16-bit weight count at bit 2, a 32-bit weight offset at bit 18, and a 14-bit
metadata index at bit 50. Contraction entries also contain their single-character
fallback row. Sibling edges are sorted by code point. An edge with no weights may
still lead to a three-character contraction.

The reader loads trusted generator output into five typed arrays. Lookups use
page indexing, followed by a short linear search or binary search for contraction
edges. This replaces runtime collation hash maps and separate contraction-starter
lists. The indexed files are larger than the old serialized maps; the layout is
intended to reduce runtime lookup and allocation overhead.
