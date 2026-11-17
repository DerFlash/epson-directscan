# Belege und Karten per Profil wechseln

Der Nutzer möchte ein Belegprofil, das Eingangsordner und PDF-Ausgabe speichert,
und mit einem Profilwechsel zu seinen bisherigen Karteneinstellungen zurückkehren.

Die bestehenden Swift-/AppKit-Profile werden um optionale Ablage-/Scanvorgaben
ergänzt. Eine zweite App oder ein externer Umschalter würde Einstellungen doppeln.
Ein einzelnes Belegprofil ohne gespeicherte Kartenvorgaben könnte die Rückkehr
zum bisherigen Ordner und JPG nicht erfüllen.

Beim Profilwechsel werden die aktuellen Vorgaben des verlassenen Profils
gesichert und die des gewählten Profils geladen. Auch „Bisherige Einstellungen“
behält seine Vorgaben. Alle bestehenden Profile ohne Vorgaben übernehmen vor dem
ersten Wechsel die bisher gemeinsam genutzten Werte. Scanfläche, Drehungen und Referenzen bleiben erhalten.

Vorgaben umfassen Ordner, JPG/PDF, Duplex, kontinuierlichen Einzug, Wartezeit
und die drei Korrekturschalter. Der Profil-Editor zeigt Ordner und Ausgabe;
weitere Vorgaben bleiben über die bestehenden Menüs einstellbar.
Ein neues „Belege“-Profil verwendet automatische Fläche, lokale automatische
Ausrichtung und einseitige PDF-Ausgabe pro Blatt. Mehrseitige Dokumente können
wie bisher den kontinuierlichen Einzug verwenden.

Die optionalen Ergänzungen bleiben Schema 3; alte Einstellungen und eingefrorene
Aufträge müssen lesbar bleiben. Ungültige Zielprofile werden vor Zustandsänderungen
abgewiesen. Während Scan/Export sind Profiländerungen weiterhin gesperrt.
Keine Änderung an Treiber, Einzug, Kartenmaßen oder OCR/PDF-Inhalten.

Der echte Eingangsordner wird vor Einrichtung aus der Nutzerantwort übernommen.
Installation erfolgt am bisherigen App-Pfad mit Sicherung von App und Einstellungen.
Es wird kein Hardware-Scan ohne bereitgelegtes Dokument ausgelöst.
