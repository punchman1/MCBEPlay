Func _BDSSave($auto_backup=False)

   Local $function_name = "Save Server"
   _log($function_name & " Function Started", $function_name, False, True)
   _BDSBusy(True)

   ; Hold, then poll save query until the file list arrives. Mojang documents
   ; that the first query often returns "A previous save has not been completed."
   $save_hold_active = True
   _BDSStdIn("save hold" & @LF)
   Sleep(500)
   _BDSProcessOutput(True)

   Local $accumulated = ""
   Local $try = 1
   Local $success = False
   While $try <= 30
	  _log("Sending Save Query [" & $try & "/30]", $function_name, False, True)
	  _BDSStdIn("save query" & @LF)
	  Sleep(500)
	  $accumulated &= _BDSProcessOutput(True)
	  If StringInStr($accumulated, "level.dat:", 0) > 0 Then
		 Sleep(300)
		 $accumulated &= _BDSProcessOutput(True)
		 $success = True
		 ExitLoop
	  EndIf
	  $try = $try + 1
	  Sleep(1000)
   WEnd

   If $success = True Then
	  _log("Save query returned a file list", $function_name, False, True)
	  If $auto_backup = True Then
		 _log("Starting backup", $function_name, False, True)
		 _BDSBackup($accumulated)
	  EndIf
   Else
	  _log("Save query did not return a file list", $function_name, True)
	  _BDSServerChat("Error Saving")
   EndIf

   ; Always release the hold, including when the query or backup failed.
   ; The copy must finish before this. Files can change again after resume.
   _BDSReleaseSaveHold()

   If $success = True And $auto_backup = False Then
	  _BDSServerChat("Saved")
   EndIf

   ; Create saved file
   If FileExists($saved_file) Then
	  FileDelete($saved_file)
   EndIf
   _log("Creating Saved File", $function_name, False, True)
   $oFile = FileOpen($saved_file, 2)
   FileClose($oFile)

   _log("Setting BDS Busy = False", $function_name, False, True)
   _BDSBusy(False)

EndFunc
