# Epson DirectScan Beta – native Menüleisten-App

Lokale Entwicklungsfassung 0.2.0-beta.1-dev für den Epson ES-C320W über USB.
Zwei vollständige Tastenscans wurden am 27.10.2026 geprüft: jeweils ein lesbares
JPG ohne Mac-Klicks, danach wieder bereit. Der zweite Scan ging nach einer
Ordneränderung ausschließlich in den neuen Ordner. Anschließend wurde der
normale Ablageordner wieder eingestellt. Das ist eine lokale Beta-Abnahme,
keine allgemeine Produktionsfreigabe für andere Macs, Treiber oder Scanner.

Die App ersetzt die ScanSmart-Oberfläche. Sie braucht weder Bedienungshilfen
noch System Events und lädt keine Scans hoch. Sie enthält keine Epson-Software;
der Epson-Treiber muss separat installiert sein.

## Voraussetzungen

- Epson ES-C320W, direkt per USB verbunden. Andere Modelle und WLAN sind nicht
  unterstützt. USB-Gerätekennung: Epson 0x04b8 / Produkt 0x0190.
- **Epson-Treiber 6.7.84.** Der separate Tastenempfänger verwendet einen internen
  Teil dieses installierten Treibers. Genau diese Version und ihre Schnittstellen
  werden beim Start geprüft; andere Versionen werden sicher abgewiesen. Epson
  garantiert diese interne Schnittstelle nicht. Nach einem Treiberupdate muss
  die Verträglichkeit neu geprüft werden.
- Geprüft: Apple-Silicon-Mac, macOS 27.0.1. Das Build-Ziel ist macOS 13+, weitere
  Systeme sind ungetestet. Es gibt keine Notarisierung und keinen öffentlichen
  Binär-Release dieser nativen Entwicklungsfassung.

## Bauen und installieren

Apple-Kommandozeilen-Werkzeuge sind erforderlich (Swift und Clang). Die Tests
verwenden Swift Testing; hier geprüft mit Swift 6.4/CLT. Keine zusätzlichen
Pakete oder Laufzeiten werden heruntergeladen.

```
./scripts/test-native.sh
./scripts/build-native.sh
./scripts/install-native.sh
```

Die App landet unter `~/Applications/Epson DirectScan Beta.app`. Zum Ersetzen
`build-native.sh --replace` und nach Beenden der App `install-native.sh --replace`
verwenden. Der Installer prüft die App-Kennung, lehnt laufende native Kopien ab
und sichert die vorherige Fassung als ZIP unter dem privaten App-Datenordner
in `Build Backups/`. Die alte ScanSmart-Automatik bleibt separat erhalten.

## Starten und scannen

1. Die alte AutoSave-App, ScanSmart und das Event-Manager-Einstellungsfenster
   beenden. Den Epson per USB verbinden.
2. DirectScan öffnen und den Ablageordner wählen, beispielsweise Dokumente/Scans.
   Das Scannersymbol erscheint in der Menüleiste. Die kleine Statusansicht lässt
   sich schließen; die App läuft weiter. Erneutes Öffnen oder **Status anzeigen**
   im Menü zeigt sie wieder an.
3. **Mit Epson verbinden** wählen. Der erste Hinweis erklärt, dass die beiden
   Epson-Tastenhelfer während des Direktmodus pausieren. Nach bestätigter
   Scanner-Freigabe beim Pausieren oder Beenden werden sie wieder gestartet.
4. Auf **Bereit – Epson-Taste drücken** warten. Eine entbehrliche Karte im geraden
   Papierweg einlegen und die Scantaste am Epson drücken. Das JPG wird automatisch
   abgelegt. Für eine weitere Karte warten, bis die App wieder bereit ist.

Beim Öffnen, Einlegen, Neuverbinden oder Ändern von Einstellungen wird kein Scan
angefordert. Ein unbekannter, verfrühter oder wiederholter Tastendruck wird nicht
als weiterer Scan vorgemerkt. Die Gerätetaste wird nicht durch einen Menübefehl
ersetzt. Nicht mehrere Scan-Apps gleichzeitig verwenden.

## Einstellungen

Das Menü am Scannersymbol und **Einstellungen …** in der Statusansicht bieten:

- Ablageordner wählen oder öffnen;
- automatischen Zuschnitt, Schräglagenkorrektur und automatische Drehung einzeln
  schalten (standardmäßig alle an);
- pausieren/freigeben, letztes JPG anzeigen, Wiederherstellung und Beenden.

JPG, 300 dpi, RGB und einseitiges Scannen sind fest eingestellt. Jede Datei
bekommt einen Namen mit Zeitstempel und UUID; vorhandene Bilder werden nicht
überschrieben. Der Treiber muss die drei angeforderten Korrekturen vor jedem
Scan bestätigen. Die Wirkungsstärke von Drehung/Schrägkorrektur wurde nicht
an gezielt unterschiedlich eingelegten Karten vermessen.

