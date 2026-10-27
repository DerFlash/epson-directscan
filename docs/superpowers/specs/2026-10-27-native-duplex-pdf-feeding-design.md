# Duplex, PDF und automatischer Einzug für Epson DirectScan

Status: vom Nutzer am 27.10.2026 ausdrücklich zur Umsetzung freigegeben.
Unabhängiger Builder-Check: keine wichtigen offenen Planungsfragen.

## Ziel und bestätigte Anforderungen

Die bestehende Menüleisten-App für den ES-C320W über USB bekommt einen
Duplex-Schalter, JPG-/PDF-Ausgabe und einen echten automatischen Einzugsmodus.
Die Scantaste am Epson bleibt der Startpunkt. Im automatischen Modus reicht
danach das Nachlegen weiterer Vorlagen, ohne erneuten Tastendruck. Die Stopptaste
am Epson oder eine einstellbare Wartezeit beendet die Sammlung als ein PDF.
Der Nutzer kennt und erwartet diesen Ablauf aus der Epson-App.

Die neue Fassung wird lokal installiert und mit einer entbehrlichen Karte
geprüft. Keine Veröffentlichung, kein neuer Cloud-Dienst, kein ScanSmart-UI und
keine zusätzliche Berechtigung für Codex sind Teil dieses Auftrags.

## Ansätze und Entscheidung

1. **Treibereigener automatischer Einzug:** ein aktiver Scanauftrag wartet auf
   weitere Vorlagen und endet über die Epson-Stopptaste oder Treiber-Zeitgrenze.
   Das passt zur ausdrücklichen Klarstellung des Nutzers. Die installierten
   Epson-Komponenten enthalten Auto-Feeding-, Timeout- und Ende-Funktionen; ihre
   tatsächliche Funktion samt Bildverarbeitung muss am Gerät nachgewiesen werden.
   Nachteil: mehr Bindung an die interne, bereits auf 6.7.84 begrenzte Epson-API.
2. **App prüft Papier und startet einzelne ICA-Aufträge:** könnte das Nachlegen
   nachbilden, bietet jedoch bislang keinen bestätigten Weg für die physische
   Stopptaste zwischen Aufträgen und erzeugt zusätzliche Verbindungswechsel.
   Kein stiller Ersatz für Ansatz 1, falls dessen Nachweis scheitert.
3. **Erneuter Scantastendruck pro Charge:** entspricht nicht der Klarstellung
   und wird nicht als kontinuierlicher Modus umgesetzt.

Vorgesehener Ansatz ist 1. Der vorhandene, geprüfte ICA-Weg bleibt für normale
Einzelscans bestehen; der automatische Einzug bekommt einen isolierten
Epson-Worker. Kein neuer allgemeiner Scanner-Unterbau und keine mitgelieferten
Epson-Binärdateien.

## Bedienung und Ausgabe

- **Doppelseitig scannen** ist unabhängig vom Ausgabeformat schaltbar.
- **JPG:** pro Seite eine Datei; bei Duplex eindeutige Vorder-/Rückseitennamen
  mit gemeinsamer Kartenkennung. Im vorhandenen einfachen Modus bleibt eine
  Seite pro Karte erhalten.
- **PDF pro Karte:** einseitig eine Seite; doppelseitig Vorder- und Rückseite
  als zwei aufeinanderfolgende PDF-Seiten. Bei einem Stapel entsteht je Karte
  ein PDF, nicht ein gemeinsames PDF für den gesamten Einzug. Diese Auslegung
  von „jeweils ein PDF“ ist ein Vorschlag des Erstellers.
- **Automatischer Einzug / Sammel-PDF:** sammelt alle Seiten einer Sitzung in
  genau einem PDF. Duplex bleibt schaltbar. Das normale JPG/PDF-Ausgabeformat
  bleibt gespeichert, ist während des Sammelmodus aber nicht dessen Ausgabe.
  Beim Verlassen des Modus gilt wieder das zuvor gewählte normale Format.

Die aktivierte Einstellung allein zieht noch keine Vorlage ein. Erst ein neuer
physischer Starttastendruck beginnt eine Sitzung. Nur während dieser Sitzung
darf das Nachlegen automatisch einen Einzug auslösen. Nach Stop oder Timeout
ist wieder ein neuer Starttastendruck nötig.

