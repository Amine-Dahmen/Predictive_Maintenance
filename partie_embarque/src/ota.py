# Remote firmware update (US-46).
#
# The backend publishes an order on usine/machines/<MACHINE_CODE>/ota (only this
# board can read it, only the backend can write it: broker ACL):
#   {"version": "1.3.0", "deploiement": 12, "url": "http://<pc>:3000/api/firmware/telechargement/<token>",
#    "fichiers": [{"nom": "main.py", "taille": 5120, "sha256": "..."}, ...]}
#
#   1. every file is downloaded to <name>.new and its SHA-256 checked against the
#      order (a modified or truncated file is rejected: nothing is replaced)
#   2. only then: <name> -> <name>.bak, <name>.new -> <name>
#   3. ota_state.json records the pending version and the board reboots
#   4. boot.py counts the boots of a pending version; after MAX_BOOTS without
#      confirmation it restores the .bak files (old version)
#   5. once the new firmware is connected to MQTT, confirm() reports REUSSI and
#      removes the .bak files
#
# Progress is published on usine/machines/<MACHINE_CODE>/ota/statut.
# File access and HTTP are injected so the logic runs in host tests (tests_host/test_ota.py).

import json
import os

try:
    import hashlib
except ImportError:  # pragma: no cover
    import uhashlib as hashlib
try:
    import binascii
except ImportError:  # pragma: no cover
    import ubinascii as binascii

# Never sent over the air: credentials.py (Wi-Fi / MQTT secrets) and boot.py (rollback)
ALLOWED = ("main.py", "config.py", "net.py", "sensors.py", "alerts.py", "buffer.py", "ota.py")
MAX_FILE = 64 * 1024
STATE = "ota_state.json"
MAX_BOOTS = 3
CHUNK = 1024


class OTAError(Exception):
    pass


def validate(order):
    """Checks an order and returns (version, deploiement, url, files)."""
    if not isinstance(order, dict):
        raise OTAError("ordre invalide")
    version = order.get("version")
    url = order.get("url")
    files = order.get("fichiers")
    if not isinstance(version, str) or not 0 < len(version) <= 40:
        raise OTAError("version invalide")
    if not isinstance(url, str) or not (url.startswith("http://") or url.startswith("https://")):
        raise OTAError("url invalide")
    if not isinstance(files, list) or not files:
        raise OTAError("aucun fichier")
    seen = []
    for f in files:
        name = f.get("nom") if isinstance(f, dict) else None
        if name not in ALLOWED or name in seen:
            raise OTAError("fichier non autorise: %r" % (name,))
        size = f.get("taille")
        digest = f.get("sha256")
        if not isinstance(size, int) or not 0 < size <= MAX_FILE:
            raise OTAError("taille invalide: %s" % name)
        if not isinstance(digest, str) or len(digest) != 64:
            raise OTAError("sha256 invalide: %s" % name)
        seen.append(name)
    return version, order.get("deploiement"), url.rstrip("/"), files


def _exists(path):
    try:
        os.stat(path)
        return True
    except OSError:
        return False


def _remove(path):
    try:
        os.remove(path)
    except OSError:
        pass


def download(url, name, size, digest, fetch):
    """Streams url/name into name.new while hashing it. fetch(url) returns an
    object with read(n) and close(). Raises OTAError if the file is not exactly
    the one announced in the order."""
    h = hashlib.sha256()
    total = 0
    stream = fetch(url + "/" + name)
    try:
        with open(name + ".new", "wb") as out:
            while True:
                chunk = stream.read(CHUNK)
                if not chunk:
                    break
                total += len(chunk)
                if total > size:
                    raise OTAError("%s: plus long que prevu" % name)
                h.update(chunk)
                out.write(chunk)
    finally:
        stream.close()
    if total != size:
        raise OTAError("%s: %d octets recus sur %d" % (name, total, size))
    if binascii.hexlify(h.digest()).decode() != digest.lower():
        raise OTAError("%s: empreinte SHA-256 incorrecte" % name)


def install(order, fetch, report):
    """Downloads and installs an order. report(statut, message) publishes progress.
    Returns True when the files were replaced (the caller must then reboot)."""
    try:
        version, deploiement, url, files = validate(order)
    except OTAError as e:
        report("ECHEC", str(e))
        return False
    report("EN_COURS", "telechargement de %d fichier(s)" % len(files))
    names = [f["nom"] for f in files]
    try:
        for f in files:
            download(url, f["nom"], f["taille"], f["sha256"], fetch)
    except Exception as e:
        for n in names:
            _remove(n + ".new")
        report("ECHEC", str(e))
        return False

    # Every file is verified: swap them, keeping the previous version as .bak
    for n in names:
        _remove(n + ".bak")
        if _exists(n):
            os.rename(n, n + ".bak")
        os.rename(n + ".new", n)
    write_state({"version": version, "deploiement": deploiement, "fichiers": names, "boots": 0})
    report("EN_COURS", "fichiers installes, redemarrage")
    return True


def read_state():
    try:
        with open(STATE) as f:
            return json.load(f)
    except (OSError, ValueError):
        return None


def write_state(state):
    with open(STATE, "w") as f:
        json.dump(state, f)


def pending():
    s = read_state()
    return s is not None and "version" in s and not s.get("rollback")


def boot_check():
    """Called by boot.py at every boot. Returns 'rollback' when the old files
    were restored, 'pending' while a new version waits for confirmation."""
    s = read_state()
    if s is None or "version" not in s:
        return None
    if s.get("rollback"):
        return "rollback"
    s["boots"] = s.get("boots", 0) + 1
    if s["boots"] > MAX_BOOTS:
        for n in s.get("fichiers", []):
            if _exists(n + ".bak"):
                _remove(n)
                os.rename(n + ".bak", n)
        s["rollback"] = True
        write_state(s)
        return "rollback"
    write_state(s)
    return "pending"


def confirm(report, current_version):
    """Called once connected. Reports the result of a previous update (if any)
    and always announces the running version."""
    s = read_state()
    if s is not None and "version" in s:
        if s.get("rollback"):
            report("ECHEC", "la version %s n'a pas demarre: retour a la version precedente" % s["version"],
                   s.get("deploiement"), s["version"])
        else:
            report("REUSSI", "version %s en service" % current_version, s.get("deploiement"), current_version)
            for n in s.get("fichiers", []):
                _remove(n + ".bak")
        _remove(STATE)
    report("DEMARRE", None, None, current_version)


def http_fetch(url):  # pragma: no cover - MicroPython only
    try:
        import requests
    except ImportError:
        import urequests as requests
    r = requests.get(url, stream=True)
    if r.status_code != 200:
        r.close()
        raise OTAError("HTTP %d" % r.status_code)
    return _Body(r)


class _Body:  # pragma: no cover - MicroPython only
    def __init__(self, r):
        self.r = r

    def read(self, n):
        return self.r.raw.read(n)

    def close(self):
        self.r.close()
