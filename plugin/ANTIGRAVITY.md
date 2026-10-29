# Antigravity CLI & Improved AI Usage Plugin

This user-owned clone of `omarchy.agents` (`<username>.agents`) survives Omarchy
package updates. `Main.qml` calls `update-usage`, which preserves the packaged
collectors, auto-refreshes expired Claude Code OAuth tokens when a valid refresh
token exists, and adds `collect-antigravity.py`. Right-click the bar icon with
Antigravity selected to launch `agy`.

## Token statistics

The collector reads `~/.gemini/antigravity-cli/conversations/*.db` in SQLite
read-only mode, including live WAL data. `gen_metadata` contains protobuf
`CortexStepGeneratorMetadata`: field 1 is `ChatModelMetadata`, whose field 4 is
`ModelUsageStats`. Token fields are 2 (input), 3 (output), 4 (cache writes),
and 5 (cache reads). Output already includes thinking tokens; fields 9/10
are its breakdown and must not be added again. These field numbers were
verified against the protobuf descriptors embedded in the installed `agy`.

Each generation is counted once, deduplicated by message/response ID.
Timestamps come from its associated steps, falling back to its execution ID.
Model names come from recorded model display names or response model IDs.
The chart covers the last seven local calendar days; the model table covers
all stored conversations, including internal models that have recorded usage.
Hover model rows for input/output/cache counts. All Antigravity models are
shown, rather than just the stock panel's top four. Database mtime/size and
WAL signatures invalidate the local statistics cache.

## Account limits & OAuth token renewal

The collector uses Antigravity's own stored OAuth access token from the system
keyring (`secret-tool lookup service gemini username antigravity`, with a
fallback to `~/.gemini/antigravity-cli/antigravity-oauth-token`), calling
`loadCodeAssist`, `retrieveUserQuotaSummary`, and `fetchAvailableModels`. The
host (`daily` or `production`) follows the installed CLI's logs, with an
allowlist of Google API hosts. Expired tokens are refreshed by `agy models`, a
read-only account command, using the CLI's own OAuth configuration. No
credentials are written into the plugin, usage record, or statistics cache.

Similarly, `update-usage` checks whether Claude Code's access token in
`~/.claude/.credentials.json` is expired while a valid refresh token is
present, and runs `claude auth status` to refresh it before invoking the stock
collectors.

The panel shows the actual plan, quota groups, windows, and reset times
returned by the account. Fractions remaining are converted to percentages
used, consistent with Claude/Codex. Any quota meters not returned by the server
are not invented. An API outage retains the last successful limits and shows a
stale-data warning. Model-scoped `quotaInfo` serves as a fallback on servers
without summary buckets.

Opening the panel refreshes limits; clicking the `󰑐` refresh button in the
panel header or pressing `R`/`Enter` forces a full refresh. The normal bar
refresh interval also updates Antigravity. `--except antigravity` and
provider-specific refreshes are honored by `update-usage`.

For a local-only check:
    ./collect-antigravity.py --local-only --force

To return to stock, run `./uninstall.sh` or replace `<username>.agents` with
`omarchy.agents` in `~/.config/omarchy/shell.json`.