Die Einstellungen werden beim akzeptierten Tastendruck für diesen Scan
festgehalten. Während der Übergabe und des Scannens sind Änderungen gesperrt.
Eine Ordnerwahl im Leerlauf gibt den Scanner zunächst frei und verbindet
anschließend wieder. Der Einzug kann einen ganzen eingelegten Stapel verarbeiten;
für erste Tests immer genau eine entbehrliche Karte verwenden.

## Wie der Hintergrundbetrieb funktioniert

Der Epson-eigene Tastenempfänger läuft als kleiner isolierter Hilfsprozess.
Nach einer physischen Taste 1 schließt er seine Verbindung und endet. Erst wenn
beides bestätigt ist, startet ein eigener Scanprozess über ImageCaptureCore.
Dieser prüft den Einzug und die Korrekturen, scannt, speichert und schließt die
Verbindung. Erst nach bestätigtem Abschluss startet der nächste Tastenempfänger.
So greifen beide Wege nicht gleichzeitig auf den Scanner zu. Jeder Scanprozess
ist neu; der zuvor beobachtete Fehler beim erneuten Öffnen einer ICA-Verbindung
innerhalb desselben Prozesses wird damit vermieden. Zwei vollständige Zyklen
und mehrere Ordnerwechsel wurden auf diesem Mac geprüft.

Beim Öffnen des Tastenempfängers werden frühe Ereignisse kurz verworfen. Scannen
ist erst nach der sichtbaren Bereitschaft möglich. Unterbrochene Vorgänge werden
nicht automatisch wiederholt. Stirbt die Haupt-App, schließen die Hilfsprozesse
beim Erkennen des fehlenden Elternprozesses ihre Verbindung.

**Pausieren und Scanner freigeben** gibt auch die Epson-Tastenhelfer zurück.
Andere Epson-Geräte können während des Direktmodus ebenfalls von deren Pause
betroffen sein. Die Freigabe wird erst nach Bestätigung und Ende des betreffenden
Hilfsprozesses gemeldet.

Ein Start bei Anmeldung wird nicht automatisch eingerichtet. Nach der lokalen
Abnahme kannst du die App in den macOS-Anmeldeobjekten hinzufügen und die alte
Automatik dort deaktivieren. Ab-/Anmeldung und längere Serien sind ungetestet.

## Fehler und Wiederherstellung

Die App scannt zuerst unter
`~/Library/Application Support/Epson DirectScan/Pending/`. Nur vollständig
lesbare JPGs werden über eine temporäre Datei atomar ohne Ersetzen in den
Ablageordner übergeben. Nachgelagerte Programme dürfen das fertige JPG sofort
weiternehmen. Erst nach einem bestätigten vollständigen Job werden seine
privaten Originale entfernt.

Bei fehlendem Zielordner, Fehler, Abbruch, Trennung oder Neustart bleiben
unbestätigte Dateien erhalten. Im Menü **Zurückgehaltene Scans und Protokoll öffnen**
wählen, Dateien prüfen und nötigenfalls manuell sichern. Danach **Fehler zurücksetzen
und neu verbinden**. Zurückgehaltene Jobs werden in `Recovery/` aufbewahrt und
nicht erneut gescannt oder automatisch exportiert.

Nach einem App-Absturz können Epson-Dienste bis zum erneuten Öffnen von DirectScan
oder der nächsten Mac-Anmeldung pausiert bleiben. Die private Datei
`epson-services.json` enthält den Wiederherstellungsvermerk; nicht löschen.
Bei nicht bestätigter Freigabe bleiben die Dienste ebenfalls pausiert, um
konkurrierende Zugriffe zu vermeiden. Beenden wartet kurz auf eine Bestätigung;
bei Fehler/Timeout bleibt der Vermerk erhalten. Die App danach erneut öffnen,
um die Dienste zurückzugeben.

`events.jsonl`, `WorkerLogs/` und jeweils eine vorherige Logdatei sind begrenzt.
Die Ereignisse enthalten Codes, Zahlen und Zeiten, keine Bilder, OCR-Texte oder
Geräteseriennummern. Einstellungen/Jobdateien enthalten den gewählten Ordner.
Vor dem Teilen von Diagnosen persönliche Pfade entfernen. DirectScan selbst
verwendet kein Netzwerk; das Verhalten installierter Epson-Software liegt
außerhalb der App.

## Zur bisherigen Lösung zurückkehren

DirectScan pausieren oder beenden. ScanSmart und die bisherige AutoSave-App
öffnen. Beide Apps und ihre Einstellungen bleiben getrennt. Vor dem Entfernen
von DirectScan die Epson-Dienste zurückgeben und benötigte Dateien aus
Pending/Recovery sichern. Der eigentliche Ablageordner ist separat.
