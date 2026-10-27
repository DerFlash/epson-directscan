# Epson DirectScan Beta – native Menüleisten-App

Lokale Entwicklungsfassung 0.2.0-beta.1-dev. Diese unabhängige App verwendet den
installierten Epson-ICA-Treiber direkt. Sie enthält keine Epson-Software und
benötigt keine Bedienungshilfen oder Steuerung von System Events.

**Noch nicht als vollständiger Tasten-Workflow abgenommen.** Zwei direkte
USB-Scans mit dem ES-C320W waren erfolgreich, einschließlich der Treiberkorrekturen.
Die Geräte-Taste wurde von den bisherigen Callback-Proben nicht erkannt. Eine
Probe mit Mac-Zielzuordnung endete vor der Bestätigung und ist nicht auswertbar.
Die dauerhafte App beobachtet zusätzlich die vorhandene alte buttonPressed-
Eigenschaft, sofern der Treiber sie anbietet. Am 27.10.2026 blieb auch damit
bei bestätigten Tastendrücken ohne und mit eingelegter Karte der Zähler auf 0;
die Karte wurde nicht eingezogen. Beide Epson-Tastenhelfer waren dabei beendet,
die native App durchgehend verbunden. **Der Start über die Gerätetaste ist mit
diesem Ansatz aktuell nicht funktionsfähig.** Die lokale App wurde anschließend
pausiert und die Epson-Dienste wurden wiederhergestellt.

## Bauen und installieren

macOS und Apple-Kommandozeilen-Werkzeuge sind erforderlich. Die Tests verwenden
Swift Testing; die hier geprüften Werkzeuge sind Swift 6.4/CLT auf macOS 27.0.1.
Die App zielt auf macOS 13+, weitere Versionen sind ungetestet. Keine externen
Pakete oder Laufzeiten werden heruntergeladen.

```
./scripts/test-native.sh
./scripts/build-native.sh
./scripts/install-native.sh
```

Die App landet unter `~/Applications/Epson DirectScan Beta.app`. Ein bereits
vorhandener nativer Build braucht `build-native.sh --replace`; der Installer
ersetzt eine vorhandene native Installation nur mit `install-native.sh --replace`,
nachdem sie beendet wurde. Die vorherige Fassung wird als ZIP unter dem privaten
App-Datenordner in `Build Backups/` gesichert. Die alte ScanSmart-Automatik
bleibt getrennt erhalten. Die lokale Signatur ist ad hoc; es gibt keine
Notarisierung und keinen neuen öffentlichen Binär-Release.

## Erster Start

1. Die alte AutoSave-App, ScanSmart und das Event-Manager-Einstellungsfenster
   beenden. Den Epson per USB verbinden. Eine parallele WLAN-Verbindung wird
   von DirectScan nicht ausgewählt.
2. DirectScan öffnen und den vorhandenen Ablageordner wählen, hier Dokumente/Scans.
   Der Ordnerdialog kann auch einen neuen Ordner anlegen. Das Scannersymbol
   erscheint oben in der Menüleiste; die App hat kein Dock-Fenster. Eine kleine
   Statusansicht zeigt Verbindung und Tastendrücke. Du kannst sie schließen;
   die App läuft weiter. Erneutes Öffnen der App oder **Status anzeigen** im Menü
   öffnet die Ansicht wieder.
3. Im Menü **Mit Epson verbinden** wählen. Der erste Hinweis erklärt die
   vorübergehende Übernahme der beiden Epson-Tastenhelfer. Die App speichert,
   welche Dienste vorher geladen waren, und stellt sie nach bestätigtem Schließen des Scanners wieder her.
4. Für die noch offene Tastenabnahme zunächst **ohne Karte** einmal die Taste am
   Epson drücken. Die Zahl der Tastendrücke muss steigen und die App soll zum
   Einlegen einer Karte auffordern. Kein kurzes Testfenster: die App hört bis zur
   Pause oder zum Beenden weiter mit. Solange kein Tastendruck erkannt ist,
   bedeutet „Verbunden“ nur eine offene Scanner-Verbindung.
5. Erst danach eine entbehrliche Karte im geraden Papierweg einlegen und die
   Epson-Taste drücken. Ein JPG muss ohne Klick am Mac im gewählten Ordner erscheinen.
   Eine zweite frische Karte prüft das erneute Bereitwerden.

Der derzeitige Kandidat hat diese Abnahme nicht bestanden. Weitere Wiederholungen
derselben Tastenprobe sind ohne einen neuen Empfangsweg nicht sinnvoll.

