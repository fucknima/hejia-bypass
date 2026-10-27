#!/usr/bin/env python3
"""
给已解密的 App 打 Info.plist 补丁：
  开启文件共享，让 HeJiaTool 日志出现在「文件」App 里

用法:
    python3 info_plist_patch.py /path/to/Payload/zhihuiguanjia.app
"""
import plistlib, sys, os, shutil

def patch(app_dir):
    p = os.path.join(app_dir, 'Info.plist')
    if not os.path.exists(p):
        print(f'❌ 找不到 {p}'); return 1

    with open(p, 'rb') as f:
        data = f.read()

    fmt = plistlib.FMT_BINARY
    try:
        pl = plistlib.loads(data, fmt=plistlib.FMT_BINARY)
    except Exception:
        pl = plistlib.loads(data, fmt=plistlib.FMT_XML)
        fmt = plistlib.FMT_XML

    before = {k: pl.get(k) for k in
              ('UIFileSharingEnabled', 'LSSupportsOpeningDocumentsInPlace')}

    pl['UIFileSharingEnabled'] = True
    pl['LSSupportsOpeningDocumentsInPlace'] = True

    shutil.copy2(p, p + '.bak')
    with open(p, 'wb') as f:
        plistlib.dump(pl, f, fmt=fmt)

    print('✅ Info.plist 已补丁：')
    for k in ('UIFileSharingEnabled', 'LSSupportsOpeningDocumentsInPlace'):
        print(f'   {k}: {before[k]} -> True')
    print(f'   备份: {p}.bak')
    return 0

if __name__ == '__main__':
    if len(sys.argv) < 2:
        print(__doc__); sys.exit(1)
    sys.exit(patch(sys.argv[1]))
