import hashlib, json, struct, sys, pathlib

def entries(path):
    with open(path, "rb") as f:
        n = struct.unpack("<Q", f.read(8))[0]
        header = json.loads(f.read(n))
    base = 8 + n
    out = {}
    for name, meta in header.items():
        if name == "__metadata__":
            continue
        s, e = meta["data_offsets"]
        out[name] = (meta["dtype"], tuple(meta["shape"]), base + s, base + e)
    return out

def tensor_digest(path, start, end):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        f.seek(start)
        left = end - start
        while left:
            chunk = f.read(min(left, 1 << 22))
            if not chunk:
                break
            h.update(chunk)
            left -= len(chunk)
    return h.hexdigest()

def compare(a, b):
    ea, eb = entries(a), entries(b)
    if set(ea) != set(eb):
        print(f"  TENSOR SET DIFFERS: only in old {sorted(set(ea)-set(eb))[:5]}, "
              f"only in new {sorted(set(eb)-set(ea))[:5]}")
        return False
    bad = []
    for name in sorted(ea):
        da, sa, s1, e1 = ea[name]
        db, sb, s2, e2 = eb[name]
        if (da, sa) != (db, sb):
            bad.append(f"{name}: dtype/shape {da}{sa} vs {db}{sb}")
            continue
        if tensor_digest(a, s1, e1) != tensor_digest(b, s2, e2):
            bad.append(f"{name}: bytes differ")
    print(f"  {len(ea)} tensors, {len(bad)} differing")
    for line in bad[:10]:
        print(f"    {line}")
    return not bad

ok = True
old, new = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
for rel in sorted(p.relative_to(old) for p in old.rglob("*.safetensors")):
    print(f"{rel}:")
    ok &= compare(old / rel, new / rel)
print("CONTENT IDENTICAL" if ok else "CONTENT DIFFERS")
