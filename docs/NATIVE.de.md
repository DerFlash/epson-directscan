# Epson DirectScan Beta – native Menüleisten-App

Beta **0.3.0-beta.2** (Build 15) für den Epson ES-C320W über USB.
Sie ergänzt doppelseitige JPGs, ein PDF pro Karte und den kontinuierlichen Einzug
mit einem gemeinsamen PDF. Duplex-JPG, Karten-PDF, automatisches Nachlegen,
Stopptaste und eine 30-Sekunden-Wartefrist wurden lokal am Gerät geprüft;
die Ergebnisse stehen in [VALIDATION.md](VALIDATION.md).
Die frühere einseitige Fassung wurde mit drei echten Tastenscans geprüft.
Das ist keine allgemeine Produktionsfreigabe für andere Macs, Treiber oder Scanner.

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
  Systeme sind ungetestet. Die fertigen Downloads sind für Apple Silicon (arm64).
  Diese Beta ist lokal ad-hoc signiert, **nicht notarisiert**; andere Architekturen bleiben
  ungetestet.

## Download und Installation

Lade die [**DMG für Apple Silicon**](https://github.com/DerFlash/epson-directscan/releases/download/v0.3.0-beta.2/epson-directscan-0.3.0-beta.2-macos-arm64.dmg)
aus dem [GitHub-Release](https://github.com/DerFlash/epson-directscan/releases/tag/v0.3.0-beta.2) herunter. Alternativ enthält die App-ZIP dieselbe fertige App. Entwicklerwerkzeuge
oder Kompilieren sind dafür nicht nötig; der Epson-Treiber bleibt Voraussetzung.
[Offizieller Epson-Support](https://www.epson.de/de_DE/support/sc/es-c320w/s/s2773).

1. ScanSmart, ältere Helfer und eine bereits laufende DirectScan-App beenden.
2. DMG öffnen und **Epson DirectScan Beta.app** nach **Applications/Programme**
   ziehen. Bei einem Update die vorhandene App **am bisherigen Ort ersetzen**.
   Liegt sie unter `~/Applications`, diesen Ordner im Finder über **Gehe zu →
   Gehe zum Ordner** öffnen und dort ersetzen. Keine zweite Kopie parallel
   betreiben. Eine gewünschte Sicherung der alten App vorher selbst anlegen.
3. Die kopierte App starten. Falls macOS diese nicht notarisierte Beta blockiert:
   Nur wenn du der Quelle vertraust, nach dem ersten Öffnungsversuch unter
   **Systemeinstellungen → Datenschutz & Sicherheit → Dennoch öffnen** persönlich
   bestätigen. [Apple erklärt diesen Ablauf](https://support.apple.com/102445).
4. Ablageordner wählen, mit Epson verbinden, auf **Bereit** warten und zunächst
   eine entbehrliche Karte testen.

Die DMG führt keine Installationsskripte aus und ändert keine Sicherheitsrechte.
Sie enthält weder Epson-Treiber noch private Einstellungen/Scans. Vorhandene
App-Daten bleiben beim Ersetzen erhalten. Für bestehende Anmeldeobjekte denselben
App-Pfad beibehalten. Autostart wird durch die DMG nicht automatisch eingerichtet.
Ein klassischer Installer mit Administratorrechten ist für diese App nicht nötig.

## Aus Quellcode bauen (optional)

Apple-Kommandozeilen-Werkzeuge sind erforderlich (Swift und Clang). Die Tests
verwenden Swift Testing und Python 3 für einen künstlichen Hilfsprozess; hier
geprüft mit Swift 6.4/CLT. Python wird von der installierten App nicht benötigt. Keine zusätzlichen
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

Für ein fertiges Download-Paket nach dem Build `./scripts/package-native.sh`
verwenden. DMG, App-ZIP und Prüfsummen werden in einem neuen `dist/`-Unterordner
angelegt; vorhandene Pakete werden nicht überschrieben. Das Verpacken verändert
weder die Quell-App noch eine installierte Kopie.

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
   Papierweg einlegen und die Scantaste am Epson drücken. Das Ergebnis wird automatisch
   abgelegt. Für eine weitere Karte warten, bis die App wieder bereit ist.

Außerhalb einer gestarteten Sammlung wird beim Öffnen, Einlegen, Neuverbinden
oder Ändern von Einstellungen kein Scan angefordert. Ein unbekannter, verfrühter oder wiederholter Tastendruck wird nicht
als weiterer Scan vorgemerkt. Die Gerätetaste wird nicht durch einen Menübefehl
ersetzt. Nicht mehrere Scan-Apps gleichzeitig verwenden.

## Einstellungen

Das Menü am Scannersymbol und **Einstellungen …** in der Statusansicht bieten:

- Ablageordner wählen oder öffnen;
- **Doppelseitig scannen**: Vorder- und Rückseite aufnehmen;
- **Ausgabe**: getrennte JPGs oder ein PDF pro Karte (bei Duplex zwei Seiten);
- **Kontinuierlicher Scan**: ein gemeinsames PDF für die ganze Sitzung;
- **Wartezeit**: 30, 60, 120 oder 300 Sekunden ohne neue Karte, optional unbegrenzt;
- Zuschnitt, Schräglagenkorrektur und automatische Drehung einzeln schalten;
- pausieren/freigeben, letzte Datei anzeigen und zurückgehaltene Seiten sichern.

Bestehende Einstellungen werden mit einer unveränderten privaten Sicherung
`settings-v1-backup.json` übernommen. Duplex und kontinuierlicher Einzug sind
anfangs aus; JPG und alle drei bisherigen Korrekturen bleiben erhalten. Die
Auflösung bleibt bei 300 dpi/Farbe. JPG-Seiten einer doppelseitigen Karte haben
dieselbe Kartennummer und die Endungen `_vorne.jpg` und `_hinten.jpg`. PDFs pro
Karte enthalten zuerst die Vorder-, dann die Rückseite. Ein Stapel erzeugt je
Karte ein PDF. Zeitstempel und UUID verhindern Namenskollisionen; eine vorhandene
Datei wird niemals ersetzt.

Die automatische Drehung verwendet Epsons Texterkennung zur Orientierung.
Sie ist **bei farbigen Spielkarten und Kartenrückseiten nicht zuverlässig**:
Die Testkarte wurde trotz aktivierter Erkennung teilweise auf dem Kopf belassen.
Es gibt keine feste Ausrichtungsgarantie. Bei der Testkarte wirkten Bilder im
kontinuierlichen Modus außerdem dunkler als normale Scans. Eine zusätzliche
Farb-/Tonwertangleichung zwischen den beiden Treiberwegen ist nicht enthalten.
Bei einem fehlenden oder nicht
kompatiblen Modul wird keine unbemerkte Ersatzkorrektur verwendet.

### Kontinuierlicher Einzug

**Einzug ohne Fortschritt / Stop:** Liefert ein gestarteter Scan 15 Sekunden lang
keine weitere vollständige Bildseite, fordert die App einen Abbruch an. Im
kontinuierlichen Modus gilt das nur während eines aktiven Einzugs, nicht beim
Warten auf weitere Karten. Für die Abbruchbestätigung bleiben 12 Sekunden;
antwortet der Treiber nicht, bleibt ein sichtbarer Fehler bestehen.

Ein Abschluss ohne Bildseiten (z. B. Stop nach erfolglosem Einzug) zeigt nach
bestätigter Scanner-Freigabe einen Hinweis wie „Keine Seite gescannt – Vorlage
und Einzug prüfen“. Danach ist die App für einen neuen Druck auf die Epson-Taste
bereit. Sie wiederholt den Scan nicht selbst. Ein leerer Auftrag wird nur
entfernt, wenn tatsächlich keine Bild-/Teildateien vorhanden sind. Bereits
vorhandene Daten und echte Gerätefehler werden weiterhin zur Prüfung behalten.
Im kontinuierlichen Modus werden bereits vollständig übernommene Seiten nach
bestätigtem Abschluss als Sammlungs-PDF gesichert; unvollständige Karten bleiben
gekennzeichnet. Bitte eine nicht einziehbare Vorlage vor dem nächsten Start
entnehmen bzw. neu einlegen.

Ein **blinkendes Ausrufezeichen bzw. Papierstau** ist ein echter Gerätefehler und
bleibt sichtbar, auch wenn die App den Einzug zuvor wegen fehlenden Fortschritts
gestoppt hat. Die App kann den mechanischen Fehler nicht löschen. Laut
[Epson-Handbuch, Fehleranzeigen](https://download4.epson.biz/sec_pubs/es-c320w/useg/de/manual.pdf)
die Scannerabdeckung öffnen, gestaute Vorlagen entfernen und die Abdeckung
schließen. Danach die zurückgehaltenen Dateien prüfen und **Fehler zurücksetzen
und neu verbinden …** wählen. Es wird kein alter Scan wiederholt.

Beim Ausschalten bzw. Trennen des Scanners beendet DirectScan den Empfang und
stellt nach bestätigter Freigabe die Epson-Tastenhelfer wieder her. Deshalb kann
nach dem Einschalten wieder ScanSmart auf die Scantaste reagieren. Epson-
Scanprogramme schließen und DirectScan erneut verbinden, bevor weitergescannt
wird. Eine automatische Wiederverbindung nach USB-Trennung ist nicht enthalten.

1. Im Leerlauf **Kontinuierlicher Scan (Sammlungs-PDF)** einschalten und die
   gewünschte Wartezeit wählen (Standard 120 Sekunden). Der normale JPG/PDF-Wert
   bleibt gespeichert und gilt nach dem Ausschalten wieder.
2. Die erste Karte einlegen und einmal die Epson-Scantaste drücken. Die App
   zeigt die aktive Sammlung und die Zahl übernommener Seiten an.
3. Weitere Karten in Ruhe nachlegen: Der bereits aktive Einzug zieht sie ohne
   erneuten Start ein. Während eines laufenden Transfers läuft keine Wartefrist.
   Nach einer vollständig verarbeiteten Karte beginnt sie neu.
4. Die **Stopptaste am Epson** drücken oder im Menü bzw. Statusfenster
   **Sammlung beenden und speichern** wählen. Alternativ beendet die gewählte
   Wartefrist die Sitzung. **Unbegrenzt** benötigt ein ausdrückliches Stop.
5. Erst dann wird das gemeinsame PDF geprüft und in den Ablageordner übergeben.
   Bei einer unvollständigen letzten Duplex-Karte enthält es alle fertig
   übernommenen Seiten; die App zeigt den fehlenden Partner ausdrücklich an. Die Originalbilder
   dieses Vorgangs bleiben außerdem privat in `Recovery/` zur Prüfung erhalten.

Ein Schließen des Statusfensters beendet die Sammlung nicht. Beim Beenden der
App kannst du speichern, zurückhalten oder abbrechen. Ein Absturz, Scannerfehler
oder USB-Abbruch startet keine neue Sitzung und wiederholt keinen Scan.

Die Einstellungen werden beim akzeptierten Tastendruck für diesen Scan
festgehalten. Während der Übergabe und des Scannens sind Änderungen gesperrt.
Eine Ordnerwahl im Leerlauf gibt den Scanner zunächst frei und verbindet
anschließend wieder. Der Einzug kann einen ganzen eingelegten Stapel verarbeiten;
für erste Tests immer genau eine entbehrliche Karte verwenden.

## Wie der Hintergrundbetrieb funktioniert

Der Epson-eigene Tastenempfänger läuft als kleiner isolierter Hilfsprozess.
Nach einer physischen Taste 1 schließt er seine Verbindung und endet. Erst wenn
beides bestätigt ist, startet der jeweilige Scanprozess. Normale JPG/PDF-Scans
verwenden ImageCaptureCore. Der kontinuierliche Einzug verwendet den nativen
Epson-Autoeinzug; Zuschnitt und Schräglagenkorrektur stammen aus Scanner.framework.
Die Orientierung ermittelt Epsons ImageProcessor/Esaod an den vollständigen
Einzelbildern. Die App wendet diese Drehentscheidung an und baut das PDF aus
geprüften Seiten. Die störungsanfällige vollständige ScanEngine-Pipeline aus
dem privaten Vorversuch wird nicht verwendet.

Erst nach bestätigtem Abschluss, Schließen und Prozessende startet der nächste
Tastenempfänger. Jeder Helfer hält unabhängig von der Haupt-App dieselbe
Betriebssystem-Sperre. Während der laufenden Sammlung bleibt die Verbindung
auch beim Warten auf neue Karten geöffnet. Es gibt keine pauschale Frist für
eine Sitzung mit unbegrenzter Wartezeit; ein nicht antwortender Transfer wird
weiterhin angehalten. Der Nachrichtenkanal ist begrenzt und stoppt bei ungültigen
oder zu vielen Meldungen mit zurückgehaltenen Daten.

Die Zähler in der Statusansicht gelten seit dem jeweiligen App-Start.

Beim Öffnen des Tastenempfängers werden frühe Ereignisse kurz verworfen. Scannen
ist erst nach der sichtbaren Bereitschaft möglich. Unterbrochene Vorgänge werden
nicht automatisch wiederholt. Stirbt die Haupt-App, schließen die Hilfsprozesse
beim Erkennen des fehlenden Elternprozesses ihre Verbindung.

**Pausieren und Scanner freigeben** gibt auch die Epson-Tastenhelfer zurück.
Andere Epson-Geräte können während des Direktmodus ebenfalls von deren Pause
betroffen sein. Die Freigabe wird erst nach Bestätigung und Ende des betreffenden
Hilfsprozesses gemeldet.

Ein Start bei Anmeldung wird nicht automatisch eingerichtet. Eine bereits
vorhandene Registrierung bleibt beim Update über denselben App-Pfad erhalten.
Für eine neue Einrichtung kannst du die App in den macOS-Anmeldeobjekten
hinzufügen und die alte Automatik dort deaktivieren. Ab-/Anmeldung und längere Serien sind ungetestet.

## Fehler und Wiederherstellung

Die App scannt zuerst unter
`~/Library/Application Support/Epson DirectScan/Pending/`. Nur vollständig
lesbare Seiten werden übernommen. PDFs werden seitenweise geschrieben und
auf Seitenzahl und Größe geprüft. Die fertige Ausgabe gelangt über eine
temporäre Datei atomar ohne Ersetzen in den Ablageordner. Ein Exportnachweis
ermöglicht die eindeutige Zuordnung auch bei einem Abbruch direkt nach der
Dateiübergabe. Erst nach bestätigtem Abschluss werden private Originale entfernt.

Bei fehlendem Zielordner, Fehler, Abbruch, Trennung oder Neustart bleiben
unbestätigte Dateien erhalten. Im Menü **Zurückgehaltene Scans und Protokoll öffnen**
wählen und Dateien prüfen. **Zurückgehaltene Seiten als PDF sichern** exportiert
explizit die bestätigten Seiten im ursprünglichen Ablageordner, ohne einen Scan
zu starten. Die gewählte Sammlungs-Ausgabe wird im Exportnachweis festgehalten;
ein Wiederholen bestätigt dieselbe Datei und wechselt nicht unbemerkt zu JPGs
oder Karten-PDFs. Bei unbestätigten Zusatzdateien oder
einem fehlenden ursprünglichen Ordner bleibt die manuelle Prüfung nötig.
Danach **Fehler zurücksetzen
und neu verbinden**. Zurückgehaltene Jobs werden in `Recovery/` aufbewahrt und
nicht erneut gescannt oder automatisch exportiert.

Nach einem App-Absturz können Epson-Dienste bis zum erneuten Öffnen von DirectScan
oder der nächsten Mac-Anmeldung pausiert bleiben. Die private Datei
`epson-services.json` enthält den Wiederherstellungsvermerk. Zusätzlich hält
jeder Hilfsprozess unabhängig von der Haupt-App die Betriebssystem-Sperre
`scanner.lock`. Solange ein alter Prozess sie noch hält, blockiert die App sowohl
die Wiederherstellung der Epson-Dienste als auch eine neue Verbindung. Das gilt
auch bei einem verzögerten Treiberabschluss nach einem Neustart. Beide Dateien
bitte nicht löschen; bei belegter Sperre warten und erneut verbinden.
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

Wenn du ausdrücklich zur vorherigen nativen0.2-Fassung zurückkehrst, beende
DirectScan zuerst und sichere die aktuelle `settings.json` separat. Die ältere
Fassung benötigt die ebenfalls aufbewahrte `settings-v1-backup.json` als
`settings.json`; sie versteht die neuen Duplex-/PDF-Einstellungen nicht.
