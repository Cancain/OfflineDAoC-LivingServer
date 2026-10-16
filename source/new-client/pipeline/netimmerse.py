"""NetImmerse / Gamebryo NIF reader for the MMOEngine asset pipeline, written fresh for DAoC's files.

Reads every NIF version the DAoC client ships (3.x, 4.1.0.12, 4.2.1.0, 4.2.2.0, 10.1.0.0) by interpreting the
community NIF format description (spec/nif.xml, from the NifTools project, BSD licence) at run time: each block's
fields, version gates, conditions and arrays come from the spec, so all block types are covered. DAoC-specific
deviations from the spec are listed in QUIRKS and applied on top.

    from netimmerse import read_nif
    nif = read_nif(raw_bytes)
    nif.version, nif.blocks (list of Block), nif.roots
    block.type, block['Num Vertices'] or block.num_vertices, links are Block objects (or None)

    python netimmerse.py <file.nif | archive.npk> ...   parse and print a block summary
"""
import re, struct, sys
import xml.etree.ElementTree as ET
from pathlib import Path
import numpy as np

SPEC_PATH = Path(__file__).resolve().parent / 'spec' / 'nif.xml'


def version_number(text):
    """'4.2.1.0' -> 0x04020100. Two-digit minor parts like '3.03' mean 3.0.3 (NifTools convention)."""
    text = text.strip()
    if text == '3.03':
        return 0x03000300
    parts = [int(p) for p in text.split('.')] + [0, 0, 0]
    return (parts[0] << 24) | (parts[1] << 16) | (parts[2] << 8) | parts[3]


def norm(name):
    return re.sub(r'\W+', '_', name.strip().lower()).strip('_')


# ---------------------------------------------------------------- spec --------------------------------------------

class Field:
    __slots__ = ('name', 'key', 'type', 'template', 'arg', 'arr1', 'arr2', 'cond', 'ver1', 'ver2', 'vercond',
                 'userver', 'userver2')

    def __init__(self, el):
        a = el.attrib
        self.name = a['name']
        self.key = norm(a['name'])
        self.type = a['type']
        self.template = a.get('template')
        self.arg = a.get('arg')
        self.arr1 = a.get('arr1')
        self.arr2 = a.get('arr2')
        self.cond = a.get('cond')
        self.ver1 = version_number(a['ver1']) if 'ver1' in a else None
        self.ver2 = version_number(a['ver2']) if 'ver2' in a else None
        self.vercond = a.get('vercond')
        self.userver = int(a['userver']) if 'userver' in a else None
        self.userver2 = int(a['userver2']) if 'userver2' in a else None


class Spec:
    def __init__(self, path=SPEC_PATH):
        root = ET.parse(path).getroot()
        self.basics = {e.attrib['name'] for e in root.iter('basic')}
        self.storage = {}                                  # enum / bitflags name -> basic storage type
        for tag in ('enum', 'bitflags'):
            for e in root.iter(tag):
                self.storage[e.attrib['name']] = e.attrib['storage']
        self.compounds = {e.attrib['name']: [Field(f) for f in e.iter('add')] for e in root.iter('compound')}
        self.objects = {}
        self.parent = {}
        for e in root.iter('niobject'):
            self.objects[e.attrib['name']] = [Field(f) for f in e.iter('add')]
            self.parent[e.attrib['name']] = e.attrib.get('inherit')
        self._chains = {}

    def chain(self, type_name):
        """All fields of a block type, ancestors first."""
        if type_name not in self._chains:
            names = []
            t = type_name
            while t:
                names.append(t)
                t = self.parent.get(t)
            self._chains[type_name] = [f for t in reversed(names) for f in self.objects[t]]
        return self._chains[type_name]

    def is_a(self, type_name, ancestor):
        t = type_name
        while t:
            if t == ancestor:
                return True
            t = self.parent.get(t)
        return False


_SPEC = None


def spec():
    global _SPEC
    if _SPEC is None:
        _SPEC = Spec()
    return _SPEC


# ---------------------------------------------------------------- expressions -------------------------------------

_TOKEN = re.compile(r'\s*(&&|\|\||==|!=|>=|<=|[()!<>&|+\-*/]|[0-9]+\.[0-9]+(?:\.[0-9]+)*|0x[0-9a-fA-F]+|[0-9]+|[A-Za-z_][A-Za-z0-9_ ]*[A-Za-z0-9_])')
_PY_OPS = {'&&': ' and ', '||': ' or ', '!': ' not '}
_EXPR_CACHE = {}


