# Ausrichtung und feste Außenmaße für Epson DirectScan

Status: vom Nutzer am 27.10.2026 freigegeben; lokal implementiert und softwaregeprüft
(98 native Tests). Die physische Abnahme der neuen Gerätefälle steht noch aus.

## Auftrag und getroffene Entscheidungen

Die vorhandene native Menüleisten-App soll feste Drehungen oder eine verbesserte
automatische Ausrichtung sowie einstellbare Breite und optional Höhe erhalten.
Bei einem Toploader soll **die gesamte Hülle einschließlich transparenter Ränder**
im Bild bleiben. Das innere Kartenmotiv wird nicht ausgeschnitten.

Der Nutzer hat den Ansatz „feste Drehung plus Apples lokale Texterkennung,
zuerst an vorhandenen Scans prüfen“ gewählt. Seine anschließende Präzisierung:
Duplex-Seiten gehören zusammen; eine gut erkennbare Seite bestimmt auch die
Ausrichtung der anderen. Das muss ebenso funktionieren, wenn die bedruckte
Kartenvorderseite auf der anderen Scannerseite liegt.

Der Einbau erfolgt im vorhandenen Checkout auf `feat/orientation-scan-profiles`.
Scanner-Taste, kontinuierlicher Einzug, Stop, Ausgabeordner, JPG/PDF-Gruppierung
und sicherer Export bleiben die Basis. Eine Veröffentlichung oder Installation
ist durch die Wahl des Ansatzes noch nicht gesondert beauftragt.

## Betrachtete Ansätze

1. Feste Drehung plus bisherige Epson-Automatik: kleinster Eingriff, lässt die
   bekannten Erkennungsschwächen aus Issue #1 bestehen.
2. **Gewählt:** feste Drehung plus lokale Apple-Vision-Texterkennung und gemeinsame
   Duplex-Entscheidung. Kein zusätzliches Modell und kein Bild-Upload nötig.
3. Ein eigenes Kartenmodell oder Referenzbild-Vergleich wäre eine mögliche spätere
   Erweiterung für textarme Einzelbilder. Das ist für dieses Vorhaben nicht nötig,
   weil Duplex die Information der jeweils anderen Seite nutzen kann.

## Lokaler Machbarkeitstest vom 27.10.2026

Nur bestehende Scans wurden gelesen. Keine Geräteaktion, Änderung der installierten
App oder Änderung der Originalbilder; letzteres wurde mit SHA-256 und Zeitstempeln
geprüft. Die privaten Originale und OCR-Berichte bleiben außerhalb des Repositorys.

- Zwei unterschiedliche Kartenvorderseiten, darunter ein dunkler kontinuierlicher
  Scan, wurden jeweils digital um 0/90/180/270 Grad gedreht.
- Vision `.fast` erkannte in **8 von 8 Vorderseitenvarianten** die richtige Drehung.
- Eine Pokémon-Rückseite ergab in allen vier Varianten zu wenig verwertbaren Text.
  Die Entscheidung muss hier aus dem Duplex-Paar kommen oder als unsicher gelten.
- Vier OCR-Kandidaten pro Bild benötigten in dieser Messung im Median ca. 0,049 s,
  maximal ca. 0,219 s. Das ist ein lokaler Machbarkeitswert, keine Laufzeitgarantie.
- 64 aus einem vorhandenen Duplex-Paar abgeleitete Kombinationen prüften vertauschte
  Scannerseiten, vier Eingangswinkel sowie beide Drehrichtungsvorzeichen und vier
  feste Rückseitenversätze. Die Paar-Rechnung lieferte jeweils beide erwarteten
  Drehungen. Das sind synthetische Varianten **eines** Paares, keine 64 unabhängigen
  Karten und keine Abnahme der tatsächlichen Treibergeometrie.
