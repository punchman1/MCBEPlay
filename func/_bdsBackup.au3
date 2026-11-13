; Makes a backup of the world during save hold.
; Modern save query lines look like:
;   [date INFO] World Name/db/CURRENT:16, World Name/db/MANIFEST-000001:120, World Name/level.dat:2000
; Paths are relative to the worlds folder. The number is the byte length to keep.
; BDS-2733 (files locked during hold) was closed in 2022. Copy the whole file, then truncate.

Func _BDSBackup($response)

   Local $function_name = "Backup Server"
   _log($function_name & " Function Started", $function_name, False, True)

   _BDSBusy(True)
   FileDelete($error_file)
   _BDSServerChat("Backup Started")

   Local $backup_timer = TimerInit()
   Local $error_found = False

   Dim $src_files[1]
   Dim $rel_files[1]
   Dim $file_lengths[1]
   Local $count = _BDSCollectSaveEntries($response, $src_files, $rel_files, $file_lengths)
   If $count < 1 Then
	  Local $preview = $response
	  If StringLen($preview) > 400 Then
		 $preview = StringLeft($preview, 400)
	  EndIf
	  _log("Save query file list was empty or unreadable: " & $preview, $function_name, True)
	  $error_found = True
   Else
	  _log("Save query listed " & $count & " files", $function_name, False, True)
   EndIf

   Local $timestamp = @YEAR & @MON & @MDAY & @HOUR & @MIN & @SEC
   Local $dst_file = $level_name & "-" & $timestamp & "\"
   Local $dst_dir = $save_dir & "\" & $dst_file

   Dim $dst_files[1]
   Dim $req_lengths[1]

   If $error_found = False Then
	  _log("Copying Files", $function_name, False, True)
	  For $i = 1 To UBound($src_files) - 1
		 Local $src_path = $src_files[$i]
		 Local $rel = $rel_files[$i]
		 Local $dst_path = $dst_dir & $rel

		 If Not FileExists($src_path) Then
			_log("Source file does not exist: " & $src_path, $function_name, True)
			$error_found = True
			ContinueLoop
		 EndIf

		 _ArrayAdd($dst_files, $dst_path)
		 _ArrayAdd($req_lengths, $file_lengths[$i])
		 _log("Copying " & $src_path & " -> " & $dst_path, $function_name, False, False)
		 If FileCopy($src_path, $dst_path, 9) < 1 Then
			_log("Error Copying File: " & $src_path & " > " & $dst_path, $function_name, True)
			$error_found = True
		 EndIf
	  Next
   EndIf

   Local $result = "Files copied"
   If $error_found = True Then
	  $result = "Files copied with errors"
   EndIf
   _BDSResponse($result)

   _log("Truncating Copied Files", $function_name, False, True)
   For $i = 1 To UBound($dst_files) - 1
	  Local $file = $dst_files[$i]
	  Local $req_size = Number($req_lengths[$i])
	  Local $dst_size = FileGetSize($file)

	  If $req_size < 1 Then
		 _log("Save query reported an empty length for " & $file, $function_name, True)
		 $error_found = True
		 ContinueLoop
	  EndIf

	  If $dst_size < $req_size Then
		 _log("Copied file is shorter than save query (" & $dst_size & " < " & $req_size & "): " & $file, $function_name, True)
		 $error_found = True
		 ContinueLoop
	  EndIf

	  If $dst_size > $req_size Then
		 Local $low = $req_size
		 Local $high = 0
		 If $req_size >= 4294967296 Then
			$high = Int($req_size / 4294967296)
			$low = $req_size - ($high * 4294967296)
		 EndIf
		 Local $hFile = _WinAPI_CreateFile($file, 2, 4)
		 If $hFile = 0 Then
			_log("Could not open " & $file & " to truncate", $function_name, True)
			$error_found = True
			ContinueLoop
		 EndIf
		 _WinAPI_SetFilePointer($hFile, $low, 0, $high)
		 _WinAPI_SetEndOfFile($hFile)
		 _WinAPI_CloseHandle($hFile)

		 Local $dFileSize = FileGetSize($file)
		 If $req_size <> $dFileSize Then
			_log("Error truncating " & $file & " from " & $dst_size & " bytes to " & $req_size & " bytes", $function_name, True)
			$error_found = True
		 Else
			_log("Truncated " & $file & " from " & $dst_size & " bytes to " & $req_size & " bytes", $function_name, False, False)
		 EndIf
	  EndIf
   Next

   Local $backup_time = TimerDiff($backup_timer)
   $backup_time = Floor($backup_time / 1000)

   If $error_found Then
	  $result = "Backup process finished with errors [" & $backup_time & " seconds]"
	  _log($result, $function_name, True)
	  _log("Renaming Backup with FAILED_ prefix", $function_name, False, True)
	  Local $fail_dir = $save_dir & "\FAILED_" & $dst_file
	  If FileExists($dst_dir) Then
		 If DirMove($dst_dir, $fail_dir) < 1 Then
			_log("Error renaming failed backup: " & $dst_dir & " > " & $fail_dir, $function_name, True)
		 EndIf
	  EndIf
	  _BDSServerChat("Error with Backup")
   Else
	  $result = "Backup process finished succesfully [" & $backup_time & " seconds]"
	  _log($result, $function_name, False, True)
	  If $backup_time > 10 Then
		 _BDSServerChat("Backup Complete [" & $backup_time & " seconds]")
	  Else
		 _BDSServerChat("Backup Complete")
	  EndIf
   EndIf

   If FileExists($backedup_file) Then
	  FileDelete($backedup_file)
   EndIf
   Local $oFile = FileOpen($backedup_file, 2)
   FileClose($oFile)

   _BDSResponse($result)
   _BDSBusy(False)

