# Epson DirectScan v0.3.0-beta.1

Erste öffentliche **Quellcode-Beta der nativen Menüleisten-App** für den Epson
ES-C320W über USB. Sie übernimmt den getesteten Build 14 und ersetzt beim Scannen
die ScanSmart-Oberfläche. Der ältere ScanSmart-AutoSave-Helfer bleibt separat im
Quellcode enthalten.

## Enthalten

- Ablageordner und Status über das Menüleisten-Icon, Scanstart über die Epson-Taste.
- 300 dpi/Farbe, ein- oder doppelseitig: getrennte JPGs oder ein PDF pro Karte.
- Kontinuierlicher automatischer Einzug: nach einem Start weitere Karten nachlegen;
  ein gemeinsames PDF bis Stop oder einstellbarer Wartefrist.
- Schaltbarer Treiberzuschnitt, Schräglagenkorrektur und automatische Orientierung.
- Korrigierter leerer Stop-Abschluss und Abbruch nach etwa 15 Sekunden ohne weitere
  vollständige Bildseite während eines aktiven Einzugs. Echte Stau-/Gerätefehler
  bleiben sichtbar; unbestätigte Dateien bleiben erhalten. Kein automatisches
  Wiederholen eines Scans und kein Überschreiben vorhandener Ausgaben.

## Geprüft und begrenzt

134 lokale Softwaretests (70 Swift, 26 Node, 38 Python), Hilfsprozess-Vertragstest,
Build und Signaturprüfung bestanden. Am ES-C320W wurden Duplex-JPG/PDF,
automatisches Nachlegen, Stop/Timeout, leerer Stop, Einzugsbegrenzung,
Wiederherstellung und ein normaler Kartenscan nach Beseitigung eines echten
Papierstaus geprüft. Der ausführbare Code entspricht dem lokal getesteten Build 14; für die
Veröffentlichung wurden nur Versionsanzeige und zugehörige Signatur angepasst.

Geprüfte Kombination: Apple Silicon, macOS 27.0.1 und **Epson-Treiber 6.7.84**.
Andere Treiberversionen werden abgewiesen. WLAN und andere Modelle sind nicht
unterstützt. Lange Serien, Ab-/Anmeldung, Ruhezustand und erzwungener Stop mitten
in einer Bildübertragung sind nicht am Gerät abgenommen.

Bekannt: Die Kartendrehung ist unzuverlässig
([#1](https://github.com/DerFlash/epson-directscan/issues/1)); kontinuierliche
Scans können dunkler ausfallen
([#2](https://github.com/DerFlash/epson-directscan/issues/2)). Ein echter
Papierstau benötigt eine Prüfung des Papierwegs. Nach Aus-/Einschalten oder
USB-Trennung DirectScan ausdrücklich neu verbinden. Details zur lokalen
Einzugs-/Stop-Korrektur stehen in
[#3](https://github.com/DerFlash/epson-directscan/issues/3).

## Download und Installation

Das Release-ZIP enthält Quellcode und synthetische Testdaten, **keine echten
Scans, privaten Einstellungen, Epson-Binärdateien oder vorgebauten, notarisierten
Apps**. `SHA256SUMS` prüft das beigefügte Quellcode-ZIP.
Epson-Treiber separat installieren, ZIP entpacken und die Bau-/Installationsschritte
in der [deutschen Anleitung](https://github.com/DerFlash/epson-directscan/blob/v0.3.0-beta.1/docs/NATIVE.de.md)
befolgen. Nicht gleichzeitig mit ScanSmart oder älteren Helfern betreiben.
Die native App benötigt weder Bedienungshilfen noch System Events und lädt keine
Scans hoch. Vorhandene App-Versionen werden beim Ersetzen privat gesichert.

[Prüfprotokoll](https://github.com/DerFlash/epson-directscan/blob/v0.3.0-beta.1/docs/VALIDATION.md)
· [Änderungen](https://github.com/DerFlash/epson-directscan/blob/v0.3.0-beta.1/CHANGELOG.md)
· [Sicherheit und Datenschutz](https://github.com/DerFlash/epson-directscan/blob/v0.3.0-beta.1/SECURITY.md)
