"""Téléchargement du jeu de données « Microsoft Azure Predictive Maintenance ».

100 machines, une année (2015) de télémesures horaires (tension, rotation, pression, vibration),
journaux d'erreurs, de maintenance et de pannes. Publié par Microsoft (guide « Predictive
Maintenance Modelling ») ; l'hébergement Azure d'origine n'existe plus, les fichiers sont pris sur un
miroir GitHub et vérifiés par leur empreinte de blob git (SHA-1 de « blob <taille>\\0<contenu> »).

Usage : python -m predimaint_ml.download [dossier]   (par défaut ml/data/raw)
"""
import hashlib
import sys
import urllib.request
from pathlib import Path

BASE = ("https://raw.githubusercontent.com/ashishpatel26/"
        "Predictive_Maintenance_using_Machine-Learning_Microsoft_Casestudy/master/data/")
FICHIERS = {
    "PdM_telemetry.csv": (79266228, "f44779fd9aeba2f6d993ff361100136f01173db5"),
    "PdM_failures.csv": (23574, "d24dc254b664eaf5faec584963fd17ffcd0220cd"),
    "PdM_maint.csv": (101616, "c5d79f07a6571bc3d2419bffcd685c6a5622230f"),
    "PdM_errors.csv": (125157, "39fdadd351388f48726fe95a879093883fc40ae7"),
    "PdM_machines.csv": (1481, "c8eeb6ad7be0fb5904978e17da7ba14694b44aa8"),
}
DEFAULT_DIR = Path(__file__).resolve().parent.parent / "data" / "raw"


def git_blob_sha1(data: bytes) -> str:
    return hashlib.sha1(b"blob %d\0" % len(data) + data).hexdigest()


def telecharger(dossier: Path = DEFAULT_DIR) -> Path:
    dossier.mkdir(parents=True, exist_ok=True)
    for nom, (taille, sha) in FICHIERS.items():
        cible = dossier / nom
        if cible.exists() and git_blob_sha1(cible.read_bytes()) == sha:
            print(f"{nom} : déjà présent")
            continue
        print(f"{nom} : téléchargement ({taille / 1e6:.1f} Mo)…")
        with urllib.request.urlopen(BASE + nom, timeout=120) as r:  # noqa: S310 (URL fixe, https)
            data = r.read(taille + 1)
        if len(data) != taille or git_blob_sha1(data) != sha:
            raise SystemExit(f"{nom} : empreinte incorrecte, fichier rejeté")
        cible.write_bytes(data)
    return dossier


if __name__ == "__main__":
    telecharger(Path(sys.argv[1]) if len(sys.argv) > 1 else DEFAULT_DIR)
