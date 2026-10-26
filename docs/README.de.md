# Epson ScanSmart AutoSave — 0.1.0-beta.3-dev

GitHub-Projekt: [DerFlash/epson-scansmart-autosave](https://github.com/DerFlash/epson-scansmart-autosave).

**Quellcode-Beta: Ein vollständiger Scan über die Gerätetaste war erfolgreich.**
Die korrigierte App hat am 25.10.2026 eine Karte ohne Mac-Klicks als lesbares JPG
gespeichert: ES-C320W über USB, deutsches Epson ScanSmart 3.7.22 und macOS 27.0.1.
Längere Serien, mehrere aufeinanderfolgende Scans, Zielwechsel mit echten Scans
und das Verhalten nach Neustart sind noch nicht mit Hardware abgenommen.
Andere Sprachen, Modelle, Ansichten, Dateiformate und macOS-Versionen sind
ungeprüft. Unbekannte Ansichten führen zur Pause. Das unabhängige Projekt enthält
keine Epson-Software und benötigt kein Codex.

Die App übernimmt die zwei Speicherschritte für JPG nach einem Scan über die
Scannertaste. Auflösung, Seiten und Dateinamen-Präfix stellst du weiterhin in
ScanSmart ein. Die App holt ScanSmart niemals nach vorn.

## Bauen und installieren

Du brauchst macOS mit den Systemwerkzeugen `osacompile` und `codesign`. Die App
benötigt keine zusätzlichen Laufzeitpakete. Entwicklungstests brauchen Node.js
und Python 3. Im heruntergeladenen Quellcode-Verzeichnis:

```sh
./scripts/test.sh
./scripts/build.sh
./scripts/install.sh
```

Der Build erstellt `build/ScanSmart AutoSave Beta.app`, packt die benötigten
JavaScript-Dateien hinein und signiert sie lokal mit einer Ad-hoc-Signatur.
Er startet und installiert nichts und ändert weder Rechte noch Autostart.
Ein vorhandener Build wird nur mit `./scripts/build.sh --replace` ersetzt.
Optional: `./scripts/build.sh --sign 'DEINE SIGNATURIDENTITÄT'`; das führt keine
Notarisierung durch. Kennung: `org.scansmart.autosave.beta`, Version `0.1.0`,
Build `3`, Beta-Version `0.1.0-beta.3-dev`.

Die Installation kopiert nach `~/Applications`. Vorhandene Apps werden abgelehnt.
Zum bewussten Ersetzen zuerst alle Helfer beenden, dann
`./scripts/install.sh --replace` verwenden. Ein anderes Zielverzeichnis muss
absolut sein, etwa `./scripts/install.sh --destination '/absoluter/Pfad/Applications'`.
Pfade mit Leerzeichen sind unterstützt. Es wird kein Anmeldeobjekt angelegt.
**Niemals zwei Helfer gleichzeitig starten**, auch keinen älteren Helfer oder
separates Vorgängerskript.

Dies ist eine Quellcode-Veröffentlichung. Der lokale Build ist nicht notarisiert.
Eine allgemein herunterladbare Binärdatei bräuchte eine stabile Developer-ID-
Signatur und Notarisierung. Erfolgreiche Tests ersetzen keine Hardware-Abnahme.

## Start, Berechtigungen und erster Scan

1. Starte die installierte App manuell. Sie ist zunächst deaktiviert. Über ihr
   Dock-Symbol öffnest du Zielordner, Aktivieren/Pause, Status, Probelauf und Reset.
2. Wähle einen beschreibbaren Zielordner. Erlaube **dieser App** unter
   Systemeinstellungen → Datenschutz & Sicherheit → Bedienungshilfen den Zugriff
   (auf neueren macOS-Versionen: „Gerätesteuerung und Datenzugriff“).
   Erlaube bei Nachfrage außerdem die Steuerung von System Events unter
   Automation. Rechte für Terminal oder Codex reichen für die eigenständige App
   nicht aus.
3. Schließe bereits wartende Exporte in ScanSmart manuell ab oder brich sie ab.
   Aktiviere zuerst den Probelauf und anschließend den Helfer. Er muss ScanSmart
   einmal außerhalb einer wartenden Auswahl-/Speicherseite sehen, bevor er
   scharfgeschaltet ist: Verwende den normalen ScanSmart-Startbildschirm vor einem
   Scan. „Aktion wählen“ ist die wartende Auswahlseite und keine freie Ansicht.
   Lass ScanSmart beim neuen Scan im Vordergrund.
4. Prüfe die geplanten Aktionen und den Zielordner. Schließe den Probelauf-Export
   manuell ab oder brich ihn ab. Schalte dann den Probelauf aus; dadurch muss der
   Helfer erneut eine freie Startansicht sehen. Derselbe wartende Probescan kann
   nicht sofort automatisch gespeichert werden. Starte einen neuen unkritischen
   Testscan und prüfe die erzeugten Dateien.

Nach einem Ad-hoc-Neubau kann macOS trotz gleicher App-Kennung eine neue
Berechtigungsidentität sehen. Falls Rechte nicht mehr greifen: App beenden,
alten Eintrag bei Bedienungshilfen entfernen und die neu installierte App erneut
hinzufügen. Automation-Eintrag prüfen und eine neue Nachfrage beantworten.
Die Skripte ändern diese Rechte nicht. Erteile sie nur deiner bekannten App-Kopie.

## Prüfintervall und Zeitmessung

Öffne die App und wähle **Prüfintervall wählen**. Du kannst 0,10, 0,25
(Voreinstellung), 0,50, 1 oder 2 Sekunden einstellen. Das ist die angeforderte Pause
nach einer Prüfung. macOS, das Lesen der Fenster und ScanSmart benötigen
zusätzliche Zeit. Bei ausgeschalteter oder pausierter Automatik sind es zwei
Sekunden. Ein reiner Intervallwechsel lässt einen laufenden Speichervorgang
unberührt. Die Sicherheitsprüfungen und Abbruchgrenzen bleiben erhalten.

**Zeitmessung anzeigen** zeigt die letzten aktiven Schritte mit Zeiten für
Fensterlesen, Aktion und gesamte Bearbeitung. Die Aktion enthält auch die erneute
Fensterprüfung und Bestätigung. Die Zeit für das Prüfintervall kommt hinzu.
Maximal 128 Messungen liegen lokal in `timings.json`: Zeitstempel, Statuscodes und
Zahlen, keine Fenstertitel, Pfade oder Bildinhalte. Warten ohne aktiven Scan
überschreibt die letzten Messungen nicht. Lokale Einzelkartenvergleiche
ergaben 14,5 → 11,9 Sekunden nach Optimierung der Fenstererfassung und danach
11,9 → 9,0 Sekunden durch Weglassen des bereits korrekten Ordnerschritts, jeweils
mit 250 ms Prüfintervall. Die Zeit des eigentlichen Karteneinzugs ist nicht
enthalten; das ist keine Zusage für längere Serien. Siehe [VALIDATION.md](VALIDATION.md).

## Einstellungen und sichere Wiederaufnahme

Einstellungen, Transaktionsstatus und begrenzte Protokolle liegen außerhalb der
signierten App unter `~/Library/Application Support/ScanSmart AutoSave/`.
Voreinstellung: kein Zielordner, deaktiviert, Probelauf aus. Ändere Einstellungen
über die App. Der Probelauf zeigt geplante Aktionen, ohne Felder zu verändern oder
zu klicken. Nach Aktivieren, Neustart, Reset oder Zielwechsel muss die App erneut
eine freie ScanSmart-Ansicht sehen.

Ein abgesendeter Klick bestätigt keinen gespeicherten Scan. Erfolg verlangt alle
erwarteten, vollständig von macOS lesbaren JPEG-Bilder, unveränderte Größen in
zwei Prüfungen und eine geschlossene Speicherseite. Die Bilder werden dafür nur
lokal im Arbeitsspeicher geprüft. Bereits vorhandene Zieldateien, Fehler, unklare
Metadaten, fremde Ansichten und Zeitüberschreitungen führen zur Pause. Werden
Dateien sofort von einem anderen Programm verschoben, kann die Prüfung ebenfalls
pausieren. Übergänge haben 30 Sekunden, die Exportprüfung 120 Sekunden Zeit.

Bei Pause zuerst Ausgabeordner und ScanSmart prüfen. Einen wartenden Export
manuell abschließen oder abbrechen; Dateien eines unklaren Speichervorgangs
erhalten. Danach Reset wählen und ScanSmart zur freien Ansicht zurückbringen.
Ein unklarer Speichervorgang wird niemals automatisch erneut versucht. Lösche
keine vorhandenen Dateien, nur um eine Kollision zu umgehen.

Epsons eigene Bedienelemente benötigen native Mausklicks. Direkt davor wird der
Vordergrundprozess erneut geprüft. Zwischen Prüfung und Klick bleibt ein kleines,
nicht atomar lösbares Zeitfenster. Wechsle während des Exports möglichst nicht
die App. Es gibt keine Tastenkürzel und kein pauschales Wegklicken von Fehlern.

## Fehler finden, Prüfstand und Entfernen

- Keine Aktion: Aktivierung, Zielordner, freie Ansicht zum Scharfschalten,
  Vordergrund, deutsche JPG-Ansicht und Rechte der eigenen App prüfen.
- Rechte nach Neubau fehlen: Berechtigungseinträge wie oben erneuern und die App
  manuell neu starten.
- Pause nach dem Export: Dateien prüfen, erst danach Reset. Ein Klick ist kein
  Erfolgsnachweis. Unbekannte Dialoge manuell behandeln.
- Doppelte Aktionen: alle Kopien und den Vorgänger beenden.

Statuscodes und Abhilfe:

| Code | Bedeutung und nächster Schritt |
| --- | --- |
| `invalid_metadata`, `counter_overflow` | JPG-Name, Endung oder Seitenzahl ist unklar oder außerhalb des erlaubten Bereichs. Export manuell klären; ScanSmart-Namen und JPG-Einstellungen prüfen. |
| `target_exists` | Eine erwartete Datei existiert schon. Erhalten; für einen neuen Scan anderen Namen oder Zielordner wählen. |
| `destination_readback`, `destination_rejected` | Zielwechsel wurde nicht bestätigt. Ordner prüfen und Export manuell abschließen/abbrechen. |
| `unsupported_view` | Unbekannte oder blockierte Ansicht. Dialog manuell behandeln; unterstützte deutsche Ansicht verwenden. |
| `transition_timeout`, `export_timeout` | Ansicht oder Dateiprüfung dauerte zu lange. Vor Wiederaufnahme tatsächliche Dateien und wartenden Export prüfen. |
| `permission_denied` | Bedienungshilfen-/Automation-Rechte dieser App prüfen. |
| `ui_changed`, `dispatch_failed` | Fenster hat sich geändert oder Aktion ist unbestätigt. ScanSmart und Dateien prüfen; nicht blind erneut versuchen. |
| `adapter_error`, `bridge_error`, `unknown_action` | Interner Zustand ist unklar. Pausieren, Dateien und wartenden Export klären; erst danach Neustart/Reset. |
| `storage_error` | Private Einstellungen/Status konnten nicht gelesen oder gespeichert werden. App beenden, Ordnerzugriff prüfen und Diagnosen vor Datenreset sichern. |
| `invalid_destination` | Vorhandenen beschreibbaren Zielordner über die App wählen. |
| `invalid_settings`, `unknown_request` | Ungültige interne Anfrage/Einstellung. Aktuellen Build neu starten; wiederholte Fehler mit bereinigten Diagnosen melden. |

Nach Behebung einer Pause Reset wählen und vor einem neuen Scan den normalen
Startbildschirm erkennen lassen. Reset beweist nicht, dass ein früherer Export
fehlgeschlagen ist.

`./scripts/test.sh` führt Node- und Python-Tests ohne GUI-Rechte aus. CI prüft den
Kern unter Linux sowie Tests, App-Build und Signatur unter macOS. Ein echter
Einzelkarten-Scan ist erfolgreich abgeschlossen. Die weitergehende manuelle
Hardware-Abnahme bleibt offen; die einzelnen Prüfpunkte stehen in
[VALIDATION.md](VALIDATION.md).

Zum Entfernen App beenden und die installierte `.app` löschen. Rechte kannst du
in den Systemeinstellungen entfernen. Für einen vollständigen lokalen Reset
zusätzlich `~/Library/Application Support/ScanSmart AutoSave/` löschen – erst nach
Klärung wartender Exporte und Sicherung benötigter Diagnosen. Deine Scans im
Zielordner bleiben erhalten. Die App legt keinen Autostart an.

Keine Netzwerkverbindung, Telemetrie oder Bildübertragung. Statusdateien können
Ordner- und Dateipfade enthalten; vor Weitergabe von Diagnosen private Angaben
entfernen. Siehe [Datenschutz und Sicherheit](../SECURITY.md),
[technischen Entwurf](design.md) und [MIT-Lizenz](../LICENSE).

Prüfergebnisse und ein Ablauf für die verbleibende Hardware-Abnahme stehen in
[VALIDATION.md](VALIDATION.md).
