# Stress test: simulate client disconnects (channel switching / page closing)
# Repeatedly open live-stream proxy + m3u8 manifest requests and abort mid-read.
import json, time, urllib.request, urllib.parse, sys

BASE = "http://localhost:8080"

def get(url, timeout=10):
    with urllib.request.urlopen(url, timeout=timeout) as r:
        return r.read()

def fetch_abort(url, read_bytes=2048, timeout=2):
    """Open stream, read a bit, then drop the connection (simulate client abort)."""
    req = urllib.request.Request(url)
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            r.read(read_bytes)
    except Exception:
        pass  # abort/timeout is the expected outcome
    return

def service_alive():
    try:
        get(BASE + "/api/status", 3)
        return True
    except Exception:
        return False

# 1. use a real live stream url (BBC from local intl.m3u, stable)
stream_target = "http://cdns.jp-primehome.com:8000/zhongying/live/playlist.m3u8?cid=cs15"
print(f"stream target: {stream_target[:80]}")

print(f"service alive before test: {service_alive()}")

# 2. abort hammering: m3u8 manifest + stream proxy, sequential + concurrent
aborted = 0
for i in range(20):
    m3u8_url = BASE + "/api/live/stream?url=" + urllib.parse.quote(stream_target, safe="")
    fetch_abort(m3u8_url, read_bytes=512, timeout=1)
    aborted += 1
    if i % 5 == 0:
        if not service_alive():
            print(f"CRASH after m3u8 abort round {i}")
            sys.exit(1)
print(f"m3u8 manifest aborts OK ({aborted} rounds), alive: {service_alive()}")

# concurrent stream aborts (simulate multiple windows / rapid switching)
import threading
def worker(k):
    fetch_abort(BASE + "/api/live/stream?url=" + urllib.parse.quote(stream_target, safe=""), read_bytes=1024, timeout=1)
    fetch_abort(BASE + "/api/live/stream?url=" + urllib.parse.quote(stream_target, safe=""), read_bytes=4096, timeout=1)

threads = []
for _ in range(10):
    t = threading.Thread(target=worker, args=(0,))
    t.start()
    threads.append(t)
for t in threads:
    t.join()

print(f"after concurrent aborts, alive: {service_alive()}")

# 3. repeated plain page/api calls after hammering
for i in range(5):
    try:
        get(BASE + "/", 3)
        get(BASE + "/api/status", 3)
    except Exception as e:
        print(f"FAIL after hammering: {e}")
        sys.exit(1)
print(f"final alive: {service_alive()}")
print("ALL PASS - no crash under client-abort hammering")
