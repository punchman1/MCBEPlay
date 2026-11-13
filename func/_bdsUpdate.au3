; Optional Bedrock Dedicated Server updates (MCBEPlay 3.6-cpx).
; Original MCBEPlay Copyright (C) 2020 FoxyNoTail. GPL-3.0. See LICENSE.
; No telemetry. The only network call is Mojang's official download-link API,
; and only when an automatic check is due or Check for Update is clicked.

Func _BDSAutoUpdate()

   If $gui <> True Then Return
   If $update_in_progress Then Return
   If $server_working Then Return

   Local $mode = StringLower(StringStripWS($auto_update, 3))
   If $mode = "true" Then $mode = "interval"
   If $mode <> "interval" And $mode <> "time" Then Return
   ; Let the GUI and keepalive settle before the first automatic check.
   If TimerDiff($update_arm_timer) < 120000 Then Return
   If _BDSUpdateIsDue($mode) = False Then Return

   _log("Automatic BDS update check is due (" & $mode & ")", "BDS Update", False, True)
   _BDSCheckForUpdate(False)

EndFunc

Func _BDSCheckForUpdate($manual)

   Local $function_name = "BDS Update"
   If $gui <> True Then Return False
   If $update_in_progress Then
	  If $manual Then MsgBox(48, "MCBEPlay", "An update is already running.")
	  Return False
   EndIf

   _log("Checking Mojang for the latest Windows Bedrock Dedicated Server", $function_name, False, True)

   Local $latest = ""
   Local $url = ""
   Local $err = ""
   If _BDSFetchLatestStable($latest, $url, $err) = False Then
	  _BDSUpdateStamp($update_fail_file)
	  _log("Update check failed: " & $err, $function_name, True)
	  If $manual Then MsgBox(16, "MCBEPlay", "Could not check for an update." & @CRLF & $err)
	  Return False
   EndIf

   FileDelete($update_fail_file)
   _BDSUpdateStamp($update_check_file)

   Local $installed = _BDSInstalledVersion()
   _log("Installed version: [" & $installed & "] Latest stable: [" & $latest & "] " & $url, $function_name, False, True)

   If $installed <> "" And _BDSVersionCompare($installed, $latest) >= 0 Then
	  _log("Bedrock Dedicated Server is up to date", $function_name, False, True)
	  If $manual Then MsgBox(64, "MCBEPlay", "Already on the latest Windows BDS (" & $installed & ").")
	  Return True
   EndIf

   If $installed = "" And $manual = False Then
	  _log("Could not read bedrock_server.exe version. Automatic update skipped.", $function_name, True)
	  Return False
   EndIf

   Local $was_running = False
   If WinExists($window_title) Or ProcessExists($server_file) Then
	  $was_running = True
   EndIf

   If $manual Then
	  Local $prompt = "A newer Bedrock Dedicated Server is available." & @CRLF & @CRLF & "Installed: " & $installed & @CRLF & "Latest: " & $latest & @CRLF & @CRLF
	  If $installed = "" Then
		 $prompt = "Could not read the installed bedrock_server.exe version." & @CRLF & "Latest stable is " & $latest & "." & @CRLF & @CRLF
	  EndIf
	  If $was_running Then
		 $prompt &= "MCBEPlay will warn players, stop the server, back up the world, replace server files (keeping worlds and your config), and restart."
	  Else
		 $prompt &= "The server is not running. MCBEPlay will back up the world and replace server files. It will not start the server."
	  EndIf
	  $prompt &= @CRLF & @CRLF & "Continue?"
	  If MsgBox(52, "MCBEPlay", $prompt) <> 6 Then
		 _log("Update declined", $function_name, False, True)
		 Return False
	  EndIf
   Else
	  _log("Newer BDS " & $latest & " will be installed automatically", $function_name, False, True)
   EndIf

   Return _BDSApplyUpdate($latest, $url, $was_running, $installed, $manual)

EndFunc

