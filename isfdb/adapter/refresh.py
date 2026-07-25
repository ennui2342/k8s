"""Weekly ISFDB mirror refresh.

1. Log into the ISFDB wiki (Cloudflare-protected, needs cloudscraper — not a
   real browser; see the design notes for why plain requests/Playwright fail).
2. Scrape the "Database Backups" table on ISFDB_Downloads for the newest
   5.5-compatible MySQL dump's Google Drive link.
3. Download it via gdown (handles Google Drive's large-file confirm-token
   flow) to a pod-local scratch file — never touches persistent storage.
4. Import into a staging database, sanity-check row counts, then atomically
   swap it in for the live `isfdb` database via a single multi-table RENAME.
5. Delete the scratch file and the previous week's now-orphaned tables.

A failed run leaves last week's data live — the swap only happens after the
staging import is verified.
"""
import logging
import os
import re
import subprocess
import sys
import tempfile
import time

import cloudscraper
import gdown
import pymysql
from bs4 import BeautifulSoup
from urllib.parse import urljoin

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
log = logging.getLogger("isfdb-refresh")

WIKI_USERNAME = os.environ["ISFDB_WIKI_USERNAME"]
WIKI_PASSWORD = os.environ["ISFDB_WIKI_PASSWORD"]
DB_HOST = os.environ.get("DB_HOST", "isfdb-db")
DB_PORT = int(os.environ.get("DB_PORT", "3306"))
DB_USER = os.environ.get("DB_USER", "root")
DB_PASSWORD = os.environ["MARIADB_ROOT_PASSWORD"]

DOWNLOADS_URL = "https://www.isfdb.org/wiki/index.php/ISFDB_Downloads"
LOGIN_URL = "https://www.isfdb.org/wiki/index.php/Special:UserLogin?returnto=ISFDB+Downloads"

# Sanity thresholds — ISFDB is a large, long-running database; a dump with
# fewer rows than this is almost certainly a truncated/failed download.
MIN_TITLES = 500_000
MIN_PUBS = 200_000


def login_and_get_downloads_page() -> tuple[cloudscraper.CloudScraper, str]:
    scraper = cloudscraper.create_scraper()

    r1 = scraper.get(LOGIN_URL)
    r1.raise_for_status()
    soup = BeautifulSoup(r1.text, "html.parser")
    form = soup.find("form", {"name": "userlogin"})
    if form is None:
        raise RuntimeError("login form not found — ISFDB page structure may have changed")
    action = urljoin(r1.url, form["action"])
    payload = {inp.get("name"): inp.get("value", "") for inp in form.find_all("input") if inp.get("name")}
    payload["wpName"] = WIKI_USERNAME
    payload["wpPassword"] = WIKI_PASSWORD
    payload["wploginattempt"] = "Log in"

    r2 = scraper.post(action, data=payload)
    r2.raise_for_status()

    r3 = scraper.get(DOWNLOADS_URL)
    r3.raise_for_status()
    if "Login required" in r3.text[:600]:
        raise RuntimeError("login did not succeed — check ISFDB_WIKI_USERNAME/PASSWORD")

    return scraper, r3.text


def find_latest_backup_url(downloads_html: str) -> tuple[str, str]:
    """Returns (drive_url, date) for the newest 5.5-compatible MySQL dump."""
    soup = BeautifulSoup(downloads_html, "html.parser")
    best_date = None
    best_url = None
    for a in soup.find_all("a", href=True):
        if "drive.google.com" not in a["href"]:
            continue
        row = a.find_parent("tr")
        if row is None:
            continue
        table = a.find_parent("table")
        heading = table.find_previous(["h2", "h3", "h4"]) if table else None
        if not heading or "Database Backups" not in heading.get_text():
            continue
        header_row = table.find("tr")
        headers = [c.get_text(strip=True) for c in header_row.find_all(["td", "th"])]
        if "5.5-compatible" not in headers:
            continue
        cells = row.find_all(["td", "th"])
        if len(cells) < 2:
            continue
        date_text = cells[0].get_text(strip=True)
        if not re.match(r"^\d{4}-\d{2}-\d{2}$", date_text):
            continue
        if best_date is None or date_text > best_date:
            best_date = date_text
            best_url = a["href"]

    if best_url is None:
        raise RuntimeError("no 5.5-compatible backup link found — ISFDB downloads page structure may have changed")
    return best_url, best_date


