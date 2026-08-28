# Lucent IR Design

The executable type definitions in src/lux are authoritative for field names and MoonBit types. This document records compatibility intent.

## Core model

- LucentRequest: model, messages, tools, options, and provider payload extensions.
- LucentResponse: output choices, usage, finish reason, and provider payload extensions.
- LucentStreamEvent: normalized conversation, item, block, delta, usage, and finish events.
- ConversionResult[T]: value plus ordered conversion diagnostics.

## Compatibility

Providers convert through this IR rather than calling another provider adapter directly. Lossy mappings emit diagnostics; unsupported fields are not presented as exact conversions. Changes follow docs/rules/lucent-ir-evolution.md.