EndFunc

; Fills parallel arrays (index 0 unused, matching _ArrayAdd). Returns the file count.
Func _BDSCollectSaveEntries($response, ByRef $src_files, ByRef $rel_files, ByRef $file_lengths)

   Local $text = StringReplace($response, @CR, "")
   Local $lines = StringSplit($text, @LF)
   Local $list = ""
   Local $i
   For $i = 1 To $lines[0]
	  If StringInStr($lines[$i], "level.dat") > 0 And StringInStr($lines[$i], ":") > 0 Then
		 $list = $lines[$i]
		 ; A read can split the single file-list line. If this piece does not
		 ; end on a size, keep the following piece.
		 Local $tail = StringRight(StringStripWS($list, 3), 1)
		 If $i < $lines[0] And StringRegExp($tail, "\d") = 0 Then
			$list &= $lines[$i + 1]
		 EndIf
		 ExitLoop
	  EndIf
   Next

   ; Drop a leading [timestamp LEVEL] so colons in the clock are not paths.
   $list = StringRegExpReplace($list, "^\s*\[[^\]]*\]\s*", "")

   Local $parts = StringSplit($list, ",")
   Local $count = 0
   For $i = 1 To $parts[0]
	  Local $entry = StringStripWS($parts[$i], 3)
	  If $entry = "" Then ContinueLoop
	  ; Last colon separates the path from the byte size. Paths use "/" and do not contain ":".
	  Local $colon = 0
	  Local $nth = 1
	  While 1
		 Local $found = StringInStr($entry, ":", 0, $nth)
		 If $found = 0 Then ExitLoop
		 $colon = $found
		 $nth = $nth + 1
	  WEnd
	  If $colon < 2 Then ContinueLoop
	  Local $path = StringLeft($entry, $colon - 1)
	  Local $size = StringMid($entry, $colon + 1)
	  If StringRegExp($size, "^\d+$") = 0 Then ContinueLoop
	  $path = StringReplace($path, "/", "\")
	  While StringLeft($path, 1) = "\"
		 $path = StringMid($path, 2)
	  WEnd
	  If StringInStr($path, "..") > 0 Then ContinueLoop

	  Local $src = ""
	  Local $rel = ""
	  If _BDSResolveSaveEntry($path, $src, $rel) = False Then ContinueLoop
	  _ArrayAdd($src_files, $src)
	  _ArrayAdd($rel_files, $rel)
	  _ArrayAdd($file_lengths, $size)
	  $count = $count + 1
   Next
   Return $count

EndFunc

; $path uses backslashes and is relative to worlds/ on modern BDS
; (WorldName\db\file) or relative to the world folder on older BDS (db\file).
; $rel is the path inside the world folder, which is what a restore copies back.
Func _BDSResolveSaveEntry($path, ByRef $src, ByRef $rel)

   Local $raw = $path
   If StringLeft(StringLower($raw), 7) = "worlds\" Then
	  $raw = StringMid($raw, 8)
   EndIf

   Local $level = $level_name
   Local $world = $world_dir & "\" & $level

   If $level <> "" And StringLeft($raw, StringLen($level) + 1) = $level & "\" Then
	  $rel = StringMid($raw, StringLen($level) + 2)
	  $src = $world & "\" & $rel
	  Return True
   EndIf

   If $level <> "" And FileExists($world & "\" & $raw) Then
	  $rel = $raw
	  $src = $world & "\" & $raw
	  Return True
   EndIf

   Local $slash = StringInStr($raw, "\")
   If $slash > 1 Then
	  Local $head = StringLeft($raw, $slash - 1)
	  Local $tail = StringMid($raw, $slash + 1)
	  If $tail <> "" And FileExists($world_dir & "\" & $head & "\" & $tail) Then
		 $rel = $tail
		 $src = $world_dir & "\" & $head & "\" & $tail
		 Return True
	  EndIf
	  If $tail <> "" And $level <> "" And StringLower($head) = StringLower($level) Then
		 $rel = $tail
		 $src = $world & "\" & $tail
		 Return True
	  EndIf
	  ; Query used the real world-folder name, which can differ from level-name.
	  If $tail <> "" And FileExists($world_dir & "\" & $head) Then
		 $rel = $tail
		 $src = $world_dir & "\" & $head & "\" & $tail
		 Return True
	  EndIf
   EndIf

   ; Older save query output omitted the world folder: db\file or level.dat.
   If $level <> "" And StringInStr($raw, "..") = 0 Then
	  $rel = $raw
	  $src = $world & "\" & $raw
	  Return True
   EndIf
   Return False

EndFunc
