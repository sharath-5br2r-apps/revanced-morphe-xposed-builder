#!/usr/bin/env python3
"""Cloudflare fetch helper with curl_cffi impersonation and solver fallback."""
import os
import time
import json
import os
import sys
import time
import urllib.request
import urllib.error
import urllib.parse

# ---------------------------------------------------------------------------
# Optional dependency: curl_cffi
# ---------------------------------------------------------------------------
try:
    from curl_cffi import requests
    from curl_cffi.requests import Response
    cffi_requests = requests
    _HAS_CFFI = True
except ImportError:
    # Exit 2: curl_cffi not installed, caller should fall back to curl/solver
    sys.exit(2)

MAX_RETRIES = 2
_TRAWL_READY = set()
DEFAULT_UA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/133.0.0.0 Safari/537.36"

def is_challenge(status_code: int, text: str, headers: dict = None) -> bool:
    if status_code in (403, 503):
        return True
    if headers and "cf-mitigated" in headers:
        return True
    lower = (text or "").lower()
    return any(phrase in lower for phrase in (
        "just a moment...",
        "attention required!",
        "please wait... | cloudflare",
        "verify you are human",
        "turnstile",
        "_cf_chl_opt",
        "challenges.cloudflare.com",
        "__cf_chl_",
        "/cdn-cgi/challenge-platform/",
        "challenges.cloudflare.com",
    ))


def acquire_lock(lock_file: str):
    """Acquire an exclusive file lock to serialise concurrent cf_get calls."""
    try:
        os.makedirs(os.path.dirname(os.path.abspath(lock_file)), exist_ok=True)
        fd = open(lock_file, "w")
        try:
            import fcntl
            fcntl.flock(fd, fcntl.LOCK_EX)
        except ImportError:
            try:
                import msvcrt
                msvcrt.locking(fd.fileno(), msvcrt.LK_LOCK, 1)
            except Exception:
                pass
        # Keep fd alive for the process lifetime — OS releases on exit.
        return fd
    except OSError:
        return None


def load_cookies(cookie_file: str, session) -> None:
    """Load a Netscape cookie file into a curl_cffi Session."""
    if not cookie_file or not os.path.isfile(cookie_file):
        return
    try:
        with open(cookie_file, "r", encoding="utf-8", errors="ignore") as f:
            for line in f:
                parts = line.strip().split("\t")
                if len(parts) >= 7 and not line.startswith("#"):
                    session.cookies.set(parts[5], parts[6], domain=parts[0])
    except Exception:
        pass


def cookies_to_header_str(session) -> str:
    """Return a 'name=value; ...' string from all cookies in the session jar."""
    try:
        return "; ".join(
            f"{c.name}={c.value}"
            for c in session.cookies.jar
            if c.name and c.value
        )
    except Exception:
        return ""


def dump_cookies_to_file(session, cookie_file: str) -> None:
    """Write all session cookies back to the Netscape cookie file.

    Format per line (tab-separated):
        domain  include_subdomains  path  secure  expires  name  value
    """
    if not cookie_file:
        return
    try:
        lines = ["# Netscape HTTP Cookie File\n"]
        for c in session.cookies.jar:
            domain  = c.domain or ""
            flag    = "TRUE" if domain.startswith(".") else "FALSE"
            path    = c.path or "/"
            secure  = "TRUE" if c.secure else "FALSE"
            # expires may be None for session cookies — use 0 in that case
            expires = str(int(c.expires)) if c.expires else "0"
            name    = c.name  or ""
            value   = c.value or ""
            lines.append(
                f"{domain}\t{flag}\t{path}\t{secure}\t{expires}\t{name}\t{value}\n"
            )
        with open(cookie_file, "w", encoding="utf-8") as f:
            f.writelines(lines)
    except Exception:
        pass


def ok(html: str, cf_cookies: str = "", user_agent: str = "") -> None:
    """Write the success JSON envelope and exit 0."""
    sys.stdout.write(json.dumps({
        "html": html,
        "cf_cookies": cf_cookies,
        "user_agent": user_agent or DEFAULT_UA,
    }))
    sys.exit(0)



# ---------------------------------------------------------------------------
# Method 1: plain urllib fallback (no impersonation)
# ---------------------------------------------------------------------------

