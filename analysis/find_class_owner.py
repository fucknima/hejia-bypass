import struct,sys
d=open('zhihuiguanjia','rb').read()
TEXT_VM=0x100000000
def rd(addr,size):
    o=addr-TEXT_VM
    return d[o:o+size]
def cstr(addr):
    o=addr-TEXT_VM; e=d.find(b'\0',o); return d[o:e].decode('ascii','replace')
def u32(a): return struct.unpack('<I',rd(a,4))[0]
def ptr(a):
    v=struct.unpack('<Q',rd(a,8))[0]
    return v & 0xFFFFFFFF if v else 0
target=sys.argv[1]
foff=235595032; n=229504//8
out={}
for i in range(n):
    clsptr=ptr(TEXT_VM+foff+i*8)
    if not clsptr: continue
    ro=ptr(clsptr+32)
    if not ro: continue
    nameptr=ptr(ro+24)
    if not nameptr: continue
    try: cname=cstr(nameptr)
    except: continue
    ml=ptr(ro+32)
    if not ml: continue
    cnt=u32(ml+4); mo=ml+8
    for j in range(cnt):
        selp=ptr(mo+j*24)
        if not selp: continue
        try: s=cstr(selp)
        except: continue
        if target in s: out.setdefault(cname,set()).add(s)
for c,v in out.items(): print('%-40s %s'%(c,sorted(v)))
