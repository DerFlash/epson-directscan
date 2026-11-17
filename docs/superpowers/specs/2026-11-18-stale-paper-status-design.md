# Scanner-Start trotz veralteter Papiermeldung

## Befund

Sechs akzeptierte Tastendrücke endeten vor `scan_started` mit null Seiten.
ICA und die direkte Epson-6.7.84-Abfrage meldeten auch nach erneutem Einlegen
eines normalen Blatts `documentLoaded == false`, vor und nach bestätigter
Steuerungsübernahme. Ein anschließender Scanauftrag über macOS Digitale Bilder
lieferte dennoch ein vollständiges JPEG mit 2480 × 3508 Pixeln (300 dpi/A4).
Die negative Vorabmeldung ist daher für diesen Scanweg kein zuverlässiger
Abbruchgrund. Die ICA-Header beschreiben Papiererkennung ausdrücklich als
abhängig von der Erkennungsfähigkeit des Treibermoduls.

## Verhalten

Nach einem akzeptierten physischen Tastendruck und bestätigter Bereitschaft
wird genau ein Scanauftrag an den Treiber übergeben. Eine negative gecachte
Papiermeldung bleibt Diagnoseinformation. Empfangene Seiten und tatsächliche
Treiberfehler entscheiden über das Ergebnis. Dies gilt für ICA-Einzelscans
und native bereits scharfgeschaltete Hüllen-/Einzugsaufträge.

Die Alternative, auf Statusaktualisierungen zu warten, kann einen dauerhaft
falschen Cache nicht auflösen. Ein unbemerkter Wechsel auf kontinuierlichen
Einzug würde Ausgabe und Bedienung des gewählten Profils verändern.

## Grenzen

Keine Änderung an physischer Autorisierung, Bereitschaft, Scanner-Sperren,
Elternprozess-Prüfung, Stop/Abbruch, 15-Sekunden-Fortschrittsüberwachung,
bestätigter Freigabe, Originalerhalt oder geprüfter Veröffentlichung.
Leere oder fehlgeschlagene Aufträge erzeugen keine erfundene Ausgabe.
Testscans bleiben lokal; keine Dokumentinhalte werden veröffentlicht.
