Func _BDSRollback()

   Local $function_name = "Rollback Server"
   _log($function_name & " Function Started", $function_name, False, True)

   _BDSBusy(True)

   Local $world = $world_dir & "\" & $level_name
   Local $db_path = $world & "\db"
   Local $modified = FileGetTime($db_path, $FT_MODIFIED, $FT_STRING)
   Local $failed_copy = $save_dir & "\FAILED_" & $level_name & "-" & $modified

   ; Keep a copy of the current world before anything is deleted.
   Local $copied = DirCopy($world, $failed_copy, 1)
   If $copied == 0 Then
	  _log("Error copying world directory to failed saves", $function_name, True)
	  _BDSResponse("Error copying world directory to failed saves")
	  _BDSBusy(False)
	  Return False
   EndIf

   Local $save_file = _BDSSelectRollbackSave()
   If $save_file = "" Then
	  _log("No complete backup to roll back to. The live world was not changed.", $function_name, True)
	  _BDSResponse("No complete backup available. Live world was not changed.")
	  _BDSBusy(False)
	  Return False
   EndIf
   _log("Selected complete backup: " & $save_file, $function_name, False, True)

   ; Stage and validate before the live db is touched.
   Local $stage = $tmp_dir & "\rollback_stage"
   DirRemove($stage, 1)
   If DirCopy($save_dir & "\" & $save_file, $stage, 1) = 0 Then
	  _log("Could not stage " & $save_file & ". The live world was not changed.", $function_name, True)
	  _BDSResponse("Could not stage the backup. Live world was not changed.")
	  _BDSBusy(False)
	  Return False
   EndIf
   If Not FileExists($stage & "\level.dat") Or Not FileExists($stage & "\db") Then
	  _log("Staged backup is missing level.dat or db. The live world was not changed.", $function_name, True)
	  DirRemove($stage, 1)
	  _BDSResponse("Staged backup is incomplete. Live world was not changed.")
	  _BDSBusy(False)
	  Return False
   EndIf

   _log("Staged backup validated. Replacing the live world db.", $function_name, False, True)
   If FileExists($db_path) Then
	  If DirRemove($db_path, 1) = 0 Then
		 _log("Unable to delete existing DB data. The live world was left in place.", $function_name, True)
		 DirRemove($stage, 1)
		 _BDSResponse("Unable to delete existing DB data")
		 _BDSBusy(False)
		 Return False
	  EndIf
   EndIf

   Local $copy = DirCopy($stage, $world, $FC_OVERWRITE)
   If $copy == 0 Then
	  _log("Error copying staged save onto the world. Restoring the pre-rollback copy.", $function_name, True)
	  DirCopy($failed_copy, $world, 1)
	  DirRemove($stage, 1)
	  _BDSResponse("Error copying save data to world directory")
	  _BDSBusy(False)
	  Return False
   EndIf
   _log("Save data copied to world directory succesfully", $function_name, False, True)
   DirRemove($stage, 1)

   Local $rolled = $save_dir & "\ROLLBACK_" & $save_file
   _log("Renaming rolled back save folder to add ROLLBACK_ prefix", $function_name, False)
   If DirMove($save_dir & "\" & $save_file, $rolled, $FC_OVERWRITE) = 0 Then
	  _log("Error renaming rolled back save", $function_name, True)
	  _BDSResponse("Error renaming rolled back save")
	  _BDSBusy(False)
	  Return False
   EndIf

   _log("Rollback Completed Succesfully", $function_name, False, True)
   _BDSResponse("Rollback Completed Succesfully")
   _BDSBusy(False)
   Return True

EndFunc

Func _BDSSelectRollbackSave()

   Local $saves = _FileListToArrayRec($save_dir, "*|FAILED_*;ROLLBACK_*", $FLTAR_FOLDERS, $FLTAR_NORECUR, $FLTAR_SORT, $FLTAR_NOPATH)
   If Not IsArray($saves) Then Return ""
   Local $best = ""
   Local $best_time = 0
   Local $i
   For $i = 1 To $saves[0]
	  Local $name = $saves[$i]
	  If StringRight($name, 1) = "\" Then $name = StringTrimRight($name, 1)
	  Local $folder = $save_dir & "\" & $name
	  If _BDSBackupIsComplete($folder) = False Then
		 _log("Skipping partial backup " & $name, "Rollback Server", False, True)
		 ContinueLoop
	  EndIf
	  Local $created = FileGetTime($folder, $FT_CREATED, 1)
	  If $created > $best_time Then
		 $best_time = $created
		 $best = $name
	  EndIf
   Next
   Return $best

EndFunc