Func _BDSApplyUpdate($latest, $url, $was_running, $installed_before, $manual)

   Local $function_name = "BDS Update"
   ; Button events can still fire during Sleep. These flags stay set until the end.
   $update_in_progress = True
   $server_working = True
   $server_stopped = True
   _BDSBusy(True)
   _BDSUpdateStamp($updating_file)
   If $gui = True Then
	  GUICtrlSetData($state_label2, "[UPDATING]")
	  GUICtrlSetColor($state_label2, $COLOR_RED)
   EndIf

   Local $work = $tmp_dir & "\update"
   Local $rollback = $work & "\rollback"
   Local $added = $work & "\added.txt"
   Local $staging = $work & "\staging"
   Local $zip = $work & "\bedrock-server.zip"

   If $was_running Then
	  If _BDSUpdateStopServer($latest) = False Then
		 Local $still_up = _BDSUpdateServerIsUp()
		 _BDSUpdateTell($manual, "Update aborted because the server did not stop cleanly. No files were changed.", True)
		 _BDSUpdateFinish($still_up)
		 Return False
	  EndIf
   EndIf

   FileDelete($error_file)

   If _BDSUpdateServerIsUp() Then
	  _BDSUpdateTell($manual, "bedrock_server is still running. Refusing to replace files.", True)
	  _BDSUpdateFinish(True)
	  Return False
   EndIf

   If _BDSUpdateWorldBackup() = False Then
	  _BDSUpdateTell($manual, "Update aborted because the world backup failed. Server files were not changed.", True)
	  If $was_running Then
		 _BDSUpdateStartAndWait()
		 _BDSUpdateFinish(True)
	  Else
		 _BDSUpdateFinish(False)
	  EndIf
	  Return False
   EndIf

   DirRemove($work, 1)
   DirCreate($work)

   If _BDSUpdateDownload($url, $zip) = False Then
	  _BDSUpdateTell($manual, "Update aborted because the download failed. The previous install was not changed.", True)
	  If $was_running Then _BDSUpdateStartAndWait()
	  _BDSUpdateFinish($was_running)
	  Return False
   EndIf

   If _BDSUpdateExtract($zip, $staging) = False Then
	  _BDSUpdateTell($manual, "Update aborted because the zip could not be extracted. The previous install was not changed.", True)
	  If $was_running Then _BDSUpdateStartAndWait()
	  _BDSUpdateFinish($was_running)
	  Return False
   EndIf

   Local $root = _BDSUpdateStagingRoot($staging)
   If $root = "" Then
	  _BDSUpdateTell($manual, "The zip has no bedrock_server.exe. The previous install was not changed.", True)
	  If $was_running Then _BDSUpdateStartAndWait()
	  _BDSUpdateFinish($was_running)
	  Return False
   EndIf

   _log("Replacing server files from " & $root & ". Previous-install snapshot: " & $rollback, $function_name, False, True)
   If _BDSUpdateSwapFiles($root, $rollback, $added) = False Then
	  _log("File replace failed. Restoring the previous install.", $function_name, True)
	  _BDSUpdateRestore($rollback, $added)
	  If $was_running Then _BDSUpdateStartAndWait()
	  _BDSUpdateTell($manual, "Update failed while copying files. The previous install was restored.", True)
	  _BDSUpdateFinish($was_running)
	  Return False
   EndIf

   Local $after = _BDSInstalledVersion()
   Local $version_bad = False
   If $installed_before <> "" And $after = "" Then $version_bad = True
   If $after <> "" And _BDSVersionCompare($after, $latest) < 0 Then $version_bad = True
   If $version_bad Then
	  _log("Version after copy is [" & $after & "], expected " & $latest & ". Restoring.", $function_name, True)
	  _BDSUpdateRestore($rollback, $added)
	  If $was_running Then _BDSUpdateStartAndWait()
	  _BDSUpdateTell($manual, "The new bedrock_server.exe did not match " & $latest & ". The previous install was restored.", True)
	  _BDSUpdateFinish($was_running)
	  Return False
   EndIf
   _log("Server files now report version [" & $after & "]", $function_name, False, True)

   If $was_running Then
	  If _BDSUpdateStartAndWait() = False Then
		 _log("New BDS did not start. Restoring the previous install.", $function_name, True)
		 _BDSUpdateKillLeftovers()
		 _BDSUpdateRestore($rollback, $added)
		 Local $old_ok = _BDSUpdateStartAndWait()
		 If $old_ok Then
			_BDSUpdateTell($manual, "The new BDS did not start. The previous version was restored and started. Snapshot: " & $rollback, True)
			_BDSUpdateFinish(True)
		 Else
			_BDSUpdateTell($manual, "The new BDS did not start, and the restored copy did not start either. Previous files are at " & $rollback, True)
			_BDSUpdateFinish(False)
		 EndIf
		 Return False
	  EndIf
   EndIf

   _log("BDS update to " & $latest & " finished", $function_name, False, True)
   DirRemove($work, 1)
   _BDSUpdateFinish($was_running)
   If $was_running Then
	  _BDSUpdateTell($manual, "Updated Bedrock Dedicated Server to " & $latest & " and restarted.", False)
   Else
	  _BDSUpdateTell($manual, "Updated Bedrock Dedicated Server to " & $latest & ". The server was left stopped.", False)
   EndIf
   Return True

