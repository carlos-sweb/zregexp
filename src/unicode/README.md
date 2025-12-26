# Unicode Module

Complete Unicode support for regex operations.

## Purpose

Provides Unicode character operations, properties, and normalization.

## Components

- **CharRange**: Efficient character range sets
- **Properties**: Unicode property lookup (Scripts, Categories)
- **Case Folding**: Unicode case-insensitive matching
- **Normalization**: NFC/NFD/NFKC/NFKD
- **Tables**: Generated Unicode data (~249KB)

## Features

- General Categories: Lu, Ll, Nd, Zs, etc.
- Scripts: Latin, Greek, Cyrillic, Han, etc.
- Binary Properties: Alphabetic, Emoji, Math, etc.
- Case Folding: Full Unicode case mapping
- Normalization: All Unicode normal forms

## Files

- `charrange.zig` - Character range representation
- `properties.zig` - Property lookup
- `casefold.zig` - Case folding
- `normalize.zig` - Normalization
- `tables.zig` - Static Unicode data
- `tables_generated.zig` - Auto-generated tables
- `unicode_tests.zig` - Test aggregation

## Dependencies

- `core` - Basic types

## Data

Unicode version: 15.0
Table size: ~249KB
Generation: From Unicode Character Database (UCD)

## Status

🚧 **Not yet implemented** - Phase 4 & 7 (Weeks 10-11, 18-19)
