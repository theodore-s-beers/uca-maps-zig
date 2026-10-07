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

Transfer the runtime tables and their shared reader to the sibling `later` repo:

```sh
cp bin/{collation,collation_cldr}.bin ../later/src/bin/
cp generated/{ccc,consts,implicit,normalization_tables}.zig ../later/src/
cp src/collation_table.zig ../later/src/collation_table.zig
cd ../later
zig fmt --check .
zig build test
zig build test --release=safe
```

Keep both copies of `src/collation_table.zig` identical when changing the format
or lookup implementation. Full regeneration also emits `generated/ccc.zig`,
`generated/consts.zig`, and `generated/implicit.zig`. These provide combining
classes, low-code-point weights, and implicit-weight rules derived from assigned
Unicode ranges, the `Unified_Ideograph` property, and the DUCET
`@implicitweights` directives. When updating the inputs, also install matching
collation conformance fixtures in `later/src/test-data/`. The `compact` command
only rebuilds the indexed binaries.

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

An entry contains a 2-bit tag (0: missing, 1: single, 2: contraction), a 16-bit
weight count at bit 2, a 32-bit weight offset at bit 18, and a 14-bit metadata
index at bit 50. Contraction entries also contain their single-character
fallback row. Sibling edges are sorted by code point. An edge with no weights
may still lead to a three-character contraction.

The reader loads trusted generator output into five typed arrays. Lookups use
page indexing, followed by a short linear search or binary search for
contraction edges. This replaces runtime collation hash maps and separate
contraction-starter lists. The indexed files are larger than the old serialized
maps; the layout is intended to reduce runtime lookup and allocation overhead.

## Indexed normalization tables

Full regeneration emits `generated/normalization_tables.zig` and verifies its
pages against the decomposition, FCD, and variable maps for every code point.
Decomposition and FCD use deduplicated 256-code-point pages; variable membership
uses four 64-bit words per page. Empty pages use a `0xffff` index sentinel.
Decomposition entries pack a 16-bit length and a values offset starting at bit
16; identical decomposition rows share storage. The generated arrays are
immutable and require no runtime allocation. Variable membership preserves the
source map's inclusion of primary-ignorable characters.

The old decomposition, FCD, and variable binary/JSON maps remain available as
intermediate data, but `later` no longer loads them.
