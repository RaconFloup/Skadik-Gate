#!/usr/bin/env python3
"""Convert .po translation files to .lmo format for LuCI"""
import struct
import re
import sys


def fnv1a(s):
    h = 0x811c9dc5
    for c in s.encode('utf-8'):
        h ^= c
        h = (h * 0x01000193) & 0xFFFFFFFF
    return h


def unescape_po(s):
    s = s.replace('\\n', '\n').replace('\\t', '\t')
    s = s.replace('\\"', '"').replace('\\\\', '\\')
    return s


def parse_po(filename):
    entries = {}
    with open(filename, 'r', encoding='utf-8') as f:
        lines = f.read().split('\n')

    i = 0
    while i < len(lines):
        line = lines[i].strip()
        if line.startswith('msgid '):
            msgid_parts = []
            val = line[6:].strip()
            if val.startswith('"') and val.endswith('"'):
                msgid_parts.append(val[1:-1])
            i += 1
            while i < len(lines):
                line = lines[i].strip()
                if line.startswith('"'):
                    msgid_parts.append(line.strip('"'))
                    i += 1
                elif line.startswith('msgstr'):
                    break
                else:
                    break
            msgid = unescape_po(''.join(msgid_parts))

            msgstr_parts = []
            if i < len(lines) and lines[i].strip().startswith('msgstr '):
                val = lines[i].strip()[7:].strip()
                if val.startswith('"') and val.endswith('"'):
                    msgstr_parts.append(val[1:-1])
                i += 1
                while i < len(lines):
                    line = lines[i].strip()
                    if line.startswith('"'):
                        msgstr_parts.append(line.strip('"'))
                        i += 1
                    else:
                        break
            else:
                i += 1
            msgstr = unescape_po(''.join(msgstr_parts))

            if msgid and msgstr:
                entries[msgid] = msgstr
        else:
            i += 1
    return entries


def build_lmo(entries, output_file):
    if not entries:
        with open(output_file, 'wb') as f:
            f.write(struct.pack('>II', 0, 0))
        return

    data = bytearray()
    str_table = {}

    all_strings = set()
    for msgid, msgstr in entries.items():
        all_strings.add(msgid)
        all_strings.add(msgstr)

    for s in sorted(all_strings, key=lambda x: len(x)):
        str_table[s] = len(data)
        data.extend(s.encode('utf-8'))
        data.append(0)
        while len(data) % 4 != 0:
            data.append(0)

    lmo_entries = []
    for msgid, msgstr in entries.items():
        lmo_entries.append({
            'key_id': str_table[msgid],
            'val_id': str_table[msgstr],
            'key_len': len(msgid.encode('utf-8')) + 1,
            'val_len': len(msgstr.encode('utf-8')) + 1,
            'hash': fnv1a(msgid),
        })

    lmo_entries.sort(key=lambda e: e['hash'])

    with open(output_file, 'wb') as f:
        f.write(struct.pack('>II', 0, len(lmo_entries)))
        for e in lmo_entries:
            f.write(struct.pack('>IIIII', e['key_id'], e['val_id'],
                                e['key_len'], e['val_len'], e['hash']))
        f.write(bytes(data))


if __name__ == '__main__':
    if len(sys.argv) < 3:
        print(f"Usage: {sys.argv[0]} input.po output.lmo")
        sys.exit(1)
    entries = parse_po(sys.argv[1])
    build_lmo(entries, sys.argv[2])
    print(f"  {len(entries)} entries -> {sys.argv[2]}")
