"""Byte-exact reproduction of PostgreSQL jsonb::text, so cmk.package_hash(jsonb) == package_hash() here.

jsonb output rules: object keys de-duplicated and sorted by (byte length, bytes); ", " and ": "
separators; strings escaped like escape_json() (\" \\ \b \f \n \r \t, other < 0x20 as \\u00xx).
Floats are refused on purpose (hash inputs carry only ints/strings/bools/null).
"""
from __future__ import annotations

import hashlib

_ESC = {'"': '\\"', "\\": "\\\\", "\b": "\\b", "\f": "\\f", "\n": "\\n", "\r": "\\r", "\t": "\\t"}


def _s(v: str) -> str:
    out = []
    for ch in v:
        if ch in _ESC:
            out.append(_ESC[ch])
        elif ord(ch) < 0x20:
            out.append("\\u%04x" % ord(ch))
        else:
            out.append(ch)
    return '"' + "".join(out) + '"'


def dumps(v) -> str:
    if v is None:
        return "null"
    if v is True:
        return "true"
    if v is False:
        return "false"
    if isinstance(v, int):
        return str(v)
    if isinstance(v, float):
        raise TypeError("canon: floats not allowed in hash inputs")
    if isinstance(v, str):
        return _s(v)
    if isinstance(v, (list, tuple)):
        return "[" + ", ".join(dumps(x) for x in v) + "]"
    if isinstance(v, dict):
        keys = sorted(v.keys(), key=lambda k: (len(k.encode()), k.encode()))
        return "{" + ", ".join(_s(k) + ": " + dumps(v[k]) for k in keys) + "}"
    raise TypeError(f"canon: unsupported type {type(v)}")


def sha256_canon(v) -> str:
    return hashlib.sha256(dumps(v).encode("utf-8")).hexdigest()