Vorschlag des Erstellers für die Zeitgrenze: **120 Sekunden Inaktivität**, ab dem
Bereitwerden für die erste bzw. nächste Vorlage; nach einer fertig gescannten
Vorlage beginnt die Wartezeit neu. Im Menü einstellbar auf 30/60/120/300 Sekunden
oder ohne Zeitgrenze, soweit der Treiber den jeweiligen Wert bestätigt. Eine
laufende Bildübertragung wird nicht durch den Inaktivitätstimer abgeschnitten.
Das ist keine harte Höchstdauer der gesamten Sammlung.

Status und Menü zeigen „Bereit“, „Scan läuft“, „Sammlung: N Seiten – wartet auf
weitere Vorlagen“ und „PDF wird gespeichert“. **Sammlung abschließen** ist auch
in der App erreichbar; die physische Stopptaste bleibt ein Abnahmekriterium.
Ordner, Duplex, Format und Bildkorrekturen sind für eine aktive Sitzung gesperrt
und werden zu Beginn unveränderlich festgehalten. Das Statusfenster darf wie
bisher geschlossen werden, ohne eine Sammlung zu beenden.

## Bilddaten und PDF

300 dpi, RGB und die drei bisherigen schaltbaren Korrekturen bleiben erhalten.
Der normale ICA-Weg muss Duplex-Unterstützung und aktivierten Zustand vor jedem
Scan bestätigen. Der neue automatische Worker muss seine Seiten ebenfalls mit
den angeforderten Epson-Bildkorrekturen liefern. Unterstützt sein Weg eine
angeforderte Korrektur nicht oder schlägt deren Bestätigung fehl, beginnt kein
scheinbar gleichwertiger Scan mit stillschweigend abgeschalteter Korrektur.
Epson-Bildverarbeitung darf aus den installierten Komponenten aufgerufen werden;
es wird keine unbemerkte eigene OCR-/Vision-Korrektur als Treiberfunktion ausgegeben.

Ein PDF enthält die korrigierten Bilder mit ihrer Größe aus Pixelmaßen und
300 dpi. Keine zusätzliche OCR und keine Cloud-Verarbeitung. Erzeugung über
Apple-Systemframeworks, anschließende Prüfung auf Lesbarkeit, Seitenzahl und
Reihenfolge. Pro Karte wird die Paarung anhand bestätigter Seiten-/Blattdaten
bzw. einer am Gerät geprüften Reihenfolge bestimmt, nicht anhand zufälliger
Dateisortierung. Eine unvollständige Duplex-Karte wird nicht als vollständiges
zweiseitiges Karten-PDF veröffentlicht.

Bei Stop während einer Vorlage kommen nur nachweislich vollständige Bilder in
das Sammel-PDF. Falls die letzte Duplex-Karte nur eine vollständige Seite lieferte,
wird dieser Umstand angezeigt und die unvollständige Karte privat zur Prüfung
aufbewahrt. Bereits vollständig gescannte Karten gehen dadurch nicht verloren.
Beschädigte oder nur teilweise übertragene Bilder werden nie als gültige Seite
eingebaut.

## Zustände, Prozesse und Sicherheit

Der erste physische Start wird weiterhin vom vorhandenen Epson-Tastenempfänger
bestätigt. Erst nach bestätigtem Schließen und Prozessende startet der jeweilige
Scan-Worker. Der automatische Worker hält die Scanner-Sperre für seine gesamte
Sitzung, auch während er auf Papier wartet. Erst nach bestätigtem Ende, Schließen
und Prozessende darf der Tastenempfänger erneut starten.

Der jetzige normale Worker mit frischem ICA-Prozess pro Auftrag bleibt als
bewährter Weg erhalten. Der automatische Worker verwendet den echten
Epson-Auto-Feeding-Lebenszyklus samt Stop und Timeout. Elternüberwachung,
Sperrdatei, Wiederherstellung der Epson-Dienste und begrenzte, streng geprüfte
Prozessmeldungen gelten für beide Wege. Feste bisherige 130/140-Sekunden-Grenzen
dürfen eine ausdrücklich längere oder unbegrenzte Warte-Sitzung nicht abschießen;
blockierte tatsächliche Übertragungen brauchen weiterhin eine Fehlergrenze.

Seiten werden zunächst vollständig geprüft und privat auf der Platte gehalten.
Eine atomare Sitzungsdatei hält Reihenfolge, Blatt/Seite, bestätigte Bilder,
Einstellungen und Abschlusszustand fest. Das fertige PDF wird erst nach Prüfung
atomar und ohne Überschreiben in den Zielordner übernommen. Quelldaten werden
erst nach bestätigtem Export gelöscht. Die bisherigen Sicherheitsprüfungen für
JPGs bleiben bestehen.