def compile_expr(text):
    """Turn a spec condition into (python source, identifier list). Identifiers become _v[i] lookups."""
    if text in _EXPR_CACHE:
        return _EXPR_CACHE[text]
    out, idents, pos = [], [], 0
    text_s = text.replace('&gt;', '>').replace('&lt;', '<').replace('&amp;', '&')
    while pos < len(text_s):
        m = _TOKEN.match(text_s, pos)
        if not m:
            raise ValueError(f'cannot parse expression {text!r} at {text_s[pos:]!r}')
        tok = m.group(1)
        pos = m.end()
        if tok in _PY_OPS:
            out.append(_PY_OPS[tok])
        elif re.fullmatch(r'[0-9]+\.[0-9]+(?:\.[0-9]+)*', tok):
            out.append(str(version_number(tok)))
        elif re.fullmatch(r'0x[0-9a-fA-F]+|[0-9]+', tok):
            out.append(tok)
        elif re.match(r'[A-Za-z_]', tok):
            idents.append(tok.strip())
            out.append(f'_v[{len(idents) - 1}]')
        else:
            out.append(f' {tok} ')
    code = compile(''.join(out).strip(), text, 'eval')
    _EXPR_CACHE[text] = (code, idents)
    return code, idents


# ---------------------------------------------------------------- data model --------------------------------------

class Struct(dict):
    """Parsed compound / block: dict keyed by normalised field name, also readable as attributes."""
    type = None

    def __getattr__(self, k):
        try:
            return self[k]
        except KeyError:
            raise AttributeError(k)

    def __getitem__(self, k):
        return dict.__getitem__(self, norm(k) if ' ' in k or k[:1].isupper() else k)

    def get(self, k, default=None):
        try:
            return self[k]
        except KeyError:
            return default


class Block(Struct):
    def __init__(self, type_name, index):
        super().__init__()
        self.type = type_name
        self.index = index

    def __repr__(self):
        return f'<{self.type} #{self.index} {self.get("name", "")!r}>'

    __hash__ = object.__hash__
    __eq__ = object.__eq__


class Nif:
    def __init__(self):
        self.header_string = ''
        self.version = 0
        self.user_version = 0
        self.user_version2 = 0
        self.blocks = []
        self.roots = []

    def is_a(self, block, ancestor):
        return block is not None and spec().is_a(block.type, ancestor)

    def of_type(self, ancestor):
        return [b for b in self.blocks if self.is_a(b, ancestor)]


# DAoC files that deviate from nif.xml. Filled in as the corpus test finds them: {(type, field key): action}.
QUIRKS = {}

_FIXED = {'byte': ('B', 1), 'char': ('B', 1), 'ushort': ('H', 2), 'short': ('h', 2), 'uint': ('I', 4),
          'ulittle32': ('I', 4), 'int': ('i', 4), 'float': ('f', 4), 'Flags': ('H', 2), 'BlockTypeIndex': ('H', 2),
          'StringOffset': ('I', 4), 'StringIndex': ('I', 4), 'FileVersion': ('I', 4), 'Ref': ('i', 4),
          'Ptr': ('i', 4)}