- `.accurate` schlug auch bei einem neutralen Textbild mit einem Fehler des Apple-
  Erkennungsmoduls fehl (`e5rt ... precompiled_compute_operation ...`, Fehler 13).
  Standard-/deutsch-englische Einstellungen und CPU-Ausführung änderten das nicht.
  Dieser Modus wird vorerst nicht verwendet; es gibt keine automatische Umschaltung
  auf ihn. Die Ursache innerhalb des Apple-Moduls ist nicht abschließend geklärt.

Die kleine Stichprobe belegt die grundsätzliche Machbarkeit, keine allgemeine
Ausrichtungsgenauigkeit für andere Karten, Sprachen oder Bildqualitäten.

## Gemeinsame Ausrichtungsentscheidung

Ein Profil bietet „Feste Drehung“, „Automatisch – macOS“ und für bestehende
Einstellungen „Automatisch – Epson (bisher)“. Feste Winkel sind 0, 90, 180, 270 Grad
im Uhrzeigersinn. Für die beiden Scannerseiten sind getrennte feste Werte möglich;
diese Werte dienen auch als ausdrückliche Ersatzvorgabe bei unsicherer Automatik.

„Vorne“ und „hinten“ bezeichnen weiterhin Scannerseite/Dateireihenfolge. Das Programm
muss nicht erkennen, welche Kartenfläche inhaltlich die Vorderseite ist, und sortiert
oder benennt Dateien durch die neue Erkennung nicht eigenmächtig um.

Für „Automatisch – macOS“ wird Epsons automatische Drehung in beiden Scanwegen
ausgeschaltet und bestätigt. Es darf keine doppelte automatische Drehung geben.

### Einzelbilder

- Für die Analyse eine verkleinerte Kopie mit maximal 1200 Pixeln längster Kante nutzen.
- Alle vier Drehungen mit Vision `.fast` bewerten. Der endgültige Scan behält seine
  Auflösung; die Analysekopie wird nicht als Ausgabe verwendet.
- Ein Kandidat erhält einen gewichteten Wert aus verwertbaren alphanumerischen
  Zeichen und OCR-Konfidenzen. Eine Konfidenz ist keine geprüfte Wahrscheinlichkeit,
  dass der Drehwinkel stimmt. Leere, punktartige oder sehr kurze Treffer reichen nicht.
- Pilotgrenzen aus dem Vergleich: gewichteter Wert mindestens 12, mindestens zwei
  Textzeilen mit jeweils mindestens drei alphanumerischen Zeichen und Abstand zum
  zweitbesten Kandidaten mindestens 20 % des besten Werts. Das sind benannte interne
  Konstanten, die anhand der Abnahmetests begründet angepasst werden dürfen.
- Ohne ausreichend deutliche Entscheidung gilt die feste Ersatzdrehung. Die App
  speichert normal und zeigt einen sachlichen Hinweis zum letzten Scan; es entsteht
  kein Scannerfehler und kein zusätzlicher Bestätigungsdialog.

### Duplex-Paare

- Nur zwei vollständige Seiten derselben physischen Vorlage gemeinsam bewerten:
  vorhandene Blatt-/Seitenmetadaten nutzen, keine Dateien nach Ankunftszeit mischen.
- Für jede mögliche Orientierung des physischen Blatts beide zugehörigen OCR-Werte
  addieren. Eine Seite ohne Text trägt keinen verwertbaren Wert bei. Dieselbe
  Entscheidung gilt für das Paar; die stärkere Seite kann auf jedem Scannerkanal liegen.
- Die Beziehung der Drehungen ist je Scanweg nachzuweisen: allgemein
  `Drehung_B = Vorzeichen * Drehung_A + Versatz (mod 360)`. Sie darf nicht pauschal
  als „gleicher Winkel“ angenommen werden. Eine gedruckte Rückseite kann zusätzlich
  einen profilbezogenen 0/90/180/270-Grad-Versatz benötigen.
- Für den getesteten ES-C320W/Treiber 6.7.84 werden ICA-Einzelscan und direkter
  kontinuierlicher Einzug mit deaktivierter Treiberdrehung separat kalibriert und
  dokumentiert. Fehlt eine geprüfte Zuordnung, ist gemeinsame Automatik für diesen
  Scanweg nicht freigegeben; die feste Vorgabe bleibt nutzbar.
