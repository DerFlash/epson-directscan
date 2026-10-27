# Epson DirectScan v0.3.0-beta.2

Das Projekt heißt jetzt **[DerFlash/epson-directscan](https://github.com/DerFlash/epson-directscan)**.
Issues, Releases und Verlauf sind erhalten; bisherige Repository-URLs leiten weiter.

Diese Beta enthält erstmals eine **fertige Mac-App für Apple Silicon (arm64)**:

- **macos-arm64.dmg:** öffnen und „Epson DirectScan Beta.app“ nach „Programme“ ziehen.
- **macos-arm64.zip:** dieselbe App als ZIP.
- **source.zip:** optionaler Quellcode; `SHA256SUMS` prüft die drei Downloads.

**Signierungsstatus: ad-hoc signiert, nicht notarisiert.** macOS kann das erste
Öffnen blockieren. Wenn du dieser Beta vertraust, bestätige das Öffnen persönlich
unter Systemeinstellungen → Datenschutz & Sicherheit → Dennoch öffnen, wie in
[Apples Anleitung](https://support.apple.com/102445) beschrieben. Die Pakete ändern
keine Sicherheitseinstellungen und enthalten keine Umgehungsskripte.

Vor einem Update laufende Scan-Helfer beenden und die vorhandene App am selben
Ort ersetzen, auch bei einer bisherigen Installation unter `~/Applications`.
So bleiben vorhandene Anmeldezuordnungen erhalten. Einstellungen und Scans liegen
außerhalb der App. Die DMG führt keine privilegierten Installationsskripte aus,
installiert keinen Epson-Treiber und richtet keinen Autostart ein.

Weiterhin erforderlich: **ES-C320W über USB und Epson-Treiber 6.7.84**, separat
installiert. Andere Modelle, WLAN und Intel-Macs sind durch diesen Download nicht
abgenommen. macOS 13+ ist das Build-Ziel; getestet wurde macOS 27.0.1/Apple Silicon.

Build 15 ändert Verpackung, Versionsangaben und Links; die Scannerlogik entspricht
dem am Gerät geprüften Build 14. Duplex-JPG/PDF, kontinuierlicher Einzug und die
Stop-/Einzugs-Korrekturen sind enthalten. Die Grenzen bei
[Kartendrehung (#1)](https://github.com/DerFlash/epson-directscan/issues/1) und
[dunkleren kontinuierlichen Scans (#2)](https://github.com/DerFlash/epson-directscan/issues/2)
bleiben bestehen; nach USB-Trennung muss die App erneut verbunden werden.

Prüfung: 138 lokale Tests (70 Swift, 26 Node, 42 Python), darunter echte ZIP-/DMG-
Pakettests mit Signatur-, Rechte-, Inhalts- und Prüfsummenkontrolle. Falsche bzw.
beschädigte Apps und vorhandene Ausgabeordner werden abgewiesen. Private Build-Pfade werden vor der Veröffentlichung entfernt; das Verpacken
weist noch enthaltene private Build-Pfade ab. Die Quell-App und eine installierte Kopie werden beim Verpacken nicht verändert.
Keine privaten Scans, Einstellungen, Zugangsdaten oder Epson-Binärdateien enthalten.

[Deutsche Installationsanleitung](https://github.com/DerFlash/epson-directscan/blob/v0.3.0-beta.2/docs/NATIVE.de.md)
· [Prüfprotokoll](https://github.com/DerFlash/epson-directscan/blob/v0.3.0-beta.2/docs/VALIDATION.md)
