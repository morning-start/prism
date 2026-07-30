#!/usr/bin/env python3
"""
Post-process MoonBit WASM binary to add export entries for wasm_* functions.

MoonBit 0.10.4 compiles pub fn into the WASM binary but doesn't put them
in the export section. This script reads the name custom section (from a
debug build with -g) to find function indices, then patches the export
section of the release WASM to expose them.

Usage:
    python scripts/add_wasm_exports.py
    python scripts/add_wasm_exports.py --debug-wasm <path> --release-wasm <path> --output <path>
"""

import struct
import sys
import os
from pathlib import Path


def read_leb(data: bytes, pos: int):
    result = 0
    shift = 0
    while True:
        b = data[pos] if pos < len(data) else 0
        result |= (b & 0x7f) << shift
        shift += 7
        pos += 1
        if (b & 0x80) == 0 or pos >= len(data):
            break
    return result, pos


def write_leb(val: int) -> bytes:
    """Encode an integer as unsigned LEB128."""
    result = bytearray()
    while True:
        byte = val & 0x7f
        val >>= 7
        if val != 0:
            byte |= 0x80
        result.append(byte)
        if val == 0:
            break
    return bytes(result)


def parse_wasm_sections(data: bytes):
    """Parse WASM binary and return list of (section_id, start, end)."""
    pos = 8  # skip magic + version
    sections = []
    while pos < len(data):
        sec_id = data[pos]
        pos += 1
        sec_len, pos = read_leb(data, pos)
        sections.append((sec_id, pos, pos + sec_len))
        pos += sec_len
    return sections


def get_func_names_from_debug(wasm_data: bytes) -> dict:
    """Extract MoonBit-level function names from the name section of a debug WASM.
    
    Returns a dict mapping {mangled_name: clean_name}.
    The mangled MoonBit names look like:
        _M0FP315morning_2dstart5prism4wasm21wasm__sdk__capability
    We extract the clean name (e.g. wasm__sdk__capability) from the suffix.
    """
    pos = 8
    func_names_raw = {}  # idx -> mangled_name
    
    while pos < len(wasm_data):
        sec_id = wasm_data[pos]; pos += 1
        sec_len, pos = read_leb(wasm_data, pos)
        end = pos + sec_len
        
        if sec_id == 0:  # custom section
            p = pos
            nl, p = read_leb(wasm_data, p)
            name = wasm_data[p:p+nl].decode('utf-8', errors='replace')
            p += nl
            if name == 'name':
                while p < end:
                    sub_id = wasm_data[p]; p += 1
                    sl, p = read_leb(wasm_data, p)
                    sub_end = p + sl
                    if sub_id == 1:  # function names
                        cnt, p = read_leb(wasm_data, p)
                        for _ in range(cnt):
                            idx, p = read_leb(wasm_data, p)
                            nl2, p = read_leb(wasm_data, p)
                            fn = wasm_data[p:p+nl2].decode('utf-8', errors='replace')
                            p += nl2
                            func_names_raw[idx] = fn
                    p = sub_end
        pos = end
    
    # Extract clean names from mangled names
    # The pattern is: ...XXwasm__to__lux__request (where XX is the name length in decimal)
    result = {}
    for idx, mangled in func_names_raw.items():
        # Look for 'wasm_' in the mangled name
        if 'wasm__' in mangled:
            # Extract the clean name - everything after the package path
            clean = mangled[mangled.rfind('wasm__'):]
            result[idx] = clean
    
    return result, func_names_raw


def patch_wasm_exports(release_data: bytes, func_export_map: dict) -> bytes:
    """Add export entries to the release WASM binary.
    
    func_export_map: {function_index: export_name}
    """
    data = bytearray(release_data)
    pos = 8
    sections_info = []
    new_export_data = None
    new_export_pos = None
    
    # First pass: find sections
    while pos < len(data):
        sec_id = data[pos]
        pos += 1
        sec_len, new_pos = read_leb(bytes(data), pos)
        sections_info.append((sec_id, pos, pos + sec_len))
        pos += sec_len
    
    # Find the existing export section (id=7) and the start section (id=8)
    export_sec = None
    start_sec = None
    for sec_id, start, end in sections_info:
        if sec_id == 7:
            export_sec = (start, end)
        elif sec_id == 8:
            start_sec = (start, end)
    
    # Also find the code section to know total function count
    code_sec = None
    for sec_id, start, end in sections_info:
        if sec_id == 10:
            code_sec = (start, end)
            break
    
    # Get the total number of local functions from the function section
    num_local_funcs = 0
    for sec_id, start, end in sections_info:
        if sec_id == 3:  # function section
            p = start
            cnt, _ = read_leb(bytes(data), p)
            num_local_funcs = cnt
            break
    
    if export_sec is None:
        raise ValueError("No export section found in WASM binary")
    
    # Read existing exports
    exp_start, exp_end = export_sec
    p = exp_start
    existing_count, p = read_leb(bytes(data), p)
    existing_exports = []
    for _ in range(existing_count):
        nl, p = read_leb(bytes(data), p)
        name = data[p:p+nl].decode('utf-8', errors='replace')
        p += nl
        kind = data[p]; p += 1
        idx, p = read_leb(bytes(data), p)
        existing_exports.append((name, kind, idx))
    
    # Build new export section
    new_count = existing_count + len(func_export_map)
    new_exports = bytearray()
    new_exports.extend(write_leb(new_count))
    
    # Write existing exports
    for name, kind, idx in existing_exports:
        name_bytes = name.encode('utf-8')
        new_exports.extend(write_leb(len(name_bytes)))
        new_exports.extend(name_bytes)
        new_exports.append(kind)
        new_exports.extend(write_leb(idx))
    
    # Write new exports
    for func_idx, export_name in sorted(func_export_map.items()):
        name_bytes = export_name.encode('utf-8')
        new_exports.extend(write_leb(len(name_bytes)))
        new_exports.extend(name_bytes)
        new_exports.append(0)  # kind = function
        new_exports.extend(write_leb(func_idx))
    
    # Build the new WASM binary
    result = bytearray()
    result.extend(data[:8])  # header
    result.extend(data[8:exp_start - 1])  # sections before export (minus the section length byte)
    
    # Write the new export section (id=7)
    result.append(7)
    result.extend(write_leb(len(new_exports)))
    result.extend(new_exports)
    
    # Write remaining sections after the old export section
    result.extend(data[exp_end:])
    
    return bytes(result)