class Reader:
    def __init__(self, raw, nif):
        self.raw = raw
        self.pos = 0
        self.nif = nif
        self.sp = spec()
        self._fmt_cache = {}

    # -- primitives
    def unpack(self, fmt, size):
        v = struct.unpack_from('<' + fmt, self.raw, self.pos)
        self.pos += size
        return v

    def line(self):
        end = self.raw.index(b'\n', self.pos)
        s = self.raw[self.pos:end].decode('latin1')
        self.pos = end + 1
        return s

    def sized_string(self):
        (n,) = self.unpack('I', 4)
        if n > 1 << 20:
            raise ValueError(f'string length {n} at {self.pos - 4}')
        s = self.raw[self.pos:self.pos + n].decode('latin1')
        self.pos += n
        return s

    def basic(self, t):
        if t == 'bool':
            if self.nif.version >= 0x04010001:
                return bool(self.unpack('B', 1)[0])
            return bool(self.unpack('I', 4)[0])
        if t in _FIXED:
            fmt, size = _FIXED[t]
            return self.unpack(fmt, size)[0]
        if t in ('HeaderString', 'LineString'):
            return self.line()
        raise ValueError(f'unhandled basic type {t}')

    # -- fixed-layout compounds (Vector3, TexCoord, Triangle, ...) read as numpy rows for speed
    def fixed_format(self, t):
        if t in self._fmt_cache:
            return self._fmt_cache[t]
        fmt = None
        if t in self.sp.compounds:
            parts = []
            for f in self.sp.compounds[t]:
                ft = self.sp.storage.get(f.type, f.type)
                if f.cond or f.vercond or f.arr2 or f.ver1 or f.ver2 or f.type == 'TEMPLATE' or ft not in _FIXED \
                        or (f.arr1 and not f.arr1.isdigit()):
                    parts = None
                    break
                parts.append(_FIXED[ft][0] * (int(f.arr1) if f.arr1 else 1))
            if parts:
                fmt = ''.join(parts)
        self._fmt_cache[t] = fmt
        return fmt

    # -- generic
    def value(self, t, template, arg, owner):
        t = self.sp.storage.get(t, t)
        if t == 'TEMPLATE':
            t = template
            t = self.sp.storage.get(t, t)
        if t in self.sp.basics or t in _FIXED:
            return self.basic(t)
        if t == 'string' or t == 'SizedString':
            return self.sized_string()
        if t == 'FilePath':                               # a string wrapper in every version DAoC uses
            return self.sized_string() if self.nif.version <= 0x14000005 else self.basic('StringIndex')
        if t in self.sp.compounds:
            return self.compound(t, template, arg)
        raise ValueError(f'unknown type {t}')

    def compound(self, t, template=None, arg=None):
        s = Struct()
        s.type = t
        self.fields(s, self.sp.compounds[t], template, arg)
        return s

    def eval(self, text, owner, arg):
        code, idents = compile_expr(text)
        vals = []
        for name in idents:
            key = norm(name)
            if name == 'Version':
                vals.append(self.nif.version)
            elif name == 'User Version':
                vals.append(self.nif.user_version)
            elif name == 'User Version 2':
                vals.append(self.nif.user_version2)
            elif name == 'ARG':
                vals.append(arg)
            elif key in owner:
                v = dict.__getitem__(owner, key)
                vals.append(v)
            elif name in self.sp.objects:                  # "NiPSysData" style type test
                vals.append(isinstance(owner, Block) and self.sp.is_a(owner.type, name))
            else:
                vals.append(0)                             # field absent in this version
        return eval(code, {'_v': vals})

    def active(self, f, owner, arg):
        v = self.nif.version
        if f.ver1 is not None and v < f.ver1:
            return False
        if f.ver2 is not None and v > f.ver2:
            return False
        if f.userver is not None and self.nif.user_version != f.userver:
            return False
        if f.userver2 is not None and self.nif.user_version2 != f.userver2:
            return False
        if f.vercond and not self.eval(f.vercond, owner, arg):
            return False
        if f.cond and not self.eval(f.cond, owner, arg):
            return False
        return True

    def fields(self, owner, flist, template, arg):
        for f in flist:
            if not self.active(f, owner, arg):
                continue
            quirk = QUIRKS.get((owner.type, f.key))
            if quirk == 'skip':
                continue
            ftemplate = template if f.template == 'TEMPLATE' else (f.template or template)
            farg = self.eval(f.arg, owner, arg) if f.arg else None
            if f.arr1:
                n = int(self.eval(f.arr1, owner, arg))
                if f.arr2:
                    n2 = self.eval(f.arr2, owner, arg)
                    if isinstance(n2, (list, np.ndarray)):          # jagged: one length per row
                        val = [self.array(f.type, int(k), ftemplate, farg, owner) for k in list(n2)[:n]]
                    else:
                        val = [self.array(f.type, int(n2), ftemplate, farg, owner) for _ in range(n)]
                else:
                    val = self.array(f.type, n, ftemplate, farg, owner)
            else:
                val = self.value(f.type, ftemplate, farg, owner)
            dict.__setitem__(owner, f.key, val)

    def array(self, t, n, template, arg, owner):
        if n < 0 or n > 10_000_000:
            raise ValueError(f'bad array length {n} for {t} at {self.pos}')
        st = self.sp.storage.get(t, t)
        if st == 'TEMPLATE':
            st = self.sp.storage.get(template, template)
        if st in _FIXED and st not in ('char',):
            fmt, size = _FIXED[st]
            arr = np.frombuffer(self.raw, dtype='<' + fmt, count=n, offset=self.pos).copy()
            self.pos += size * n
            return arr
        if st == 'char':
            s = self.raw[self.pos:self.pos + n]
            self.pos += n
            return s
        fmt = self.fixed_format(st)
        if fmt is not None:
            size = struct.calcsize('<' + fmt)
            dt = np.dtype([(f'f{i}', '<' + c) for i, c in enumerate(fmt)])
            rows = np.frombuffer(self.raw, dtype=dt, count=n, offset=self.pos)
            self.pos += size * n
            return np.stack([rows[name].astype(np.float64 if c == 'f' else np.int64)
                             for name, c in zip(dt.names, fmt)], axis=1) if n else np.zeros((0, len(fmt)))
        return [self.value(t, template, arg, owner) for _ in range(n)]