EndFunc

Func _BDSUpdateFinish($leave_running)

   _BDSBusy(False)
   $server_working = False
   $update_in_progress = False
   FileDelete($updating_file)
   If $leave_running Then
	  $server_stopped = False
   Else
	  $server_stopped = True
   EndIf

EndFunc

Func _BDSUpdateTell($manual, $text, $is_error)

   _log($text, "BDS Update", $is_error, True)
   If $manual Then
	  Local $flag = 64
	  If $is_error Then $flag = 16
	  MsgBox($flag, "MCBEPlay", $text)
   EndIf

EndFunc

Func _BDSUpdateStopServer($latest)

   Local $function_name = "BDS Update"
   Local $say = "say MCBEPlay is updating the server to Bedrock " & $latest & ". The server will restart in 15 seconds."
   _log("Warning players: " & $say, $function_name, False, True)
   If _BDSUpdateSendCommand($say, 30000) = False Then
	  _log("The server did not accept the warning chat.", $function_name, True)
	  Return False
   EndIf
   Sleep(15000)
   _log("Sending update-stop", $function_name, False, True)
   If _BDSUpdateSendCommand("update-stop", 30000) = False Then
	  _log("The server did not accept update-stop.", $function_name, True)
	  Return False
   EndIf

   Local $t = TimerInit()
   While _BDSUpdateServerIsUp()
	  If TimerDiff($t) > 600000 Then
		 _log("Server did not exit within 10 minutes", $function_name, True)
		 Return False
	  EndIf
	  Sleep(500)
   WEnd
   Sleep(1000)
   _log("Server stopped", $function_name, False, True)
   Return True

EndFunc

Func _BDSUpdateSendCommand($command, $timeout)

   _serverSendCommand($command)
   Local $t = TimerInit()
   While FileExists($command_file)
	  If TimerDiff($t) > $timeout Then Return False
	  Sleep(200)
   WEnd
   Return True

EndFunc

Func _BDSUpdateServerIsUp()

   If ProcessExists($server_file) Then Return True
   If WinExists($window_title) Then Return True
   Return False

EndFunc

Func _BDSUpdateKillLeftovers()

   If WinExists($window_title) Then
	  WinClose($window_title)
	  Sleep(1000)
   EndIf
   If ProcessExists("bds.exe") Then
	  ProcessClose("bds.exe")
	  Sleep(500)
   EndIf
   If ProcessExists($server_file) Then
	  ProcessClose($server_file)
	  Sleep(500)
   EndIf

EndFunc

Func _BDSUpdateWorldBackup()

   Local $function_name = "BDS Update"
   If $level_name = "" Then
	  _log("level-name is empty in server.properties. World backup aborted.", $function_name, True)
	  Return False
   EndIf
   Local $src = $world_dir & "\" & $level_name
   If Not FileExists($src) Then
	  _log("World folder not found: " & $src, $function_name, True)
	  Return False
   EndIf
   Local $dst = $save_dir & "\FULL_" & $level_name & "-" & @YEAR & @MON & @MDAY & @HOUR & @MIN & @SEC
   _log("Copying world before update: " & $src & " -> " & $dst, $function_name, False, True)
   If DirCopy($src, $dst, 1) = 0 Then
	  _log("World backup failed: " & $src, $function_name, True)
	  Return False
   EndIf
   If FileExists($backedup_file) Then FileDelete($backedup_file)
   Local $h = FileOpen($backedup_file, 2)
   FileClose($h)
   _log("World backup finished: " & $dst, $function_name, False, True)
   Return True

EndFunc

