"""The game's own icon in the Godot executables (owner 2026-10-15: "i still see the godot logo on the taskbar").
project.godot's icon reaches the game window once it runs, but Windows' grouped taskbar button, a pinned shortcut
and the moment before the window opens show the executable's own icon - Godot's. This writes godot/icon.ico (the
launcher's triquetra realm emblem) over the GODOT_ICON group of tools/godot_net/Godot_v4.7.2-stable_mono_win64.exe
(what the launcher starts) and its _console twin. A signed executable's signature would no longer match its
contents, so the old one is taken off first (an unsigned program runs the same). Backups: --backup=<dir>.

    python pipeline/set_exe_icon.py [--backup=<dir>]
"""
import ctypes, shutil, struct, sys
from ctypes import wintypes as W
from pathlib import Path
from assets_pipeline import ROOT

ICO = ROOT / 'godot/icon.ico'
EXES = [ROOT / 'tools/godot_net/Godot_v4.7.2-stable_mono_win64.exe',
        ROOT / 'tools/godot_net/Godot_v4.7.2-stable_mono_win64_console.exe']
GROUP = 'GODOT_ICON'
LANG = 1033
RT_ICON, RT_GROUP_ICON = 3, 14


def ico_images(data: bytes):
    _, kind, n = struct.unpack_from('<HHH', data, 0)
    assert kind == 1, 'not an .ico'
    out = []
    for i in range(n):
        w, h, colors, res, planes, bpp, size, off = struct.unpack_from('<BBBBHHII', data, 6 + 16 * i)
        out.append(((w, h, colors, res, planes, bpp, size), data[off:off + size]))
    return out


def strip_signature(exe: Path) -> None:
    import pefile
    pe = pefile.PE(str(exe), fast_load=True)
    d = pe.OPTIONAL_HEADER.DATA_DIRECTORY[4]
    if d.Size == 0:
        pe.close()
        return
    at, size = d.VirtualAddress, d.Size
    total = exe.stat().st_size
    d.VirtualAddress, d.Size = 0, 0
    data = bytearray(pe.write())
    pe.close()
    if at + size == total:                      # the certificate table ends the file: drop it
        del data[at:]
    exe.write_bytes(bytes(data))


def set_icon(exe: Path, images) -> None:
    k = ctypes.WinDLL('kernel32', use_last_error=True)
    k.BeginUpdateResourceW.restype = W.HANDLE
    k.BeginUpdateResourceW.argtypes = [W.LPCWSTR, W.BOOL]
    k.UpdateResourceW.argtypes = [W.HANDLE, W.LPVOID, W.LPVOID, W.WORD, W.LPVOID, W.DWORD]
    k.EndUpdateResourceW.argtypes = [W.HANDLE, W.BOOL]
    h = k.BeginUpdateResourceW(str(exe), False)
    if not h:
        raise OSError(ctypes.get_last_error(), 'BeginUpdateResource', str(exe))
    grp = struct.pack('<HHH', 0, 1, len(images))
    for i, (hdr, blob) in enumerate(images, 1):
        buf = ctypes.create_string_buffer(blob, len(blob))
        if not k.UpdateResourceW(h, RT_ICON, i, LANG, buf, len(blob)):
            raise OSError(ctypes.get_last_error(), 'UpdateResource icon', i)
        w, hh, colors, res, planes, bpp, size = hdr
        grp += struct.pack('<BBBBHHIH', w, hh, colors, res, planes, bpp, size, i)
    gbuf = ctypes.create_string_buffer(grp, len(grp))
    if not k.UpdateResourceW(h, RT_GROUP_ICON, ctypes.c_wchar_p(GROUP), LANG, gbuf, len(grp)):
        raise OSError(ctypes.get_last_error(), 'UpdateResource group')
    if not k.EndUpdateResourceW(h, False):
        raise OSError(ctypes.get_last_error(), 'EndUpdateResource', str(exe))


def main():
    backup = next((Path(a.split('=', 1)[1]) for a in sys.argv if a.startswith('--backup=')), None)
    images = ico_images(ICO.read_bytes())
    for exe in EXES:
        if backup:
            backup.mkdir(parents=True, exist_ok=True)
            if not (backup / exe.name).exists():
                shutil.copy2(exe, backup / exe.name)
        strip_signature(exe)
        set_icon(exe, images)
        print(exe.name, len(images), 'icon images')


if __name__ == '__main__':
    main()
