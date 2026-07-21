#!/sd/usr/bin/python
# Schema-agnostic recon.db summary (row counts per table). Used by bot-report.
import sqlite3, sys
db = sys.argv[1] if len(sys.argv) > 1 else '/sd/recon.db'
try:
    c = sqlite3.connect(db)
    tables = [r[0] for r in c.execute("select name from sqlite_master where type='table'")]
    if not tables:
        print ' (empty database)'
    for t in tables:
        try:
            n = c.execute('select count(*) from "%s"' % t).fetchone()[0]
        except Exception:
            n = '?'
        print ' %-22s %s rows' % (t, n)
except Exception as e:
    print ' db read error:', e