Func _BDSUpdateDownload($url, $zip)

   Local $function_name = "BDS Update"
   _log("Downloading " & $url, $function_name, False, True)
   HttpSetUserAgent("MCBEPlay/3.6-cpx")
   Local $h = InetGet($url, $zip, 1, 1)
   If @error Or $h = 0 Then
	  _log("InetGet failed to start", $function_name, True)
	  Return False
   EndIf

   Local $t = TimerInit()
   Local $last_log = 0
   While InetGetInfo($h, 2) = False
	  Sleep(500)
	  If TimerDiff($t) - $last_log > 15000 Then
		 $last_log = TimerDiff($t)
		 _log("Downloaded " & InetGetInfo($h, 0) & " bytes", $function_name, False, True)
	  EndIf
	  If TimerDiff($t) > 600000 Then
		 InetClose($h)
		 _log("Download timed out", $function_name, True)
		 Return False
	  EndIf
   WEnd

   Local $success = InetGetInfo($h, 3)
   Local $bytes = InetGetInfo($h, 0)
   InetClose($h)
   If $success = False Or Number($bytes) < 1000000 Then
	  _log("Download failed or was too small (" & $bytes & " bytes)", $function_name, True)
	  Return False
   EndIf
   _log("Downloaded " & $bytes & " bytes to " & $zip, $function_name, False, True)
   Return True

EndFunc

Func _BDSUpdateExtract($zip, $dest)

   Local $function_name = "BDS Update"
   DirCreate($dest)
   _log("Extracting " & $zip, $function_name, False, True)
   Local $tar = RunWait(@ComSpec & ' /c tar -xf "' & $zip & '" -C "' & $dest & '"', $tmp_dir, @SW_HIDE)
   If _BDSUpdateStagingRoot($dest) <> "" Then
	  _log("tar extracted the zip (exit " & $tar & ")", $function_name, False, True)
	  Return True
   EndIf

   _log("tar did not produce bedrock_server.exe (exit " & $tar & "). Trying Expand-Archive.", $function_name, False, True)
   Local $ps1 = $tmp_dir & "\update\expand.ps1"
   Local $ps = "Expand-Archive -LiteralPath '" & StringReplace($zip, "'", "''") & "' -DestinationPath '" & StringReplace($dest, "'", "''") & "' -Force" & @CRLF
   Local $fh = FileOpen($ps1, 2)
   FileWrite($fh, $ps)
   FileClose($fh)
   Local $code = RunWait('powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "' & $ps1 & '"', $tmp_dir, @SW_HIDE)
   If _BDSUpdateStagingRoot($dest) <> "" Then
	  _log("Expand-Archive extracted the zip (exit " & $code & ")", $function_name, False, True)
	  Return True
   EndIf
   _log("Could not extract bedrock_server.exe (Expand-Archive exit " & $code & ")", $function_name, True)
   Return False

EndFunc