def fallback_get(url: str, cookie_file: str) -> None:
    """Plain HTTP GET using stdlib urllib, mirroring _fallback_get in utils.sh."""
    try:
        req = urllib.request.Request(url, headers={"User-Agent": DEFAULT_UA})
        with urllib.request.urlopen(req, timeout=10) as resp:
            text = resp.read().decode("utf-8", errors="replace")
        if text and not is_challenge(resp.status, text):
            ok(text, cf_cookies="", user_agent=DEFAULT_UA)
    except Exception:
        pass


# ---------------------------------------------------------------------------
# Method 2: Trawl / 8191 solver
# ---------------------------------------------------------------------------

def trawl_get(url: str, referer: str = "") -> None:
    """POST to a Trawl/8191 solver, mirroring _trawl_get in utils.sh."""
    trawl_base = (
        os.environ.get("TRAWL_URL") or
        ""
    ).rstrip("/")
    if not trawl_base:
        return

    # Keep readiness polling inside the Python solver so every caller shares
    # the same health/retry behavior and utils.sh has no duplicate trawl code.
    if trawl_base not in _TRAWL_READY:
        health_url = trawl_base + "/health"
        ready = False
        for _ in range(30):
            try:
                with urllib.request.urlopen(health_url, timeout=3) as health:
                    if 200 <= health.status < 500:
                        ready = True
                        break
            except Exception:
                pass
            time.sleep(3)
        if not ready:
            return
        _TRAWL_READY.add(trawl_base)

    solver_url = trawl_base + "/scrape"
    payload: dict = {"url": url, "maxTimeout": 60000, "skipHttp": True}
    if referer:
        payload["headers"] = {"Referer": referer}

    for attempt in range(1, MAX_RETRIES + 1):
        try:
            data = json.dumps(payload).encode()
            req = urllib.request.Request(
                solver_url, data=data,
                headers={"Content-Type": "application/json"},
                method="POST",
            )
            with urllib.request.urlopen(req, timeout=15) as resp:
                body = resp.read().decode("utf-8", errors="replace")
            result = json.loads(body)
            status = result.get("statusCode", 0)
            if isinstance(status, int) and 100 <= status < 400:
                html = result.get("html") or ""
                if html and not is_challenge(status, html):
                    ua = result.get("userAgent") or DEFAULT_UA
                    cookies = "; ".join(
                        f"{c['name']}={c['value']}"
                        for c in result.get("cookies", [])
                        if "name" in c and "value" in c
                    )
                    ok(html, cf_cookies=cookies, user_agent=ua)
        except Exception:
            pass
        if attempt < MAX_RETRIES:
            time.sleep(2)


# ---------------------------------------------------------------------------
# Method 3: curl_cffi browser impersonation
# ---------------------------------------------------------------------------

def cf_get(url: str, cookie_file: str) -> None:
    """Unified Python GET using curl_cffi browser impersonation when available."""
    if not _HAS_CFFI:
        return

    impersonate_targets = [
        "safari180",
        "chrome131_android",
        "firefox133",
        "safari170",
        "chrome131",
        "chrome124",
        "chrome120",
        "chrome110",
    ]

    for imp in impersonate_targets:
        try:
            s = cffi_requests.Session(impersonate=imp)
            load_cookies(cookie_file, s)
            resp = s.get(url, timeout=15, allow_redirects=True)
            if is_challenge(resp.status_code, resp.text):
                sys.exit(1)
            if resp.status_code == 200 and resp.text:
                cf_cookies = cookies_to_header_str(s)
                dump_cookies_to_file(s, cookie_file)
                ok(resp.text, cf_cookies=cf_cookies, user_agent=DEFAULT_UA)
        except Exception:
            continue



# ---------------------------------------------------------------------------
# Method 4: cf-bypasser (CFB) sidecar
# ---------------------------------------------------------------------------

def cfb_get(url: str, referer: str = "") -> None:
    """GET via cf-bypasser sidecar, mirroring _cfb_get in utils.sh."""
    cfb_base = (
        os.environ.get("CFB_URL") or
        ""
    ).rstrip("/")
    if not cfb_base:
        return

    solver_url = cfb_base + "/html"
    params = urllib.parse.urlencode({"url": url})
    full_url = f"{solver_url}?{params}"

    for attempt in range(1, MAX_RETRIES + 1):
        try:
            req = urllib.request.Request(full_url, headers={"User-Agent": DEFAULT_UA})
            with urllib.request.urlopen(req, timeout=15) as resp:
                html = resp.read().decode("utf-8", errors="replace")
                headers = {k.lower(): v for k, v in resp.headers.items()}
            if resp.status == 200 and html and not is_challenge(resp.status, html):
                cf_cookies = headers.get("x-cf-bypasser-cookies", "").strip()
                ua = headers.get("x-cf-bypasser-user-agent", "").strip() or DEFAULT_UA
                ok(html, cf_cookies=cf_cookies, user_agent=ua)
        except Exception:
            pass
        if attempt < MAX_RETRIES:
            time.sleep(2)