def drive_id_from_url(url: str) -> str:
    m = re.search(r"/d/([^/]+)/", url)
    if not m:
        raise RuntimeError(f"could not parse Google Drive file id from {url}")
    return m.group(1)


def db_conn(database: str | None = None):
    return pymysql.connect(
        host=DB_HOST, port=DB_PORT, user=DB_USER, password=DB_PASSWORD,
        database=database, autocommit=True, connect_timeout=10,
        cursorclass=pymysql.cursors.DictCursor,
    )


def import_dump(dump_path: str, target_db: str):
    conn = db_conn()
    with conn.cursor() as cur:
        cur.execute(f"DROP DATABASE IF EXISTS `{target_db}`")
        cur.execute(f"CREATE DATABASE `{target_db}` DEFAULT CHARACTER SET utf8mb4")
    conn.close()

    log.info("importing dump into %s (this takes a couple of minutes)...", target_db)
    with open(dump_path, "rb") as f:
        result = subprocess.run(
            ["mariadb", "-h", DB_HOST, "-P", str(DB_PORT), "-u", DB_USER,
             f"-p{DB_PASSWORD}", "--max_allowed_packet=256M", target_db],
            stdin=f, capture_output=True, text=True,
        )
    if result.returncode != 0:
        raise RuntimeError(f"mariadb import failed: {result.stderr[-2000:]}")


def sanity_check(database: str):
    conn = db_conn(database)
    with conn.cursor() as cur:
        cur.execute(f"SELECT count(*) AS n FROM `{database}`.titles")
        titles = cur.fetchone()["n"]
        cur.execute(f"SELECT count(*) AS n FROM `{database}`.pubs")
        pubs = cur.fetchone()["n"]
    conn.close()
    log.info("staging row counts — titles=%d pubs=%d", titles, pubs)
    if titles < MIN_TITLES or pubs < MIN_PUBS:
        raise RuntimeError(
            f"staging import looks truncated (titles={titles}, pubs={pubs}); "
            f"expected at least titles={MIN_TITLES}, pubs={MIN_PUBS} — aborting swap"
        )


def atomic_swap(staging_db: str, live_db: str):
    old_db = f"{live_db}_old"
    conn = db_conn()
    with conn.cursor() as cur:
        cur.execute(f"DROP DATABASE IF EXISTS `{old_db}`")
        cur.execute(f"CREATE DATABASE `{old_db}` DEFAULT CHARACTER SET utf8mb4")

        cur.execute(f"SHOW TABLES FROM `{live_db}`")
        live_tables = [r[f"Tables_in_{live_db}"] for r in cur.fetchall()]
        cur.execute(f"SHOW TABLES FROM `{staging_db}`")
        staging_tables = [r[f"Tables_in_{staging_db}"] for r in cur.fetchall()]

        renames = []
        for t in live_tables:
            renames.append(f"`{live_db}`.`{t}` TO `{old_db}`.`{t}`")
        for t in staging_tables:
            renames.append(f"`{staging_db}`.`{t}` TO `{live_db}`.`{t}`")

        if renames:
            cur.execute("RENAME TABLE " + ", ".join(renames))
            log.info("atomic swap complete — %d live tables archived, %d staging tables promoted",
                      len(live_tables), len(staging_tables))

        cur.execute(f"DROP DATABASE IF EXISTS `{old_db}`")
        cur.execute(f"DROP DATABASE IF EXISTS `{staging_db}`")
    conn.close()


def main():
    log.info("checking ISFDB downloads page for a new backup...")
    scraper, html = login_and_get_downloads_page()
    drive_url, backup_date = find_latest_backup_url(html)
    log.info("latest 5.5-compatible backup: %s (%s)", backup_date, drive_url)

    with tempfile.TemporaryDirectory() as tmpdir:
        dump_path = os.path.join(tmpdir, "isfdb-backup.sql")
        file_id = drive_id_from_url(drive_url)
        log.info("downloading via gdown (id=%s)...", file_id)
        start = time.time()
        gdown.download(f"https://drive.google.com/uc?id={file_id}", output=dump_path, quiet=False)
        log.info("download complete in %.0fs, size=%d bytes", time.time() - start, os.path.getsize(dump_path))

        import_dump(dump_path, "isfdb_staging")
        sanity_check("isfdb_staging")
        atomic_swap("isfdb_staging", "isfdb")

    log.info("refresh complete — mirror now at %s", backup_date)


if __name__ == "__main__":
    try:
        main()
    except Exception:
        log.exception("refresh failed")
        sys.exit(1)
