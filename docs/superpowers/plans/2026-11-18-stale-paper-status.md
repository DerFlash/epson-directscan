# Stale Paper Status Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ein vorbereiteter Scan wird durch eine veraltete negative Papiermeldung nicht vor dem Treiberaufruf verworfen.

**Architecture:** ICA behandelt den gecachten Papierwert als Diagnose. Die native bereits scharfgeschaltete Erfassung wird in `captureArmedFeeding` gekapselt und lässt den tatsächlichen Treiberauftrag über Seiten/Fehler entscheiden.

**Tech Stack:** Swift/ICA, Objective-C, vorhandene native Callback-Testumgebung.

**Spec:** docs/superpowers/specs/2026-11-18-stale-paper-status-design.md

## Global Constraints

- Keine Lockerung der Tasten-, Bereitschafts-, Sperr-, Elternprozess-, Abbruch- oder Originalschutzregeln.
- Bestehende Zeitgrenzen und Profilvorgaben erhalten; keine unbemerkte Wiederholung.
- Nur Statusdaten und technische Bildmetadaten als Diagnosebeleg veröffentlichen.

## Review Focus

- Kein Scan beim Öffnen, bei Zwischenmeldungen oder ohne bestätigte Bereitschaft.
- Negative Papiermeldung verhindert keinen akzeptierten Auftrag mit anschließend tatsächlich gelieferten Seiten.
- Kein Export bei null Seiten oder unbestätigtem Abbruch.
- Stop/Elternverlust während Steuerungsübernahme verhindert Start des Einzugs.
- Shop-, Beleg- und Kartenprofile behalten ihre eigenen Ausgabevorgaben.

### Task 1: Veraltete Vorabmeldung in beiden Scanwegen korrigieren

**Files:** `ScannerController.swift`, `AdapterTests.swift`, `EpsonFeedingWorker.m`, `EpsonFeedingCallbacks.m` unter `native/`.

**Interfaces:** `ScannerController.scanAuthorized()` bleibt der autorisierte ICA-Einstieg; `captureArmedFeeding(scanner, receiver, parent)` führt den vorhandenen bestätigten nativen Auftrag aus.

- [x] Hardwarebefund gegen Digitale Bilder vergleichen und tatsächliche A4-Datei anhand Metadaten prüfen.
- [x] Regressionen mit negativem Papierstatus zuerst schreiben und scheitern sehen.
- [x] Vorabmeldung in beiden Wegen als nicht entscheidenden Cache behandeln; bestehenden Einzug-/Abbruchablauf erhalten.
- [x] Vollständige native Suite einschließlich Callback-Umgebung erfolgreich ausführen.
- [ ] Zusammen mit dem freigegebenen Profil-Editor prüfen, Build 27 erstellen, Review/CI/Merge abschließen und bestehende App mit Sicherung aktualisieren.
- [ ] Abschließenden Dokumentenscan über die Epson-Taste prüfen und Ergebnis klar von reinen Softwareprüfungen unterscheiden.