# ---------------------------------------------------------------------------
# Method 5: FlareSolverr
# ---------------------------------------------------------------------------

def fs_get(url: str, referer: str = "") -> None:
    """POST to FlareSolverr, mirroring _fs_get in utils.sh."""
    fs_base = (
        os.environ.get("FS_URL") or
        os.environ.get("FLARESOLVERR_URL") or
        os.environ.get("CF_BYPASS_SOLVER_FS_URL") or
        ""
    ).rstrip("/")
    if not fs_base:
        return

    solver_url = fs_base + "/v1"
    payload: dict = {"cmd": "request.get", "url": url, "maxTimeout": 15000}
    if referer:
        payload["headers"] = {"Referer": referer}

    for attempt in range(1, MAX_RETRIES + 1):
        try:
            data = json.dumps(payload).encode()
            req = urllib.request.Request(
                solver_url, data=data,
                headers={"Content-Type": "application/json"},
                method="POST",
            )
            with urllib.request.urlopen(req, timeout=20) as resp:
                body = resp.read().decode("utf-8", errors="replace")
            result = json.loads(body)
            if result.get("status") == "ok":
                html = result.get("solution", {}).get("response") or ""
                if html and not is_challenge(200, html):
                    cookies = "; ".join(
                        f"{c['name']}={c['value']}"
                        for c in result.get("solution", {}).get("cookies", [])
                        if "name" in c and "value" in c
                    )
                    ua = result.get("solution", {}).get("userAgent") or DEFAULT_UA
                    ok(html, cf_cookies=cookies, user_agent=ua)
        except Exception:
            pass
        if attempt < MAX_RETRIES:
            time.sleep(2)


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------
    # Ensure standard aliases are prioritized
    if "chrome" not in targets:
        targets.insert(0, "chrome")
    if "safari" not in targets:
        targets.append("safari")

    return targets[:8]

def load_cookies(session, cookie_file: str):
    if not cookie_file or not os.path.isfile(cookie_file):
        return
    try:
        with open(cookie_file, "r", encoding="utf-8", errors="ignore") as f:
            for line in f:
                parts = line.strip().split("\t")
                if len(parts) >= 7 and not line.startswith("#"):
                    session.cookies.set(parts[5], parts[6], domain=parts[0], path=parts[2])
    except Exception:
        pass

    # Check companion user agent file if available
    temp_dir = os.path.dirname(os.path.abspath(cookie_file))
    ua_path = os.path.join(temp_dir, "cf_ua.txt")
    if os.path.isfile(ua_path):
        try:
            with open(ua_path, "r", encoding="utf-8", errors="ignore") as f:
                ua = f.read().strip()
                if ua:
                    session.headers["User-Agent"] = ua
        except Exception:
            pass

def save_cookies(session, cookie_file: str, user_agent: str = ""):
    if not cookie_file:
        return
    try:
        temp_dir = os.path.dirname(os.path.abspath(cookie_file))
        os.makedirs(temp_dir, exist_ok=True)
        with open(cookie_file, "w", encoding="utf-8") as f:
            f.write("# Netscape HTTP Cookie File\n")
            for c in session.cookies:
                domain = getattr(c, "domain", "") or ""
                path = getattr(c, "path", "/") or "/"
                secure = "TRUE" if getattr(c, "secure", False) else "FALSE"
                expires = str(int(getattr(c, "expires", 0) or 0))
                name = getattr(c, "name", "")
                val = getattr(c, "value", "")
                f.write(f"{domain}\tTRUE\t{path}\t{secure}\t{expires}\t{name}\t{val}\n")

        if user_agent:
            with open(os.path.join(temp_dir, "cf_ua.txt"), "w", encoding="utf-8") as f:
                f.write(user_agent)

        cookie_header = "; ".join(f"{c.name}={c.value}" for c in session.cookies)
        if cookie_header:
            with open(os.path.join(temp_dir, "cf_cookies.txt"), "w", encoding="utf-8") as f:
                f.write(cookie_header)
    except Exception:
        pass

