; Global Variables
Global $MCBEPlay = "MCBEPlay v3.6-cpx"
Global $options_file = @ScriptDir & "\options.txt"	; Define Name of Options File

; Icon File
Global $icon_file = @ScriptDir & "\icon.ico"
; Icon is embedded by compile.ps1 (/icon). Aut2Exe does not understand
; #AutoIt3Wrapper directives; SciTE's wrapper does, if you compile from SciTE.

; Directories
Global $tmp_dir = @ScriptDir & "\tmp"	; Set Temporary Directory

If Not FileExists($tmp_dir) Then
   DirCreate($tmp_dir)
EndIf

; Files
Global $error_file = $tmp_dir & "\server_error.txt" 		; Server status: Offline, Online, Error
Global $command_file = $tmp_dir & "\command.txt" 			; File used to send commands to server. Should only exist when sending a command
Global $response_file = $tmp_dir & "\response.txt" 			; File used to receive data from the server.
Global $backup_file = $tmp_dir & "\backup.txt" 				; File used for the server to tell the gui to make a full backup.
Global $member_file = $tmp_dir & "\members.txt" 			; File used to store which members are currently on the server
Global $working_file = $tmp_dir & "\working.txt"			; File used for BDS to indicate that things are processing (Busy signal)
Global $save_file = $tmp_dir & "\last_save.txt"				; File used for GUI to see when the last save was
Global $saved_file = $tmp_dir & "\saved_file.txt"				; File used for BDS to indicate when a save has completed


; ### UPDATE 6/2/2020
Global $backup_file = $tmp_dir & "\last_backup.txt"			; File used for GUI to see when the last backup was
Global $backedup_file = $tmp_dir & "\backup_finished.txt"		; File used for BDS to indicate when a backup has completed
Global $restart_file = $tmp_dir & "\restart.txt"		; File used for BDS to indicate when a backup has completed
; ### UPDATE 6/2/2020

Global $bds_true_save_time									; Used by BDS to get the actual last physical save time (used for player disconnect saving)

; Date and Time Globals
Global $date = @YEAR&@MON&@MDAY		; YYYYMMDD
Global $timestamp = @YEAR&@MON&@MDAY&@HOUR&@MIN&@SEC ; YYYYMMDDHHMMSS

; Server Globals
Global $server_status = False 		; False = Offline, True = Online
Global $server_error = False		; False = No Error, Other = Get from error file ERROR, CRASH, UNRESPONSIVE
Global $server_working = False		; False = Idle, True = Working
Global $PID = 0						; cmd.exe started by this instance (stdin/stdout)
Global $server_pid = 0				; bedrock_server.exe PID spawned by this instance
Global $server_pid_file = $tmp_dir & "\server.pid"
Global $save_hold_active = False	; True between save hold and save resume
Global $members_online = 0			; Number of players connected
Global $members_online_last = 0		; For checking if a member has just joined or left (autosave)
Global $min_save_time = 2			; Minutes since last save when a new save is allowed to trigger
Global $console_log					; Most Recent Console [Active]
Global $console_size = 0			; Console Log File Size - Required for checking if console log changed

Global $verbose_logging = False		; Log Everything!
Global $debug_mode = False			; Use AU3 instead of EXE
Global $server_stopped = False		; If true then keep alive won't engage

; Keep Alive System
Global $keepalive_timer = 0			; Used for trigger cooldown
Global $keepalive_triggered = False	; Used for spam prevention
Global $chat_triggered = False		; Used for spam prevention


; Set max vars
$max_debug_lines = 30
$max_console_lines = 100

; BDS auto-update (3.6). Defaults live in inc/options.au3 so a missing key is safe.
Global $update_check_file = $tmp_dir & "\last_update_check.txt"
Global $update_fail_file = $tmp_dir & "\update_check_failed.txt"
Global $updating_file = $tmp_dir & "\updating.txt"
Global $update_in_progress = False
Global $update_arm_timer = TimerInit()