def read_nif(raw):
    nif = Nif()
    r = Reader(raw, nif)
    nif.header_string = r.line()
    vtext = nif.header_string.split('Version ')[-1]
    nif.version = version_number(vtext)
    if nif.version <= 0x03010000:
        raise NotImplementedError(f'NIF {vtext} (pre-3.3) not handled yet')
    (file_version,) = r.unpack('I', 4)
    if file_version != nif.version:
        raise ValueError(f'header says {vtext} but version field is {file_version:#x}')
    if nif.version >= 0x0A010000:
        (nif.user_version,) = r.unpack('I', 4)
    (num_blocks,) = r.unpack('I', 4)
    if nif.version >= 0x0A010000 and (nif.user_version >= 10 or (nif.user_version == 1 and nif.version != 0x0A020000)):
        (nif.user_version2,) = r.unpack('I', 4)
        raise NotImplementedError('export-info headers not used by DAoC')
    types_index = None
    if nif.version >= 0x0A000100:
        (ntypes,) = r.unpack('H', 2)
        type_names = [r.sized_string() for _ in range(ntypes)]
        idx = r.unpack(f'{num_blocks}H', 2 * num_blocks)
        types_index = [type_names[i & 0x7FFF] for i in idx]
        r.unpack('I', 4)                                   # unknown int 2
    sp = spec()
    for i in range(num_blocks):
        if types_index is None:
            type_name = r.sized_string()
        else:
            type_name = types_index[i]
            if nif.version < 0x0A020000:
                r.unpack('I', 4)                            # per-block zero marker in 10.0-10.1 files
        if type_name not in sp.objects:
            raise ValueError(f'block {i}: unknown type {type_name!r} at {r.pos}')
        block = Block(type_name, i)
        block.offset = r.pos
        r.fields(block, sp.chain(type_name), None, None)
        nif.blocks.append(block)
    (nroots,) = r.unpack('I', 4)
    roots = r.unpack(f'{nroots}i', 4 * nroots)
    nif.trailing = len(raw) - r.pos
    _link(nif)
    nif.roots = [nif.blocks[i] if 0 <= i < len(nif.blocks) else None for i in roots]
    return nif


def _link(nif):
    """Replace Ref / Ptr indices with Block objects, walking the spec to know which fields are links."""
    sp = spec()
    n = len(nif.blocks)

    def fix(owner, flist):
        for f in flist:
            if f.key not in owner:
                continue
            v = dict.__getitem__(owner, f.key)
            t = f.type
            if t in ('Ref', 'Ptr'):
                if isinstance(v, np.ndarray):
                    v = [nif.blocks[i] if 0 <= i < n else None for i in v.tolist()]
                elif isinstance(v, list):
                    v = [[nif.blocks[i] if 0 <= i < n else None for i in row] if isinstance(row, (list, np.ndarray))
                         else (nif.blocks[row] if 0 <= row < n else None) for row in v]
                else:
                    v = nif.blocks[v] if 0 <= v < n else None
                dict.__setitem__(owner, f.key, v)
            elif t in sp.compounds and t not in ('string', 'SizedString'):
                items = v if isinstance(v, list) else [v]
                for it in items:
                    if isinstance(it, Struct):
                        fix(it, sp.compounds[t])
                    elif isinstance(it, list):
                        for s in it:
                            if isinstance(s, Struct):
                                fix(s, sp.compounds[t])

    for b in nif.blocks:
        fix(b, sp.chain(b.type))


def main():
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    from daoc_mpk import read_mpk
    for p in sys.argv[1:]:
        items = read_mpk(p).items() if p.lower().endswith(('.npk', '.mpk')) else [(p, open(p, 'rb').read())]
        for name, raw in items:
            if not name.lower().endswith('.nif'):
                continue
            nif = read_nif(raw)
            print(f'{name}: {nif.header_string} blocks={len(nif.blocks)} trailing={nif.trailing}')
            for b in nif.blocks:
                extra = ''
                if 'num_vertices' in b:
                    extra = f' verts={b.num_vertices}'
                if 'file_name' in b:
                    extra = f' file={b.file_name!r}'
                print(f'  {b!r}{extra}')


if __name__ == '__main__':
    main()
