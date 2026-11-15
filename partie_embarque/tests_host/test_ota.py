# Host-side tests of the remote firmware update logic (src/ota.py, US-46).
import hashlib
import io
import json
import os
import sys

import pytest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "src"))

import ota  # noqa: E402


@pytest.fixture
def board(tmp_path, monkeypatch):
    """The board's flash: a temporary directory holding the current firmware."""
    monkeypatch.chdir(tmp_path)
    for name in ("main.py", "net.py"):
        (tmp_path / name).write_text("# old %s\n" % name)
    return tmp_path


def order_for(files, version="1.3.0"):
    return {
        "version": version, "deploiement": 7, "url": "http://pc:3000/api/firmware/telechargement/abc",
        "fichiers": [{"nom": n, "taille": len(c), "sha256": hashlib.sha256(c).hexdigest()} for n, c in files.items()],
    }


def fetcher(files):
    def fetch(url):
        return io.BytesIO(files[url.rsplit("/", 1)[1]])
    return fetch


def test_install_replaces_files_and_keeps_backup(board):
    new = {"main.py": b"# new main\n" * 200, "net.py": b"# new net\n"}
    reports = []
    assert ota.install(order_for(new), fetcher(new), lambda s, m: reports.append(s))
    assert (board / "main.py").read_bytes() == new["main.py"]
    assert (board / "main.py.bak").read_text() == "# old main.py\n"
    assert not (board / "main.py.new").exists()
    assert reports == ["EN_COURS", "EN_COURS"]
    assert ota.pending() and ota.read_state()["version"] == "1.3.0"


def test_wrong_hash_changes_nothing(board):
    new = {"main.py": b"# new main\n", "net.py": b"# new net\n"}
    order = order_for(new)
    tampered = dict(new, **{"net.py": b"# bad net\n"})  # same length, different content
    reports = []
    assert not ota.install(order, fetcher(tampered), lambda s, m: reports.append((s, m)))
    assert (board / "main.py").read_text() == "# old main.py\n"   # first file was fine but not installed
    assert not any(p.name.endswith((".new", ".bak")) for p in board.iterdir())
    assert reports[-1][0] == "ECHEC" and "SHA-256" in reports[-1][1]
    assert not ota.pending()


def test_truncated_download_is_rejected(board):
    new = {"main.py": b"x" * 100}
    order = order_for(new)
    reports = []
    assert not ota.install(order, fetcher({"main.py": b"x" * 60}), lambda s, m: reports.append((s, m)))
    assert reports[-1][0] == "ECHEC" and "60 octets" in reports[-1][1]


@pytest.mark.parametrize("name", ["credentials.py", "boot.py", "../main.py", "x.mpy", None])
def test_forbidden_files_are_refused(name):
    order = {"version": "1", "url": "http://h", "fichiers": [{"nom": name, "taille": 1, "sha256": "0" * 64}]}
    with pytest.raises(ota.OTAError):
        ota.validate(order)


def test_order_validation():
    with pytest.raises(ota.OTAError):
        ota.validate({"version": "1", "url": "ftp://h", "fichiers": []})
    with pytest.raises(ota.OTAError):
        ota.validate({"version": "1", "url": "http://h", "fichiers": [{"nom": "main.py", "taille": 10 ** 6, "sha256": "0" * 64}]})


def test_boot_rollback_after_failed_boots(board):
    new = {"main.py": b"broken(\n"}
    assert ota.install(order_for(new), fetcher(new), lambda s, m: None)
    for _ in range(ota.MAX_BOOTS):
        assert ota.boot_check() == "pending"
    assert ota.boot_check() == "rollback"
    assert (board / "main.py").read_text() == "# old main.py\n"
    assert not ota.pending()
    reports = []
    ota.confirm(lambda s, m, d, v: reports.append((s, d, v)), "1.2.0")
    assert reports[0] == ("ECHEC", 7, "1.3.0") and reports[-1] == ("DEMARRE", None, "1.2.0")
    assert ota.read_state() is None


def test_confirm_after_successful_boot(board):
    new = {"main.py": b"# ok\n"}
    ota.install(order_for(new), fetcher(new), lambda s, m: None)
    assert ota.boot_check() == "pending"
    reports = []
    ota.confirm(lambda s, m, d, v: reports.append((s, d, v)), "1.3.0")
    assert reports == [("REUSSI", 7, "1.3.0"), ("DEMARRE", None, "1.3.0")]
    assert not (board / "main.py.bak").exists() and ota.read_state() is None


def test_no_update_just_announces_version(board):
    reports = []
    assert ota.boot_check() is None
    ota.confirm(lambda s, m, d, v: reports.append(s), "1.3.0")
    assert reports == ["DEMARRE"]
