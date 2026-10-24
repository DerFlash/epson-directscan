use framework "Foundation"
use scripting additions

-- Pure helpers are kept before lifecycle handlers for permission-free tests.
on jsonText(v)
	set d to current application's NSJSONSerialization's dataWithJSONObject:v options:0 |error|:(missing value)
	if d is missing value then error "JSON encoding failed" number 1001
	return (current application's NSString's alloc()'s initWithData:d encoding:4) as text
end jsonText

on decodeJSON(t)
	set d to (current application's NSString's stringWithString:t)'s dataUsingEncoding:4
	set v to current application's NSJSONSerialization's JSONObjectWithData:d options:0 |error|:(missing value)
	if v is missing value then error "JSON decoding failed" number 1002
	return v
end decodeJSON

on getKey(v, k)
	set x to v's objectForKey:k
	if x is missing value then return missing value
	if (x's isEqual:(current application's NSNull's null())) as boolean then return missing value
	return x
end getKey

on evaluateBridge(sourceText, requestValue)
	set payload to my jsonText(requestValue)
	set outputText to run script (sourceText & linefeed & "handleRequest(" & payload & ");") in "JavaScript"
	return my decodeJSON(outputText as text)
end evaluateBridge

on safePoint(targetPosition, targetSize, windowPosition, windowSize)
	if (count targetPosition) is not 2 or (count targetSize) is not 2 then return missing value
	if item 1 of targetSize <= 0 or item 2 of targetSize <= 0 then return missing value
	-- The whole target must lie inside the current window, not only its center.
	if item 1 of targetPosition < item 1 of windowPosition or item 2 of targetPosition < item 2 of windowPosition then return missing value
	if (item 1 of targetPosition) + (item 1 of targetSize) > (item 1 of windowPosition) + (item 1 of windowSize) then return missing value
	if (item 2 of targetPosition) + (item 2 of targetSize) > (item 2 of windowPosition) + (item 2 of windowSize) then return missing value
	return {(item 1 of targetPosition) + (item 1 of targetSize) / 2, (item 2 of targetPosition) + (item 2 of targetSize) / 2}
end safePoint

on sameIdentity(a, b)
	return processIDValue of a is processIDValue of b and windowIdentity of a is windowIdentity of b and rootIdentity of a is rootIdentity of b and sheetNumber of a is sheetNumber of b
end sameIdentity

on isOutputSuffix(t)
	if class of t is not text then return false
	repeat with extensionText in {".jpg", ".jpeg", ".pdf", ".png", ".tif", ".tiff", ".bmp"}
		set suffixText to contents of extensionText
		if t is suffixText then return true
		if t ends with suffixText then
			set counterPart to text 1 thru ((length of t) - (length of suffixText)) of t
			if (length of counterPart) < 2 or counterPart does not start with "_" then return false
			repeat with aCharacter in characters 2 thru -1 of counterPart
				if contents of aCharacter is not in "0123456789" then return false
			end repeat
			return true
		end if
	end repeat
	return false
end isOutputSuffix

on runNativeScript(jsSource, x, y, targetPID)
	-- Integer-only invocation is locale independent; no user text becomes code.
	set invocation to "postVerifiedClick([" & (x as integer) & "," & (y as integer) & "," & (targetPID as integer) & "]);"
	return run script (jsSource & linefeed & invocation) in "JavaScript"
end runNativeScript

on friendlyStatus(codeValue)
	if codeValue is "disabled" then return "Automatik ist ausgeschaltet."
	if codeValue is "waiting_for_idle" then return "Wartet auf die freie ScanSmart-Startansicht. Einen offenen Scan bitte selbst abschließen oder abbrechen."
	if codeValue is "ready" then return "Bereit für den nächsten Scan über die Scannertaste."
	if codeValue is "saved" then return "Die erwarteten JPGs wurden gespeichert und geprüft."
	if codeValue is "opening_save" or codeValue is "awaiting_transition" then return "Wartet auf den nächsten ScanSmart-Speicherschritt."
	if codeValue is "setting_destination" then return "Setzt den gewählten Ablageordner und prüft die Rückmeldung."
	if codeValue is "saving" or codeValue is "verifying_files" then return "Prüft, ob alle erwarteten JPGs vollständig im Ablageordner liegen."
	if codeValue is "dry_run_open_save" then return "Probelauf: Würde die Speichereinstellungen öffnen. Es wird nichts angeklickt."
	if codeValue is "dry_run_set_destination" then return "Probelauf: Würde den gewählten Ordner prüfen und JPGs speichern. Es wird nichts verändert."
	if codeValue is "invalid_destination" then return "Pause: Der gewählte Ordner fehlt oder ist nicht beschreibbar. Bitte einen erreichbaren Ordner wählen."
	if codeValue is "target_exists" then return "Pause: Eine erwartete Zieldatei ist bereits vorhanden. Bitte Dateien und ScanSmart-Dateinamen prüfen."
	if codeValue is "permission_denied" then return "Pause: Die App benötigt ihre macOS-Bedienfreigaben. Öffne ‚Freigaben öffnen‘ und folge der Anleitung."
	if codeValue is "destination_readback" or codeValue is "destination_rejected" then return "Pause: ScanSmart hat den gewählten Ordner nicht eindeutig übernommen. Bitte manuell prüfen."
	if codeValue is "export_timeout" then return "Pause: Der Speichervorgang konnte nicht bestätigt werden. Bitte vorhandene JPGs prüfen, bevor du neu scannst."
	if codeValue is "transition_timeout" then return "Pause: ScanSmart hat den erwarteten Speicherschritt nicht rechtzeitig geöffnet. Bitte die Ansicht prüfen."
	if codeValue is "invalid_metadata" or codeValue is "counter_overflow" then return "Pause: Dateiformat, Dateiname oder Bildanzahl wurden nicht eindeutig erkannt. Bitte JPG-Einstellungen prüfen."
	if codeValue is "unsupported_view" or codeValue is "ui_changed" then return "Pause: ScanSmart zeigt einen unerwarteten Dialog oder eine veränderte Ansicht. Bitte selbst prüfen und schließen."
	if codeValue is "storage_error" then return "Pause: Lokale Einstellungen konnten nicht sicher gelesen oder geschrieben werden. Bitte die Anleitung zur Wiederherstellung prüfen."
	return "Pause: Der Schritt konnte nicht sicher ausgeführt werden. Bitte ScanSmart und die gespeicherten Dateien prüfen."
end friendlyStatus

-- Application lifecycle
on run
	try
		set r to my bridge({op:"startup"})
		if not (my getKey(r, "ok") as boolean) then
			my showStatus(r)
			return
		end if
		set cfg to my getKey(r, "settings")
		if my getKey(cfg, "destination") is missing value then
			display dialog "Diese Beta übernimmt die Speicher-Schritte in der deutschen Epson-ScanSmart-Oberfläche. Wähle zuerst einen JPG-Zielordner und aktiviere sie anschließend über das App-Symbol. Starte keine zweite Scan-Automatik gleichzeitig." with title "ScanSmart AutoSave Beta" buttons {"Später", "Einrichten"} default button "Einrichten"
			if button returned of result is "Einrichten" then my settingsMenu()
		end if
	on error
		display dialog "Die Beta konnte ihre lokalen Einstellungen nicht laden. Bitte prüfe die Anleitung und starte sie erneut. Es wurde kein Scan bedient." with title "ScanSmart AutoSave Beta" buttons {"OK"}
	end try
end run

on reopen
	my settingsMenu()
end reopen

on idle
	try
		set beforeState to my bridge({op:"getSettings"})
		set cfg to my getKey(beforeState, "settings")
		if cfg is missing value then return 2
		if not (my getKey(cfg, "enabled") as boolean) then return 2
		if (my getKey(beforeState, "phase") as text) is "paused" then return 2
		set captureValue to my readCapture()
		set r to my bridge({op:"tick", snapshot:snapshotData of captureValue})
		set actionValue to my getKey(r, "action")
		if actionValue is not missing value then
			set r to my performAction(actionValue, captureValue)
		end if
		if (my getKey(r, "phase") as text) is "paused" and (my getKey(beforeState, "phase") as text) is not "paused" then
			display notification "Automatik pausiert. Öffne das App-Symbol für Status und Hilfe." with title "ScanSmart AutoSave Beta"
		end if
	on error number n
		try
			set codeValue to "adapter_error"
			if n is -1743 or n is -1719 or n is -25211 then set codeValue to "permission_denied"
			my bridge({op:"pause", errorCode:codeValue})
			display notification "Automatik pausiert. Öffne das App-Symbol und prüfe Status und Freigaben." with title "ScanSmart AutoSave Beta"
		end try
	end try
	return 1
end idle

on bridge(requestValue)
	set resourcePath to (path to me as text) & "Contents:Resources:"
	set coreSource to read file (resourcePath & "core.js") as «class utf8»
	set runtimeSource to read file (resourcePath & "runtime.js") as «class utf8»
	return my evaluateBridge(coreSource & linefeed & runtimeSource, requestValue)
end bridge

on settingsMenu()
	activate
	try
		set r to my bridge({op:"getSettings"})
		set selectionValue to choose from list {"Status anzeigen", "Ablageordner wählen", "Automatik aktivieren", "Automatik pausieren", "Trockenlauf einschalten", "Trockenlauf ausschalten", "Fehler zurücksetzen", "Freigaben öffnen", "Beenden"} with title "ScanSmart AutoSave Beta" with prompt "Einstellungen (Scanauflösung, Seiten und Dateinamen stellst du in ScanSmart ein):" default items {"Status anzeigen"}
		if selectionValue is false then return
		set choiceValue to item 1 of selectionValue
		if choiceValue is "Ablageordner wählen" then
			set selectedFolder to choose folder with prompt "JPG-Ablageordner für ScanSmart AutoSave wählen:"
			set r to my bridge({op:"setSettings", patch:{destination:POSIX path of selectedFolder}})
		else if choiceValue is "Automatik aktivieren" then
			set r to my bridge({op:"setSettings", patch:{enabled:true}})
		else if choiceValue is "Automatik pausieren" then
			set r to my bridge({op:"setSettings", patch:{enabled:false}})
		else if choiceValue is "Trockenlauf einschalten" then
			set r to my bridge({op:"setSettings", patch:{dryRun:true}})
		else if choiceValue is "Trockenlauf ausschalten" then
			set r to my bridge({op:"setSettings", patch:{dryRun:false}})
		else if choiceValue is "Fehler zurücksetzen" then
			set r to my bridge({op:"reset"})
		else if choiceValue is "Freigaben öffnen" then
			display dialog "Erlaube dieser App die Bedienung von System Events sowie die Bedienungshilfen (neuere macOS-Versionen: Gerätesteuerung und Datenzugriff). Das ermöglicht die zwei ScanSmart-Speicherschritte. Du kannst die Freigaben jederzeit widerrufen. Codex benötigt dafür keine Freigabe. Nach einem Neubau der App muss der alte Eintrag eventuell entfernt und die neue App hinzugefügt werden." with title "ScanSmart AutoSave Beta" buttons {"OK"} default button "OK"
			open location "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
			return
		else if choiceValue is "Beenden" then
			quit
			return
		end if
		my showStatus(r)
	on error number n
		if n is not -128 then display dialog "Die Einstellung konnte nicht übernommen werden. Prüfe den Ablageordner und die Anleitung." with title "ScanSmart AutoSave Beta" buttons {"OK"}
	end try
end settingsMenu

on showStatus(r)
	set cfg to my getKey(r, "settings")
	set folderText to "Noch nicht gewählt"
	set modeText to "Aus"
	set dryText to "Aus"
	if cfg is not missing value then
		if my getKey(cfg, "destination") is not missing value then set folderText to my getKey(cfg, "destination") as text
		if my getKey(cfg, "enabled") as boolean then set modeText to "Ein"
		if my getKey(cfg, "dryRun") as boolean then set dryText to "Ein"
	end if
	set statusText to my friendlyStatus(my getKey(r, "status") as text)
	set codeValue to my getKey(r, "errorCode")
	if codeValue is not missing value then set statusText to statusText & linefeed & "Fehlercode: " & (codeValue as text) & linefeed & "Prüfe den Scan und schließe offene Speicher-/Fehlerdialoge selbst. Wähle danach ‚Fehler zurücksetzen‘. Ein unklarer Scan wird nicht erneut gespeichert."
	display dialog "Automatik: " & modeText & linefeed & "Trockenlauf: " & dryText & linefeed & "Ordner: " & folderText & linefeed & linefeed & statusText & linefeed & linefeed & "Nach Aktivieren, Ordnerwechsel oder Zurücksetzen erst einen offenen Scan selbst abschließen oder abbrechen. Danach die nächste Karte am Scanner starten." with title "ScanSmart AutoSave Beta" buttons {"OK"} default button "OK"
end showStatus

on emptyCapture(isBlocked)
	return {snapshotData:{foreground:false, blocked:isBlocked, processId:0, windowTitle:"", captions:{}, fields:{}, suffixLabels:{}, saveTargetCount:0, saveEnabled:false, noJob:(not isBlocked)}, processIDValue:0, windowIdentity:0, rootIdentity:0, sheetNumber:0, targetRefs:{}, folderRefs:{}}
end emptyCapture

on readCapture()
	tell application "System Events"
		if not UI elements enabled then error "Permission required" number -25211
		set matches to application processes whose bundle identifier is "com.epson.scan.Epson-ScanSmart"
		if (count matches) is 0 then return my emptyCapture(false)
		if (count matches) is not 1 then return my emptyCapture(true)
		set p to item 1 of matches
		if (count windows of p) is 0 then return my emptyCapture(false)
		set w to window 1 of p
		set subroleText to subrole of w
		if subroleText is "AXDialog" or subroleText is "AXSystemDialog" then return my emptyCapture(true)
		try
			if value of attribute "AXModal" of w is true then return my emptyCapture(true)
		end try
		set attachedSheets to sheets of w
		if (count attachedSheets) > 1 then return my emptyCapture(true)
		set rootValue to w
		if (count attachedSheets) is 1 then set rootValue to item 1 of attachedSheets
		if rootValue is not w then
			if (count sheets of rootValue) > 0 then return my emptyCapture(true)
		end if
		set allElements to entire contents of rootValue
		set foregroundValue to frontmost of p
		set pidValue to unix id of p
		set titleValue to name of w as text
	end tell
	set captionsValue to {}
	set fieldsValue to {}
	set suffixesValue to {}
	set buttonsValue to {}
	set textTargetsValue to {}
	set foldersValue to {}
	set enabledValue to true
	repeat with e in allElements
		tell application "System Events"
			set roleText to role of e
			set valueText to ""
			set nameText to ""
			try
				set valueText to value of e as text
			end try
			try
				set nameText to name of e as text
			end try
			if roleText is "AXStaticText" then
				if valueText is not "" then set end of captionsValue to valueText
				if nameText is not "" and nameText is not valueText then set end of captionsValue to nameText
				set suffixText to valueText
				if suffixText is "" then set suffixText to nameText
				if my isOutputSuffix(suffixText) then set end of suffixesValue to suffixText
				if valueText is "Speichern" or nameText is "Speichern" then set end of textTargetsValue to contents of e
			else if roleText is "AXButton" then
				if nameText is not "" then set end of captionsValue to nameText
				if nameText is "Speichern" then set end of buttonsValue to contents of e
			else if roleText is "AXComboBox" or roleText is "AXTextField" then
				set end of fieldsValue to valueText
				if valueText starts with "/" then set end of foldersValue to contents of e
			end if
		end tell
	end repeat
	set targetsValue to buttonsValue
	if (count targetsValue) is 0 then set targetsValue to textTargetsValue
	if (count buttonsValue) is 1 then
		tell application "System Events" to set enabledValue to enabled of item 1 of buttonsValue
	end if
	set knownJob to captionsValue contains "Aktion wählen" or captionsValue contains "In Computereinstellungen speichern"
	set blockedValue to ((count attachedSheets) > 0 and not knownJob)
	return {snapshotData:{foreground:foregroundValue, blocked:blockedValue, processId:pidValue, windowTitle:titleValue, captions:captionsValue, fields:fieldsValue, suffixLabels:suffixesValue, saveTargetCount:(count targetsValue), saveEnabled:enabledValue, noJob:(not knownJob and not blockedValue)}, processIDValue:pidValue, windowIdentity:w, rootIdentity:rootValue, sheetNumber:(count attachedSheets), processRef:p, targetRefs:targetsValue, folderRefs:foldersValue}
end readCapture

on performAction(actionValue, oldCapture)
	set actionID to my getKey(actionValue, "id") as text
	try
		set fresh to my readCapture()
		if not my sameIdentity(oldCapture, fresh) then error "Changed window" number 1101
		set permissionResult to my bridge({op:"canDispatch", actionId:actionID, snapshot:snapshotData of fresh})
		if not (my getKey(permissionResult, "allowed") as boolean) then error "Guard refused" number 1102
		set actionType to my getKey(actionValue, "type") as text
		set p to processRef of fresh
		tell application "System Events"
			if not frontmost of p then error "Background" number 1103
			if window 1 of p is not windowIdentity of fresh then error "Changed window" number 1104
			if (count sheets of window 1 of p) is not sheetNumber of fresh then error "Changed sheet" number 1105
		end tell
		if actionType is "setDestination" then
			if (count folderRefs of fresh) is not 1 then error "Ambiguous folder" number 1106
			set folderTarget to item 1 of folderRefs of fresh
			set destinationValue to my getKey(actionValue, "destination") as text
			tell application "System Events"
				if not frontmost of p then error "Background" number 1103
				set value of folderTarget to destinationValue
				if (value of folderTarget as text) is not destinationValue then error "Folder readback failed" number 1107
			end tell
		else if actionType is "openSave" or actionType is "save" then
			if (count targetRefs of fresh) is not 1 then error "Ambiguous Save" number 1108
			set t to item 1 of targetRefs of fresh
			tell application "System Events"
				set targetName to ""
				set targetValue to ""
				try
					set targetName to name of t as text
				end try
				try
					set targetValue to value of t as text
				end try
				if targetName is not "Speichern" and targetValue is not "Speichern" then error "Changed target" number 1109
				if role of t is "AXButton" then
					if not enabled of t then error "Disabled Save" number 1110
				end if
				set pointValue to my safePoint(position of t, size of t, position of window 1 of p, size of window 1 of p)
				if pointValue is missing value then error "Invalid geometry" number 1111
				if not frontmost of p then error "Background" number 1103
				if window 1 of p is not windowIdentity of fresh then error "Changed window" number 1104
				if (count sheets of window 1 of p) is not sheetNumber of fresh then error "Changed sheet" number 1105
			end tell
			my nativeClick(item 1 of pointValue, item 2 of pointValue, processIDValue of fresh)
		else
			error "Unknown action" number 1112
		end if
		return my bridge({op:"reportAction", actionId:actionID, success:true})
	on error number n
		set errorValue to "ui_changed"
		if n is 1107 then set errorValue to "destination_rejected"
		if n is -1743 or n is -25211 then set errorValue to "permission_denied"
		return my bridge({op:"reportAction", actionId:actionID, success:false, errorCode:errorValue})
	end try
end performAction

on nativeClick(x, y, targetPID)
	set sourcePath to (path to me as text) & "Contents:Resources:native-click.js"
	set jsSource to read file sourcePath as «class utf8»
	return my runNativeScript(jsSource, x, y, targetPID)
end nativeClick