- Aussagekraft und Abstand gelten für das gemeinsame Ergebnis. Widersprüchliche
  starke Hinweise, Gleichstand oder zwei textarme Seiten führen zur festen Vorgabe
  mit Hinweis, nicht zum willkürlichen Sieger durch die Reihenfolge im Array.
- Fehlende Gegenseiten bleiben der bestehenden Wiederherstellung vorbehalten.
  Kein unvollständiges Paar wird als erfolgreiches zweiseitiges PDF veröffentlicht.

## Scanfläche und Profile

Ein schlankes Profil bündelt Namen, Scanfläche, Ausrichtungsmodus und feste Werte
für beide Scannerseiten. Duplex/Ausgabeart, Zielordner und kontinuierlicher Einzug
bleiben globale Einstellungen wie bisher. Profile können gewählt und bearbeitet
werden; Änderungen gelten nur für neue Aufträge.

- **Automatische Fläche:** bisheriger Zuschnitt bleibt möglich.
- **Feste Breite und Höhe:** beide Werte in Millimetern; kein automatischer
  Randzuschnitt. Der komplette angegebene Bereich einschließlich transparenter
  Flächen wird aufgenommen. Bildinhalte werden nicht auf die Größe verzerrt.
- **Feste Breite, automatische Höhe:** gewünschte Erweiterung, aber eigener
  Treiber-Abnahmepunkt. Erst anbieten, wenn die tatsächliche Längenerkennung ohne
  Reduktion auf einen inneren sichtbaren Kartenrand für den jeweiligen Scanweg
  nachgewiesen ist. Eine nicht unterstützte Variante wird ausdrücklich als solche
  angezeigt, nicht durch eine erfundene Höhe oder stilles Abschneiden ersetzt.
- Für einen transparenten **Toploader werden standardmäßig beide Außenmaße
  verlangt**. Seine transparente Endkante kann nicht allein aus Text oder dem
  inneren Kartenrand bestimmt werden.

Breite bezeichnet die Strecke quer zum Einzug, Höhe die Strecke in Einzugsrichtung,
jeweils vor der Ausgabe-Drehung. Eine 90-Grad-Ausgabe tauscht anschließend die
Bildabmessungen. Die Maße sind ein Scanbereich, kein Versprechen über die mechanische
Einziehbarkeit einer Hülle. Die Gerätegrenzen und der gerade Papierweg bleiben gültig.

Vorschlag für Voreinstellungen: ein bearbeitbares Kartenprofil mit 63 × 88 mm;
Toploader ohne angenommene Universalmaße, der Nutzer trägt seine tatsächlichen
Außenmaße ein. Kein neues Profil wird bei Migration unbemerkt aktiv.

Die Scanfläche wird am mittig geführten Einzug ausgerichtet. Beide Adapter müssen
Einheiten umrechnen, aktuelle Grenzen beachten und angeforderte/übernommene Werte
prüfen. Die korrekte Zentrierung, ganze transparente Ränder und das Zusammenspiel
mit Schräglagenkorrektur sind physische Abnahmepunkte. Papier-Deskew kann bei festen
Formaten im Epson-Treiber eingeschränkt sein; eine wirksame Korrektur darf nicht
behauptet oder durch einen die Hülle beschneidenden Ersatz simuliert werden.

## Integration und Datenhaltung

Die Drehentscheidung und Anwendung werden gemeinsam für beide Scanwege umgesetzt,
mit Apple-Systemframeworks in den vorhandenen isolierten Hintergrundprozessen.
Das genaue Swift-/Objective-C-Interface ist eine Implementierungsentscheidung.

Vollständig empfangene Originalseiten werden zunächst dauerhaft mit Blatt- und
Seitenzuordnung gesichert. Duplex-Verarbeitung wartet auf das zusammengehörige Paar.
Die bestehende Wiederherstellung muss auch bei Prozessabbruch zwischen Empfang,
Korrektur und Export funktionieren. Ein bereits korrigiertes Bild wird bei einer
Wiederholung nicht erneut gedreht. Pro Auftrag werden Profileinstellungen und
Verarbeitungszustand festgehalten.

