"""Temporary SQLite model only; not a production build-number allocator."""
import sqlite3

from .policy import DIGEST, Reconciliation


class Ledger:
    def __init__(self, path):
        self.db = sqlite3.connect(path, timeout=5)
        self.db.execute("""CREATE TABLE IF NOT EXISTS reservations (
            app TEXT, build TEXT, owner TEXT, state TEXT, digest TEXT,
            acceptance_seen INTEGER NOT NULL DEFAULT 0,
            PRIMARY KEY (app, build))""")

    def close(self):
        self.db.close()

    def reserve(self, app, build, owner):
        # Prevent accidental use of actual application identities/build numbers.
        if app != "fixture-app" or not build.startswith("fixture-"):
            raise ValueError("fixture_identity_required")
        try:
            with self.db:
                self.db.execute("INSERT INTO reservations VALUES (?, ?, ?, 'reserved', '', 0)",
                                (app, build, owner))
            return True
        except sqlite3.IntegrityError:
            return False

    def advance(self, build, owner, previous, following, digest):
        """Preparation only. Response decisions must use record_reconciliation."""
        allowed = {("reserved", "prepared"), ("prepared", "approved"),
                   ("approved", "upload_intent")}
        if (previous, following) not in allowed:
            return False
        with self.db:
            result = self.db.execute("""UPDATE reservations SET state=?, digest=?
                WHERE app='fixture-app' AND build=? AND owner=? AND state=?
                AND (digest='' OR digest=?)""", (following, digest, build, owner, previous, digest))
        return result.rowcount == 1

    def record_reconciliation(self, build, owner, previous, decision):
        """Atomically save outcome and independent acceptance evidence for this intent."""
        if (not isinstance(decision, Reconciliation) or type(decision.acceptance_seen) is not bool
                or not isinstance(decision.package_digest, str) or not DIGEST.fullmatch(decision.package_digest)
                or not isinstance(previous, str) or not isinstance(decision.state, str)
                or previous not in {"upload_intent", "unknown", "processing"}
                or decision.state not in {"unknown", "rejected", "processing", "processed", "processing_failed"}
                or (decision.state in {"processing", "processed", "processing_failed"} and not decision.acceptance_seen)
                or (decision.state == "rejected" and decision.acceptance_seen)):
            return False
        with self.db:
            # MAX preserves history even if a caller used a stale prior flag.
            # A stale rejection is converted to unknown in this same update.
            result = self.db.execute("""UPDATE reservations SET
                state=CASE WHEN ?='rejected' AND acceptance_seen=1 THEN 'unknown' ELSE ? END,
                acceptance_seen=MAX(acceptance_seen, ?)
                WHERE app='fixture-app' AND build=? AND owner=? AND state=? AND digest=?""",
                (decision.state, decision.state, int(decision.acceptance_seen),
                 build, owner, previous, decision.package_digest))
        return result.rowcount == 1

    def state(self, build):
        row = self.db.execute("SELECT state FROM reservations WHERE app='fixture-app' AND build=?",
                              (build,)).fetchone()
        return row[0] if row else None

    def acceptance_seen(self, build):
        row = self.db.execute("SELECT acceptance_seen FROM reservations WHERE app='fixture-app' AND build=?",
                              (build,)).fetchone()
        return bool(row[0]) if row else None