Die App startet keinen Scan beim Öffnen, Einlegen, Neuverbinden oder Ändern der
Einstellungen. Es gibt keinen heimlichen Ersatz der Gerätetaste durch einen
Menübefehl. Nicht auf Tastenerkennung oder Hardwareabnahme schließen, wenn nur
Build und Softwaretests bestanden sind.

## Einstellungen und Betrieb

- JPG, 300 dpi, RGB, einseitig sind fest eingestellt.
- Automatischer Zuschnitt, Schräglagenkorrektur und automatische Drehung sind
  standardmäßig an und einzeln schaltbar. Vor jedem Scan müssen die angeforderten
  Korrekturen vom Treiber bestätigt sein.
- Änderungen gelten für den nächsten Scan; während eines laufenden Jobs sind
  Ordnerwahl, Korrekturen und Neuverbinden gesperrt.
- Jeder Scanjob verwendet einen eigenen Namen mit Zeitstempel und UUID.
  Vorhandene Dateien werden nicht überschrieben. Der komplette Einzug kann
  mehrere eingelegte Vorlagen einziehen; für die Abnahme nur eine Karte einlegen.
- **Pausieren und Scanner freigeben** schließt die Scanner-Verbindung und stellt
  die Epson-Hintergrunddienste erst nach bestätigter Freigabe wieder her. Andere Epson-Geräte können während des
  Direktmodus ebenfalls von der pausierten Tastenüberwachung betroffen sein.
- Der Start bei Anmeldung wird nicht automatisch geändert. Nach erfolgreicher
  Abnahme kann die App in den macOS-Anmeldeobjekten hinzugefügt werden; dabei die
  bisherige Automatik deaktivieren. Autostart nach Ab-/Anmeldung ist ungetestet.
- Bekannter Verbindungsfehler: Nach Pausieren und erneutem Verbinden im selben
  App-Prozess wurde zweimal eine Gerätetrennung mit Fehler -21345 beobachtet.
  Ein vollständiger App-Neustart stellte die Verbindung wieder her. Auch dieser
  Fehler muss vor einer Freigabe behoben und am Gerät nachgeprüft werden.

## Fehler und Wiederherstellung

Die App scannt zuerst in einen privaten Bereich unter
`~/Library/Application Support/Epson DirectScan/Pending/`. Nur vollständig
lesbare JPGs werden über eine temporäre Datei atomar ohne Ersetzen in den
Ablageordner übergeben. Das ermöglicht auch nachgelagerten Programmen, das fertige
JPG sofort weiterzunehmen. Erst nach einem bestätigten vollständigen Job werden
seine lokalen Originale entfernt.

Bei Fehlern, fehlendem Zielordner, Abbruch, Trennung oder Neustart bleiben
unbestätigte Dateien erhalten. Im Menü **Zurückgehaltene Scans und Protokoll öffnen**
wählen, Dateien prüfen und gegebenenfalls manuell sichern. Danach **Fehler
zurücksetzen und neu verbinden**. Bereits zurückgehaltene Jobs werden dabei in
`Recovery/` aufbewahrt; sie werden nicht erneut gescannt oder automatisch exportiert.

Nach einem App-Absturz können die Epson-Dienste bis zum erneuten Öffnen von
DirectScan oder der nächsten Mac-Anmeldung pausiert bleiben. Die private Datei
`epson-services.json` dient zur Wiederherstellung; nicht löschen. DirectScan beim
Neustart einmal öffnen und pausieren oder beenden, um die Dienste zurückzugeben.
Bei einer nicht bestätigten Scanner-Freigabe bleiben die Dienste zur Vermeidung
konkurrierender Zugriffe pausiert. Beenden wartet kurz auf die Bestätigung; bei
einem Fehler/Timeout bleibt der Wiederherstellungsvermerk für den Neustart
erhalten. Die App danach erneut öffnen, um die Dienste zurückzugeben.

`events.jsonl` und eine vorherige Logdatei sind begrenzt; sie enthalten feste
Ereigniscodes, Zahlen und Zeiten, keine Bilder, OCR-Texte oder Geräteseriennummern.
Private Einstellungen und Jobdateien enthalten den gewählten Ordner. Vor dem
Teilen von Diagnosen persönliche Pfade entfernen. Keine Netzwerkzugriffe oder
Uploads durch DirectScan. Das Verhalten von Epson-Software liegt außerhalb dieser
App.

## Zur bisherigen Lösung zurückkehren

DirectScan pausieren oder beenden. ScanSmart mit dem USB-Scanner öffnen und die
bisherige AutoSave-App aktivieren. Beide Apps und ihre Einstellungen sind getrennt.
Vor dem Entfernen von DirectScan die Epson-Dienste zurückgeben und benötigte
Dateien aus Pending/Recovery sichern. Der eigentliche Ablageordner ist separat.
