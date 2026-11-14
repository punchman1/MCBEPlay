# Changelog

## 3.6-cpx fixes after BDS 1.26.63.1 testing

- Player join/leave logs the XUID after `xuid:`. `Player Spawned` and `Player PartyIdUpdate` are not treated as join or leave.
- Live backups also copy non-db world files: pack JSON, `behavior_packs/`, `resource_packs/`, `world_icon`, `levelname.txt`, and anything else except `db/` (that still comes from `save query` and is truncated). Full backups copy those too. Rollback will not select a live save that is missing non-db files the world still has, and it stages the backup before deleting the live `db` folder.
- Stop, exit, and update close the bedrock PID this instance started. They do not match `bedrock_server.exe` or `bds.exe` by name.
- `_purgeFolders` uses the loop index it actually has. `auto_restart=off` (also `false` or `none`) and `restart_interval=0` disable scheduled restarts.
- Live-backup truncate calls `_WinAPI_SetFilePointer` with three arguments. The old fourth argument aborted the helper and left the server in `save hold`. `save resume` is sent again on exit if a hold is still open.

## 3.6-cpx

Fork of FoxyNoTail's MCBEPlay 3.5 (GPL-3.0). Foxy's credits and license are unchanged.

Bedrock Dedicated Server 1.26 fixes. The false-positive handling follows the approach in [ZanderCowboy/MCBEPlay](https://github.com/ZanderCowboy/MCBEPlay) (18 and 20 August 2026) and was checked against this tree.

- Startup no longer dies on `Profiler config ('bootstrap.json') load result: success=1, errorMessage=(null)`. Only a BDS log level of `ERROR` stops the server. That success line is INFO, and the old check matched the letters in `errorMessage`.
- `Unknown command` is not fatal. The 60 second health check used to send a blank line, which BDS logs as `[ERROR] Unknown command:`. It now sends `list`. Commands read from `command.txt` are trimmed so a trailing newline is not sent as a second, empty command.
- A `cmd /K` prompt such as `C:\MCBEPlay\BDS>` is not a crash. The old check treated any line containing `server_dir` as a crash, including that prompt after a clean quit. Crashes are `CrashReporter` or a non-INFO `EXCEPTION`.
- Reload Allowlist sends `allowlist reload` (BDS 1.18.10 and newer). Older installs still get `whitelist reload`.
- Live backups parse modern `save query` output (`WorldName/db/file:size`, including spaces in the world name). Files are copied from the real path, then truncated to the reported size, including files larger than 4 GB. `save resume` always runs. `auto_save` still defaults to false. BDS-2733 was closed in 2022.
- Optional BDS updates, off unless `options.txt` says otherwise. See the options below. No telemetry.
- `compile.ps1` and a Windows GitHub Actions workflow build `mcbeplay.exe` and `bds.exe` with Aut2Exe, without UPX.

### New options

Missing keys are safe. An existing `options.txt` keeps working.

| Option | Default | Meaning |
| --- | --- | --- |
| `auto_update` | `false` | `false` does nothing. `interval` checks every `update_interval` hours. `time` checks once a day at or after `update_time`. `true` is the same as `interval`. |
| `update_interval` | `24` | Hours between checks when `auto_update=interval`. Values below 1 are treated as 24. |
| `update_time` | `04:00` | `HH:MM` used when `auto_update=time`. |

The first automatic check waits two minutes after the GUI opens. A failed web request waits 30 minutes before it tries again. Check for Update on the GUI does not wait.

When a newer Windows stable build is found, MCBEPlay warns players, stops the server, copies the world into `save_dir`, downloads the official zip, and replaces server files. It keeps `worlds\`, `server.properties`, `allowlist.json`, `whitelist.json`, `permissions.json`, and `packetlimitconfig.json` (when that file already exists). Anything else in the zip is replaced. Files that were not in the zip are left alone. If a step fails after files were replaced, the previous files are copied back and the old server is started when it had been running.

The version check reads `bedrock_server.exe` (`FileVersion`, then `ProductVersion`) and compares it to the version in Mojang's zip name. Preview builds are ignored.

The download URL comes from `https://net-secondary.web.minecraft-services.net/api/v1.0/download/links`, the same API the official Bedrock server download page uses. Only `serverBedrockWindows` is accepted, and the URL has to be `https://www.minecraft.net/bedrockdedicatedserver/bin-win/bedrock-server-<version>.zip`.
