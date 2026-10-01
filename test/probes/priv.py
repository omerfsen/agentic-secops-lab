# Runs in the sandbox and in the control; prints "key value" lines.
import ctypes, os, fcntl, time
libc = ctypes.CDLL(None, use_errno=True); libc.syscall.restype = ctypes.c_long
def status(pid):
    d = {}
    for line in open("/proc/%s/status" % pid):
        k, _, v = line.partition(":"); d[k] = v.split()
    return d
me, one = status("self"), status(1)
print("uid", ",".join(me["Uid"])); print("capeff", me["CapEff"][0]); print("nnp", me["NoNewPrivs"][0])
print("filters", me.get("Seccomp_filters", ["?"])[0]); print("pid1_filters", one.get("Seccomp_filters", ["?"])[0])
def call(name, nr, *a):
    r = libc.syscall(nr, *[ctypes.c_long(v) for v in a])
    print(name, "ok" if r >= 0 else os.strerror(ctypes.get_errno()).replace(" ", "_"))
# x86_64 numbers; the pod's RuntimeDefault profile allows both, so only OpenShell's filters can refuse them
call("setuid_self", 105, os.getuid())
call("memfd_create", 319, ctypes.cast(ctypes.c_char_p(b"x"), ctypes.c_void_p).value, 0)
# exec a real setuid-root binary and read its credentials while it blocks writing to a full pipe
if os.path.exists("/bin/mount"):
    st = os.stat("/bin/mount"); print("mount_mode", "%o" % (st.st_mode & 0o7777), "owner", st.st_uid)
    r, w = os.pipe(); fcntl.fcntl(w, 1031, 4096); os.write(w, b"x" * 4000)
    pid = os.fork()
    if pid == 0:
        os.dup2(w, 1); os.execv("/bin/mount", ["mount"])
    time.sleep(1)
    print("mount_uid", ",".join([l for l in open("/proc/%d/status" % pid) if l.startswith("Uid")][0].split()[1:]))
    os.close(w)
    while os.read(r, 65536): pass
    os.waitpid(pid, 0)
print("sudo", "present" if any(os.path.exists(p + "/sudo") for p in ("/bin", "/usr/bin", "/sbin", "/usr/sbin")) else "absent")
print("DONE")