Func _BDSUpdateStagingRoot($dest)

   If FileExists($dest & "\bedrock_server.exe") Then Return $dest
   Local $dirs = _FileListToArray($dest, "*", $FLTA_FOLDERS)
   If IsArray($dirs) Then
	  Local $i
	  For $i = 1 To $dirs[0]
		 If FileExists($dest & "\" & $dirs[$i] & "\bedrock_server.exe") Then
			Return $dest & "\" & $dirs[$i]
		 EndIf
	  Next
   EndIf
   Return ""

EndFunc

Func _BDSUpdateSwapFiles($root, $rollback, $added)

   Local $function_name = "BDS Update"
   DirCreate($rollback)
   Local $h = FileOpen($added, 2)
   FileClose($h)

   Local $files = _FileListToArrayRec($root, "*", $FLTAR_FILES, $FLTAR_RECUR, $FLTAR_NOSORT, $FLTAR_RELPATH)
   If Not IsArray($files) Then
	  _log("No files found in " & $root, $function_name, True)
	  Return False
   EndIf

   Local $i
   For $i = 1 To $files[0]
	  Local $rel = $files[$i]
	  If StringInStr($rel, "..") > 0 Then
		 _log("Skipping unsafe path " & $rel, $function_name, True)
		 ContinueLoop
	  EndIf
	  Local $norm = StringLower(StringReplace($rel, "/", "\"))
	  If $norm = "worlds" Or StringLeft($norm, 7) = "worlds\" Then
		 _log("Left worlds untouched (" & $rel & ")", $function_name, False, False)
		 ContinueLoop
	  EndIf
	  Local $dest = $server_dir & "\" & $rel
	  If _BDSUpdateIsUserConfig($norm) And FileExists($dest) Then
		 _log("Preserved " & $rel, $function_name, False, True)
		 ContinueLoop
	  EndIf
	  If FileExists($dest) Then
		 If FileCopy($dest, $rollback & "\" & $rel, 9) = 0 Then
			_log("Could not snapshot " & $dest, $function_name, True)
			Return False
		 EndIf
	  Else
		 FileWriteLine($added, $rel)
	  EndIf
	  If FileCopy($root & "\" & $rel, $dest, 9) = 0 Then
		 _log("Could not copy " & $rel & " into " & $server_dir, $function_name, True)
		 Return False
	  EndIf
   Next
   Return True

EndFunc

Func _BDSUpdateIsUserConfig($norm)

   If $norm = "server.properties" Then Return True
   If $norm = "allowlist.json" Then Return True
   If $norm = "whitelist.json" Then Return True
   If $norm = "permissions.json" Then Return True
   If $norm = "packetlimitconfig.json" Then Return True
   Return False

EndFunc

Func _BDSUpdateRestore($rollback, $added)

   Local $function_name = "BDS Update"
   _log("Restoring previous server files from " & $rollback, $function_name, False, True)
   Local $ok = True
   Local $i
   If FileExists($rollback) Then
	  Local $files = _FileListToArrayRec($rollback, "*", $FLTAR_FILES, $FLTAR_RECUR, $FLTAR_NOSORT, $FLTAR_RELPATH)
	  If IsArray($files) Then
		 For $i = 1 To $files[0]
			If FileCopy($rollback & "\" & $files[$i], $server_dir & "\" & $files[$i], 9) = 0 Then
			   _log("Could not restore " & $files[$i], $function_name, True)
			   $ok = False
			EndIf
		 Next
	  EndIf
   EndIf
   If FileExists($added) Then
	  Local $lines
	  _FileReadToArray($added, $lines)
	  If IsArray($lines) Then
		 For $i = 1 To $lines[0]
			Local $rel = $lines[$i]
			If $rel = "" Or StringInStr($rel, "..") > 0 Then ContinueLoop
			Local $path = $server_dir & "\" & $rel
			If FileExists($path) Then
			   If FileDelete($path) = 0 Then
				  _log("Could not remove added file " & $path, $function_name, True)
				  $ok = False
			   EndIf
			EndIf
		 Next
	  EndIf
   EndIf
   If $ok Then
	  _log("Previous server files restored", $function_name, False, True)
   EndIf
   Return $ok

EndFunc

Func _BDSUpdateStartAndWait()

   Local $function_name = "BDS Update"
   FileDelete($error_file)
   FileDelete($response_file)
   _log("Starting BDS", $function_name, False, True)
   _runScript("bds")
   Local $t = TimerInit()
   While TimerDiff($t) < 180000
	  Sleep(500)
	  If FileExists($error_file) Then
		 Local $e = FileRead($error_file)
		 If $e = "ERROR" Or $e = "CRASH" Or $e = "UNRESPONSIVE" Then
			_log("BDS reported " & $e & " while starting", $function_name, True)
			Return False
		 EndIf
	  EndIf
	  If FileExists($response_file) Then
		 Local $resp = FileRead($response_file)
		 If StringInStr($resp, "started succes") > 0 Then
			_log("BDS started: " & $resp, $function_name, False, True)
			Return True
		 EndIf
		 If StringInStr(StringLower($resp), "fail") > 0 Then
			_log("BDS start failed: " & $resp, $function_name, True)
			Return False
		 EndIf
	  EndIf
   WEnd
   _log("Timed out waiting for BDS to start", $function_name, True)
   Return False

EndFunc

Func _BDSFetchLatestStable(ByRef $version, ByRef $url, ByRef $err)

   $version = ""
   $url = ""
   $err = ""
   Local $api = "https://net-secondary.web.minecraft-services.net/api/v1.0/download/links"
   HttpSetUserAgent("MCBEPlay/3.6-cpx")
   Local $raw = InetRead($api, 1)
   If @error Or $raw = "" Then
	  $err = "Could not read " & $api
	  Return False
   EndIf

   Local $json = BinaryToString($raw, 4)
   Local $found = StringRegExp($json, '(\{[^{}]*"downloadType"\s*:\s*"serverBedrockWindows"[^{}]*\})', 1)
   If Not IsArray($found) Then
	  $err = "The download API did not list serverBedrockWindows"
	  Return False
   EndIf
   Local $u = StringRegExp($found[0], '"downloadUrl"\s*:\s*"(https://[^"]+)"', 1)
   If Not IsArray($u) Then
	  $err = "The download API entry had no downloadUrl"
	  Return False
   EndIf
   $url = $u[0]
   If _BDSUpdateUrlOk($url) = False Then
	  $err = "Refusing a download URL that is not the official Windows stable zip: " & $url
	  $url = ""
	  Return False
   EndIf
   Local $v = StringRegExp($url, 'bedrock-server-(\d+\.\d+\.\d+(?:\.\d+)?)\.zip$', 1)
   If Not IsArray($v) Then
	  $err = "Could not read a version from " & $url
	  $url = ""
	  Return False
   EndIf
   $version = $v[0]
   _log("Official Windows stable is " & $version & " (" & $url & ")", "BDS Update", False, True)
   Return True

EndFunc

Func _BDSUpdateUrlOk($url)

   Local $prefix = "https://www.minecraft.net/bedrockdedicatedserver/bin-win/bedrock-server-"
   If StringLeft($url, StringLen($prefix)) <> $prefix Then Return False
   If StringRight(StringLower($url), 4) <> ".zip" Then Return False
   If StringInStr($url, "..") > 0 Then Return False
   If StringInStr(StringLower($url), "preview") > 0 Then Return False
   Return True

EndFunc

Func _BDSInstalledVersion()

   Local $exe = $server_dir & "\" & $server_file
   If Not FileExists($exe) Then Return ""
   Local $keys[2] = ["FileVersion", "ProductVersion"]
   Local $i
   For $i = 0 To 1
	  Local $v = _BDSNormalizeVersion(FileGetVersion($exe, $keys[$i]))
	  If $v <> "" Then Return $v
   Next
   Return ""

EndFunc

Func _BDSNormalizeVersion($v)

   If $v = "" Then Return ""
   $v = StringReplace($v, ",", ".")
   $v = StringStripWS($v, 8)
   Local $m = StringRegExp($v, "(\d+\.\d+\.\d+(?:\.\d+)?)", 1)
   If IsArray($m) Then Return $m[0]
   Return ""

EndFunc

; -1 if $a < $b, 0 if equal, 1 if $a > $b. Missing pieces count as 0.
Func _BDSVersionCompare($a, $b)

   $a = _BDSNormalizeVersion($a)
   $b = _BDSNormalizeVersion($b)
   If $a = "" Then $a = "0.0.0"
   If $b = "" Then $b = "0.0.0"
   Local $pa = StringSplit($a, ".")
   Local $pb = StringSplit($b, ".")
   Local $n = $pa[0]
   If $pb[0] > $n Then $n = $pb[0]
   Local $i
   For $i = 1 To $n
	  Local $va = 0
	  Local $vb = 0
	  If $i <= $pa[0] Then $va = Number($pa[$i])
	  If $i <= $pb[0] Then $vb = Number($pb[$i])
	  If $va < $vb Then Return -1
	  If $va > $vb Then Return 1
   Next
   Return 0

EndFunc

Func _BDSUpdateIsDue($mode)

   If FileExists($update_fail_file) Then
	  Local $fail_at = StringStripWS(FileRead($update_fail_file), 3)
	  Local $mins = _DateDiff("n", $fail_at, _NowCalc())
	  ; A bad stamp must not block checks forever.
	  If $fail_at <> "" And @error = 0 And $mins >= 0 And $mins < 30 Then
		 Return False
	  EndIf
   EndIf

   Local $last = ""
   If FileExists($update_check_file) Then
	  $last = StringStripWS(FileRead($update_check_file), 3)
   EndIf

   If $mode = "time" Then
	  If _BDSClockReached($update_time) = False Then Return False
	  If $last <> "" And StringLeft($last, 10) = StringLeft(_NowCalc(), 10) Then Return False
	  Return True
   EndIf

   Local $hours = Number($update_interval)
   If $hours < 1 Then $hours = 24
   If $last = "" Then Return True
   Local $elapsed = _DateDiff("h", $last, _NowCalc())
   If @error <> 0 Then Return True
   If $elapsed >= $hours Then Return True
   Return False

EndFunc

Func _BDSClockReached($hhmm)

   Local $parts = StringSplit(StringStripWS($hhmm, 3), ":")
   If $parts[0] < 2 Then Return False
   If StringRegExp($parts[1], "^\d+$") = 0 Then Return False
   If StringRegExp($parts[2], "^\d+$") = 0 Then Return False
   Local $target = Number($parts[1]) * 60 + Number($parts[2])
   If $target < 0 Or $target > (23 * 60 + 59) Then Return False
   Local $now = Number(@HOUR) * 60 + Number(@MIN)
   If $now >= $target Then Return True
   Return False

EndFunc

Func _BDSUpdateStamp($file)

   Local $h = FileOpen($file, 2)
   FileWrite($h, _NowCalc())
   FileClose($h)

EndFunc
