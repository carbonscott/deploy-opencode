# Incident: Elog-Copilot Database Lost Historical Data

**Date:** 2026-02-10
**Severity:** High — all historical experiment data missing
**Status:** Resolved

## Summary

The elog-copilot SQLite database lost all historical experiment data dating back to 2009, leaving only ~12 experiments from the most recent 7-day window. A full backfill restored 1,750 experiments spanning 2009–2025.

## Timeline

- **2026-02-08** — Earliest DB on disk (`elog_2026_0208_1200.db`) already contained only 12 experiments. The incremental chain was already broken at this point.
- **2026-02-10 ~15:30** — Issue discovered: queries against elog-copilot returned no experiments older than January 2026.
- **2026-02-10 15:40** — Cron job disabled on sdfcron001.
- **2026-02-10 15:45** — Full backfill started with `--hours 158000` (~18 years).
- **2026-02-10 18:18** — Backfill completed: 1,790 succeeded, 1 failed (access denied on `tmol1032021`).
- **2026-02-10 18:19** — Symlink updated, cron re-enabled.

## Root Cause

The elog-copilot system relies on an **incremental chain** to preserve historical data:

1. The elog API endpoint (`/ws/lgbk/lgbk/ws/experiment_names_updated_within?offset_secs=N`) only returns experiments with activity within the lookback window.
2. The cron job uses a **7-day (168-hour) lookback** — so only experiments with recent elog activity are returned by the API.
3. In **incremental mode**, the tool copies the latest DB file and only updates experiments returned by the API. Old experiments are preserved because they're carried forward in the copy.
4. If a **fresh (non-incremental) DB** is ever created instead, the chain breaks. The new DB only contains the ~12 experiments active in the past 7 days, and all historical data is lost.

**What likely broke the chain:** At some point before 2026-02-08, a fresh database was created without using `--incremental`. This could have happened due to:
- Manual invocation without `--incremental`
- All existing `elog_*.db` files being deleted (cleanup gone wrong)
- A code change or configuration error that bypassed incremental mode

Once the chain broke, every subsequent cron run built incrementally on the tiny base, so the problem was self-perpetuating.

## Impact

- **1,750 experiments** spanning **16 years** (2009–2025) were missing from the database.
- All elog-copilot queries (from any user) returned only recent data.
- DB size dropped from ~1.2 GB to ~2.8 MB.
- The issue persisted for at least 2 days before discovery (based on oldest DB file on disk).

## Fix

### Steps taken

```bash
# 1. Disable cron to prevent interference
/sdf/group/lcls/ds/dm/apps/dev/tools/elog-copilot/scripts/elog-cron.sh disable

# 2. Verify Kerberos ticket
klist -s || kinit

# 3. Dry run to confirm scope (1,867 experiments found)
source /sdf/group/lcls/ds/dm/apps/dev/tools/elog-copilot/env.sh
source /sdf/group/lcls/ds/dm/apps/dev/tools/elog-copilot/.venv/bin/activate
elogfetch update --dry-run --hours 158000 \
  --output-dir /sdf/group/lcls/ds/dm/apps/dev/data/elog-copilot

# 4. Run full backfill (non-incremental, ~2.5 hours)
elogfetch update --hours 158000 --parallel 10 \
  --output-dir /sdf/group/lcls/ds/dm/apps/dev/data/elog-copilot

# 5. Update symlink
cd /sdf/group/lcls/ds/dm/apps/dev/data/elog-copilot
ln -sf "$(ls -t elog_*.db | head -1)" elog-copilot.db

# 6. Verify
sqlite3 elog-copilot.db \
  "SELECT COUNT(DISTINCT experiment_id), MIN(start_time), MAX(start_time) FROM Experiment;"
# Result: 1750 | 2009-08-13 | 2025-07-18

# 7. Re-enable cron
/sdf/group/lcls/ds/dm/apps/dev/tools/elog-copilot/scripts/elog-cron.sh enable
```

### Results

| Metric | Before | After |
|--------|--------|-------|
| Experiments | 12 | 1,750 |
| Oldest experiment | 2026-01-10 | 2009-08-13 |
| DB size | 2.8 MB | 1.2 GB |
| Instruments covered | ~4 | 16 |

### Known issues from backfill

- **1 failed experiment:** `tmol1032021` — access denied (permissions issue, not a data loss)
- **UED questionnaires:** Multiple UED experiments returned 500 errors on questionnaire fetch — the experiments themselves were ingested successfully, just missing questionnaire data

## Prevention

### Why this is fragile

The current design has a single point of failure: the incremental chain. If it breaks for any reason, there is no automatic way to detect or recover — the cron job happily continues building on the broken base.

### Recommended safeguards

1. **Monitor experiment count.** Add a post-update check to `elog-cron.sh` that alerts if the experiment count drops below a threshold (e.g., 1,000). A simple check:
   ```bash
   count=$(sqlite3 "$db" "SELECT COUNT(*) FROM Experiment;")
   if [[ $count -lt 1000 ]]; then
       echo "ALERT: Experiment count dropped to $count" >&2
   fi
   ```

2. **Monitor DB file size.** A healthy DB should be >500 MB. If a new DB is <10 MB, something went wrong. The cleanup step in `elog-cron.sh` could check this before deleting old DBs.

3. **Protect against accidental non-incremental runs.** The cron script already uses `--incremental`, but a manual run without it would break the chain. Consider making incremental the default in the CLI when an existing DB is present.

4. **Keep more old DBs.** Currently `KEEP_DB_COUNT=8` (2 days of 6-hour runs). Increasing this to 30+ would provide a longer recovery window if the chain breaks.

## References

- Tool location: `/sdf/group/lcls/ds/dm/apps/dev/tools/elog-copilot/`
- Data directory: `/sdf/group/lcls/ds/dm/apps/dev/data/elog-copilot/`
- Cron script: `scripts/elog-cron.sh`
- Backfill procedure: `README.md` § "Backfilling Missing Experiments"
- Source repo: `/sdf/data/lcls/ds/prj/prjcwang31/results/fetch-elog/`