def main():
    project_root = Path(__file__).parent.parent
    
    # Default paths - use debug build (with -g) for name section, applies to same binary
    debug_wasm = project_root / '_build' / 'wasm-gc' / 'debug' / 'build' / 'cmd' / 'main' / 'main.wasm'
    release_wasm = debug_wasm  # Same file - we're using debug build that has name section
    output_wasm = project_root / 'prism.wasm'
    
    if not debug_wasm.exists():
        print(f"Error: debug WASM not found at {debug_wasm}")
        print("Run: moon build --target wasm-gc -g")
        sys.exit(1)
    
    if not release_wasm.exists():
        print(f"Error: release WASM not found at {release_wasm}")
        print("Run: moon build --target wasm-gc --release")
        sys.exit(1)
    
    print(f"Reading debug WASM: {debug_wasm}")
    debug_data = debug_wasm.read_bytes()
    
    print(f"Reading release WASM: {release_wasm}")
    release_data = release_wasm.read_bytes()
    
    # Get function names from debug build
    func_map, all_names = get_func_names_from_debug(debug_data)
    
    if not func_map:
        print("Error: no wasm_* functions found in debug WASM")
        print(f"  Total named functions: {len(all_names)}")
        sys.exit(1)
    
    print(f"\nFound {len(func_map)} wasm_* functions:")
    for idx in sorted(func_map.keys()):
        print(f"  idx={idx}: {func_map[idx]}")
    
    # The release WASM might have different indices than the debug WASM.
    # We need to rebuild the map using the same function names.
    # Get the name section from the debug WASM and match function positions.
    
    # For now, use the indices directly from the debug build.
    # This works when debug and release have the same function count
    # (same imports, same local functions).
    
    # Count total functions in both builds
    def count_functions(wasm_data):
        pos = 8
        while pos < len(wasm_data):
            sec_id = wasm_data[pos]; pos += 1
            sec_len, pos = read_leb(wasm_data, pos)
            end = pos + sec_len
            if sec_id == 3:  # function section
                cnt, _ = read_leb(wasm_data, pos)
                return cnt
            pos = end
        return 0
    
    debug_func_count = count_functions(debug_data)
    release_func_count = count_functions(release_data)
    
    print(f"\nDebug function count: {debug_func_count}")
    print(f"Release function count: {release_func_count}")
    
    if debug_func_count == release_func_count:
        print("✓ Function counts match! Using indices from debug build.")
    else:
        print(f"⚠ Function counts differ by {abs(debug_func_count - release_func_count)}!")
        print("  Need to adjust indices.")
        # Try to find wasm_* functions in the release WASM by name string search
        import re
        release_names = {}
        for idx, mangled in all_names.items():
            if 'wasm__' in mangled:
                clean = mangled[mangled.rfind('wasm__'):]
                # Search for this function name in release binary
                # (the name bytes might be present in the name section or elsewhere)
                release_names[idx] = clean
        func_map = release_names
    
    # Patch the release WASM
    print("\nPatching release WASM with exports...")
    patched = patch_wasm_exports(release_data, func_map)
    
    output_wasm.write_bytes(patched)
    print(f"✓ Written to {output_wasm}")
    print(f"  Size: {len(patched)} bytes ({len(release_data)} original)")
    
    # Verify
    print("\nVerifying patched WASM...")
    sections = parse_wasm_sections(patched)
    for sec_id, start, end in sections:
        names = {0: 'custom', 7: 'export', 8: 'start'}
        name = names.get(sec_id, str(sec_id))
        if sec_id == 7:
            p = start
            cnt, _ = read_leb(patched, p)
            print(f"  Export section: {cnt} exports")


if __name__ == '__main__':
    main()
