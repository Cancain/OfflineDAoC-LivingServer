"""Reader for DAoC MPAK archives (.mpk / .npk), written fresh for the MMOEngine asset pipeline.

    python daoc_mpk.py <archive.mpk>              list entries
    python daoc_mpk.py <archive.mpk> <name> > out  write one entry to stdout

Layout: "MPAK", one byte, a 16-byte header XOR-masked with its byte index (crc, directory size, name size,
entry count), a zlib stream holding the archive name, a zlib stream holding the directory (0x11C bytes per
entry: 256-byte name, then timestamps, sizes and offsets), then each entry's own zlib stream.
"""
import struct, sys, zlib

ENTRY_SIZE = 0x11C


class MpakArchive:
    def __init__(self, path):
        with open(path, 'rb') as f:
            self.raw = f.read()
        if self.raw[:4] != b'MPAK':
            raise ValueError(f'{path}: not an MPAK archive')
        header = bytes(byte ^ i for i, byte in enumerate(self.raw[5:21]))
        _crc, dir_size, name_size, self.count = struct.unpack('<4I', header)
        cursor = 21
        self.name = zlib.decompress(self.raw[cursor:cursor + name_size]).rstrip(b'\0').decode('latin1')
        cursor += name_size
        directory = zlib.decompress(self.raw[cursor:cursor + dir_size])
        self.data_start = cursor + dir_size
        self.entries = {}
        for i in range(self.count):
            rec = directory[i * ENTRY_SIZE:(i + 1) * ENTRY_SIZE]
            entry_name = rec[:256].split(b'\0', 1)[0].decode('latin1')
            # after the name: timestamp, two unknown words, unpacked size, offset, packed size, checksum
            fields = struct.unpack('<7I', rec[256:284])
            self.entries[entry_name.lower()] = (fields[4], fields[5], fields[3])

    def names(self):
        return list(self.entries)

    def read(self, name):
        offset, packed, _size = self.entries[name.lower()]
        start = self.data_start + offset
        return zlib.decompress(self.raw[start:start + packed])


def read_mpk(path):
    """Every entry of an archive as {lowercase name: bytes}."""
    archive = MpakArchive(path)
    return {name: archive.read(name) for name in archive.names()}


if __name__ == '__main__':
    arc = MpakArchive(sys.argv[1])
    if len(sys.argv) > 2:
        sys.stdout.buffer.write(arc.read(sys.argv[2]))
    else:
        for n in arc.names():
            print(n, arc.entries[n][2])