Unbekannte Fehler, Trennung, Festplattenfehler, Absturz oder ein nicht bestätigter
Abschluss führen zur Wiederherstellung, nicht zu einer automatischen Wiederholung
oder einem als vollständig ausgegebenen PDF. Nach Neustart wird eine offene
Sammlung angezeigt und blockiert neue Scans, bis der Nutzer sie geprüft hat.
Vollständig bestätigte Seiten können ausdrücklich als PDF gesichert werden;
Originale bleiben bei unklarem Zustand erhalten. Ein normales Beenden bei offener
Sammlung bietet Sichern oder Aufbewahren; das Schließen des Statusfensters nicht.

## Einstellungen, Migration und Installation

Neue Einstellungen werden versionsbewusst aus den vorhandenen Werten migriert:
Zielordner, Pause und drei Korrekturen bleiben erhalten; Standard für bestehende
Installationen bleibt einseitiges JPG und ausgeschalteter automatischer Einzug.
Neue Werte: Duplex, normales Ausgabeformat, automatischer Einzug und Wartezeit.
Beschädigte oder zukünftige unbekannte Einstellungen werden nicht still zurückgesetzt.

Vor der Migration werden die bisherigen Einstellungen privat gesichert. Die
bestehende App-Sicherung vor dem Ersetzen bleibt erhalten. Bundle-Kennung und
Installationspfad bleiben gleich, damit das gerade eingerichtete macOS-
Anmeldeobjekt weiter auf die installierte App zeigt. Kein zusätzliches Anmeldeobjekt.

Für den lokalen Funktionstest werden die neuen Modi ausdrücklich ausgewählt.
Nach den Tests kann der normale Kartenbetrieb mit Duplex/JPG bereitbleiben;
die automatische Sammlung startet auch dann erst nach Aktivieren dieses Modus
und einem neuen physischen Start. Diese Test-/Abschlusseinstellung ist eine
Vorgabe des Erstellers und bei der Abnahme korrigierbar.

## Umsetzung und Abnahme

Zuerst den echten Auto-Feeding-Weg, die vollständigen Bild-Callbacks einschließlich
beider Seiten und das physische Stop-Ende nachweisen. Das Vorhandensein von
Methodennamen allein gilt nicht als funktionierendes Feature. Bei negativem
Nachweis den konkreten Blocker melden und keinen anderen Ablauf unterschieben.
Der vorhandene funktionierende Build bleibt bis zur geprüften Installation nutzbar.

Tests vor Implementierung für Migration, Duplex-Readback, Blatt-/Seitenzuordnung,
PDF-Seiten und Orientierung, atomaren Export/Kollision, Sitzung/Wartezeit/Stop,
Fehler und Wiederherstellung sowie Prozess-/Sperrreihenfolge. Bestehende Tests
weiterhin ausführen. Build, Signatur und eine unabhängige Abschlussprüfung.

Die entbehrliche Testkarte kann mehrfach verwendet werden. Am Gerät prüfen:
zwei vollständige Seiten bei Duplex, getrennte JPGs und PDF-Seiten, automatisches
Nachlegen ohne weiteren Starttastendruck, Abschluss über echte Stopptaste sowie
über eine für den Test verkürzte Wartezeit. PDFs auf Seitenzahl, Reihenfolge,
Lesbarkeit und Bilddarstellung prüfen. Tatsächlich nicht geprüfte Fälle offen
benennen. Nur lokale Installation, keine Veröffentlichung.

## Quellen und bekannte Unsicherheit

- [Epson: Automatischer Einzug](https://download4.epson.biz/sec_pubs/es-c320w/useg/en/GUID-49D1FC41-261C-4A72-961F-072C79B9F04F.htm)
- [Epson: Tasten, einschließlich Ende des automatischen Einzugs über Stop](https://download4.epson.biz/sec_pubs/es-c320w/useg/en/GUID-A927C6C5-E23A-46B9-9D7A-370ECBEE61A5.htm)
- Installierte Scanner.framework 6.7.84: reine Metadatenabfrage bestätigt
  Auto-Feeding-, Timeout-, Duplex- und kontinuierliche Abschluss-Schnittstellen.
  Der neue aktive Scanweg und die Bildverarbeitung sind damit noch nicht getestet.

Interne Typen, Dateiaufteilung, konkrete Bibliotheksadapter und die kleinste sichere
PDF-Pipeline bleiben technische Entscheidungen des Erstellers. Eine Umstellung
auf einen anderen Benutzungsablauf oder das Weglassen der Stopptaste nicht.
