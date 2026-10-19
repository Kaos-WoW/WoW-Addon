# -*- coding: utf-8 -*-
"""
Baut das Zip zum Weitergeben:  ..\\Fairshare-releases\\Fairshare-<Version>.zip

Der Inhalt kommt standardmaessig aus dem letzten COMMIT (git archive).
Mit dem Schalter --aktuell wird direkt der aktuelle Arbeitsordner gepackt.
Dazu kommt LIESMICH.txt (liegt neben diesem Skript).

Aufruf:
  python release/bauen.py            (aus letztem Git-Commit)
  python release/bauen.py --aktuell  (aus aktuellem Arbeitsordner)
"""
import os
import re
import subprocess
import sys
import zipfile

HIER = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HIER)
AUSGABE = os.path.join(os.path.dirname(REPO), "Fairshare-releases")
aktuell = "--aktuell" in sys.argv or "--arbeitsordner" in sys.argv or "-a" in sys.argv

toc = open(os.path.join(REPO, "Fairshare", "Fairshare.toc"), encoding="utf-8").read()
version = re.search(r"^## Version:\s*(\S+)", toc, re.M).group(1)

os.makedirs(AUSGABE, exist_ok=True)
ziel = os.path.join(AUSGABE, "Fairshare-%s.zip" % version)
if os.path.exists(ziel):
    os.remove(ziel)

if aktuell:
    with zipfile.ZipFile(ziel, "w", zipfile.ZIP_DEFLATED) as z:
        for wurzel, _, dateien in os.walk(os.path.join(REPO, "Fairshare")):
            for d in sorted(dateien):
                voll = os.path.join(wurzel, d)
                rel = os.path.relpath(voll, REPO).replace("\\", "/")
                z.write(voll, rel)
        z.write(os.path.join(HIER, "LIESMICH.txt"), "LIESMICH.txt")
    commit = subprocess.check_output(["git", "rev-parse", "--short", "HEAD"], cwd=REPO).decode().strip() + " (Arbeitsstand)"
else:
    # Es darf nichts Unversioniertes oder Ungespeichertes in Fairshare/ liegen
    stand = subprocess.check_output(["git", "status", "--porcelain", "Fairshare"], cwd=REPO).decode("utf-8").strip()
    if stand:
        sys.exit("Fairshare/ hat uncommittete Aenderungen - erst committen oder mit --aktuell packen:\n" + stand)

    subprocess.check_call(["git", "archive", "--format=zip", "--prefix=Fairshare/", "-o", ziel, "HEAD:Fairshare"], cwd=REPO)

    with zipfile.ZipFile(ziel, "a", zipfile.ZIP_DEFLATED) as z:
        z.write(os.path.join(HIER, "LIESMICH.txt"), "LIESMICH.txt")
    commit = subprocess.check_output(["git", "rev-parse", "--short", "HEAD"], cwd=REPO).decode().strip()

with zipfile.ZipFile(ziel) as z:
    dateien = [n for n in z.namelist() if not n.endswith("/")]
print("%s  (%d Dateien, %d KB, Commit %s)" % (ziel, len(dateien), os.path.getsize(ziel) // 1024, commit))