def solve_challenge(url: str, session) -> tuple[bool, str]:
    solver_url = os.getenv("CFB_URL", "http://localhost:8000").rstrip("/")
    try:
        resp = requests.get(f"{solver_url}/cookies", params={"url": url}, timeout=60)
        if resp.status_code == 200:
            data = resp.json()
            cookies = data.get("cookies", {})
            user_agent = data.get("user_agent", "")
            if isinstance(cookies, dict):
                for k, v in cookies.items():
                    session.cookies.set(k, v)
            elif isinstance(cookies, list):
                for c in cookies:
                    if isinstance(c, dict) and "name" in c and "value" in c:
                        session.cookies.set(c["name"], c["value"])

            if user_agent:
                session.headers["User-Agent"] = user_agent
            return True, user_agent
    except Exception as e:
        sys.stderr.write(f"[cf_get] Solver error connecting to {solver_url}: {e}\n")
    return False, ""

def fetch_from_solver_html(url: str) -> str | None:
    solver_url = os.getenv("CFB_URL", "http://localhost:8000").rstrip("/")
    try:
        resp = requests.get(f"{solver_url}/html", params={"url": url}, timeout=60)
        if resp.status_code == 200 and resp.text:
            if not is_challenge(resp.status_code, resp.text, getattr(resp, "headers", None)):
                return resp.text
    except Exception:
        pass
    return None

def download_file(url: str, dest_path: str, referer: str = "", cookie_file: str = "") -> bool:
    os.makedirs(os.path.dirname(os.path.abspath(dest_path)), exist_ok=True)
    temp_dest = f"{dest_path}.part"
    impersonate_targets = get_impersonate_targets()

    for imp in impersonate_targets:
        try:
            s = requests.Session(impersonate=imp)
            load_cookies(s, cookie_file)
            headers = {}
            if referer:
                headers["Referer"] = referer

            resp = s.get(url, headers=headers, timeout=(10, 300), stream=True, allow_redirects=True)
            if is_challenge(resp.status_code, "", getattr(resp, "headers", None)):
                solved, ua = solve_challenge(url, s)
                if solved:
                    save_cookies(s, cookie_file, ua)
                    resp = s.get(url, headers=headers, timeout=(10, 300), stream=True, allow_redirects=True)

            if resp.status_code == 200:
                with open(temp_dest, "wb") as f:
                    for chunk in resp.iter_content(chunk_size=1048576):
                        if chunk:
                            f.write(chunk)
                if os.path.isfile(temp_dest) and os.path.getsize(temp_dest) > 0:
                    if os.path.isfile(dest_path):
                        os.remove(dest_path)
                    os.rename(temp_dest, dest_path)
                    save_cookies(s, cookie_file)
                    return True
        except Exception as e:
            sys.stderr.write(f"[cf_get] Download error with target {imp}: {e}\n")
            if os.path.isfile(temp_dest):
                try:
                    os.remove(temp_dest)
                except Exception:
                    pass
            continue

    return False

def main():
    if len(sys.argv) < 2:
        sys.exit(2)

    url         = sys.argv[1]
    # Handle download subcommand: cf_get.py download <url> <dest> [referer] [cookie_file]
    if sys.argv[1] == "download":
        if len(sys.argv) < 4:
            sys.exit(2)
        dl_url = sys.argv[2]
        dest = sys.argv[3]
        referer = sys.argv[4] if len(sys.argv) > 4 else ""
        cookie_file = sys.argv[5] if len(sys.argv) > 5 else ""
        success = download_file(dl_url, dest, referer, cookie_file)
        sys.exit(0 if success else 1)

    url = sys.argv[1]
    cookie_file = sys.argv[2] if len(sys.argv) > 2 else ""
    lock_file   = sys.argv[3] if len(sys.argv) > 3 else ""
    referer     = sys.argv[4] if len(sys.argv) > 4 else ""

    # Serialise concurrent requests via an exclusive file lock
    _lock_fd = acquire_lock(lock_file) if lock_file else None

    # Try each method in order — each calls ok() and sys.exit(0) on success
    fallback_get(url, cookie_file)

    trawl_get(url, referer)

    cf_get(url, cookie_file)

    cfb_get(url, referer)

    fs_get(url, referer)

    sys.exit(1)


if __name__ == "__main__":
    main()