OCR läuft außerhalb der Menüleisten-UI. Ein begrenztes Analysebudget und Abbruch
müssen mit dem vorhandenen Stop-/Fortschrittsmechanismus zusammenspielen. Ein OCR-
Fehler führt zur gespeicherten festen Ersatzvorgabe und einem Hinweis; ein Geräte-,
unvollständiger Bild- oder Schreibfehler behält die bestehende Fehlerbehandlung.
Nach einem tatsächlichen Abbruch wird kein Hintergrundauftrag erneut gestartet.

Die Ausgabe enthält tatsächlich gedrehte Pixel, korrekte DPI, eine dazu passende
normale Bildorientierung und bei PDF die richtigen Seitengrößen. Unveränderte
Bilder werden möglichst ohne erneute JPG-Kompression weitergereicht. Es wird weder
ein Bild hochgeladen noch der erkannte Kartentext im regulären Diagnoseprotokoll
gespeichert; Winkel, Entscheidungswerte, Laufzeit und Ersatzgrund reichen.

Bestehende Einstellungen werden mit unveränderter privater Sicherung in eine neue
Schema-Version übernommen. Vorheriger Zielordner, Korrekturen und Ausgabeoptionen
bleiben erhalten; bisherige Epson-Automatik bleibt bei dieser Migration zunächst
aktiv. Alte gespeicherte Aufträge bleiben lesbar. App-Pfad, Bundle-ID und bestehender
Anmeldestart werden durch diese Funktion nicht geändert.

## Abnahme

1. Automatisierte Prüfungen mit synthetischen Bildern: feste Pixelrotationen,
   vier Winkel, Maße/DPI/PDF-Boxen, Duplex-Zuordnung in beiden Richtungen,
   widersprüchliche/fehlende OCR, Gleichstände, Ersatzwerte und Wiederherstellung.
2. Der private Vergleich mit vorhandenen Scans muss erneut reproduzierbar sein;
   der Bericht benennt Stichprobe und Grenzen. Private Kartenbilder werden nicht
   als neue öffentliche Testdateien eingecheckt.
3. Physisch auf beiden Scanwegen: eine gut lesbare Testkarte normal und um 180 Grad
   gedreht; zusätzlich 90 Grad zur Bestimmung der Rückseitengeometrie sowie mit
   vertauschten Kartenflächen. Beide Ausgabeseiten müssen sichtbar korrekt stehen.
4. Feste Maße mit einer normal einziehbaren Karte und einer mechanisch geeigneten
   entbehrlichen Hülle: vollständige Außenränder, korrekte Zentrierung, kein innerer
   Karten-Autocrop; Duplex-JPG und PDF sowie kontinuierliche Sammlung prüfen.
5. Breite mit automatischer Höhe nur nach eigenem Nachweis anbieten. Stop,
   erfolgloser Einzug, Inaktivitätsabschluss und Rückkehr zu Bereit dürfen sich
   durch das Warten auf Paare oder OCR nicht verschlechtern.
6. Erst nach Implementierung, passenden Tests und separatem Auftrag lokal installieren
   bzw. veröffentlichen. Der Machbarkeitstest ändert die installierte Beta nicht.

## Quellen

- Bestehender Code: `ScannerController.swift`, `EpsonFeedingWorker.m`,
  `EpsonImageProcessing.m`, `Settings.swift`, `ScanStorage.swift` und `PageManifest.swift`.
- Bekannte Ausrichtungsgrenze: https://github.com/DerFlash/epson-directscan/issues/1
- Epson zu benutzerdefinierten Größen und transparenten Rändern:
  https://download4.epson.biz/sec_pubs/es-c320w/useg/en/GUID-8F46A76E-AF4D-4AFB-8BDC-4E44E1A5CC1E.htm
- Apple Vision:
  https://developer.apple.com/documentation/vision/recognizing-text-in-images
