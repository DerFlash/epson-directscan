import AppKit
import DirectScanCore

final class ProfilePanel: NSWindowController, NSWindowDelegate {
    private var snapshot: ScanSettings
    private var current: ScanProfile
    private var completed = false
    private let completion: (ScanSettings?) -> Bool
    private let profiles = NSPopUpButton(), area = NSPopUpButton(), orientation = NSPopUpButton()
    private let front = NSPopUpButton(), back = NSPopUpButton(), offset = NSPopUpButton()
    private let name = NSTextField(), width = NSTextField(), height = NSTextField()
    private let hint = NSTextField(wrappingLabelWithString:"")
    private let removeButton = NSButton()
    init(settings: ScanSettings, completion: @escaping (ScanSettings?) -> Bool) {
        snapshot = settings;self.completion = completion
        if let selected = settings.activeProfile ?? settings.profiles.first { current = selected }
        else { var p = ScanProfile(name:"Karte");p.area = ScanArea(widthMM:63,heightMM:88);p.orientation = .vision;current = p }
        let panel = NSPanel(contentRect:NSRect(x:0,y:0,width:560,height:580),styleMask:[.titled,.closable],backing:.buffered,defer:false)
        super.init(window:panel);panel.title = "Scanprofile";panel.isReleasedWhenClosed = false;panel.delegate = self
        let content = NSView(frame:panel.frame);panel.contentView = content
        func label(_ text:String,_ y:CGFloat) { let v = NSTextField(labelWithString:text);v.frame=NSRect(x:20,y:y,width:200,height:24);content.addSubview(v) }
        func field(_ v:NSView,_ y:CGFloat) {v.frame=NSRect(x:220,y:y,width:315,height:26);content.addSubview(v)}
        label("Profil bearbeiten",530)
        for p in settings.profiles {profiles.addItem(withTitle:p.name);profiles.lastItem?.representedObject=p.id}
        profiles.addItem(withTitle:"Neues Kartenprofil");profiles.lastItem?.representedObject="card"
        profiles.addItem(withTitle:"Neuer Toploader");profiles.lastItem?.representedObject="holder"
        profiles.target=self;profiles.action=#selector(selectProfile);field(profiles,530)
        if let index=settings.profiles.firstIndex(where:{$0.id==current.id}) {profiles.selectItem(at:index)} else {profiles.selectItem(at:settings.profiles.count)}
        label("Name",489);field(name,489)
        area.addItems(withTitles:["Automatische Scanfläche","Feste Außenmaße"]);area.target=self;area.action=#selector(updateControls)
        label("Scanfläche",448);field(area,448)
        label("Breite quer zum Einzug (mm)",407);field(width,407)
        label("Höhe in Einzugsrichtung (mm)",366);field(height,366)
        orientation.addItems(withTitles:["Feste Drehung","Automatisch – macOS","Automatisch – Epson (bisher)"])
        orientation.target=self;orientation.action=#selector(updateControls)
        label("Ausrichtung",325);field(orientation,325)
        for popup in [front,back,offset] {popup.addItems(withTitles:["0° – unverändert","90° im Uhrzeigersinn","180°","270° im Uhrzeigersinn"])}
        label("Vorne / feste Ersatzdrehung",284);field(front,284)
        label("Hinten / feste Ersatzdrehung",243);field(back,243)
        label("Druckversatz der Rückseite",202);field(offset,202)
        hint.frame=NSRect(x:20,y:70,width:520,height:118);hint.font = .systemFont(ofSize:12);hint.textColor = .secondaryLabelColor;content.addSubview(hint)
        func button(_ title:String,_ x:CGFloat,_ w:CGFloat,_ action:Selector)->NSButton {
            let b=NSButton(title:title,target:self,action:action);b.bezelStyle = .rounded;b.frame=NSRect(x:x,y:20,width:w,height:32);content.addSubview(b);return b
        }
        removeButton.title="Profil löschen";removeButton.target=self;removeButton.action=#selector(removeProfile);removeButton.bezelStyle = .rounded
        removeButton.frame=NSRect(x:16,y:20,width:130,height:32);content.addSubview(removeButton)
        _ = button("Abbrechen",240,110,#selector(cancel))
        let save=button("Speichern und verwenden",350,195,#selector(save));save.keyEquivalent="\r"
        load(current);panel.center()
    }
    required init?(coder:NSCoder) { fatalError("Not supported") }
    private func load(_ profile:ScanProfile) {
        current=profile;name.stringValue=profile.name
        area.selectItem(at:profile.area.isAutomatic ? 0 : 1)
        width.stringValue=profile.area.widthMM.map{String(format:"%g",$0)} ?? ""
        height.stringValue=profile.area.heightMM.map{String(format:"%g",$0)} ?? ""
        orientation.selectItem(at:OrientationMode.allCases.firstIndex(of:profile.orientation) ?? 0)
        front.selectItem(at:profile.frontRotation/90);back.selectItem(at:profile.backRotation/90);offset.selectItem(at:profile.printedBackOffset/90)
        updateControls()
    }
    @objc private func selectProfile() {
        if let id=profiles.selectedItem?.representedObject as? UUID,let p=snapshot.profiles.first(where:{$0.id==id}) {load(p);return}
        let holder=profiles.selectedItem?.representedObject as? String == "holder"
        var p=ScanProfile(name:holder ? "Toploader" : "Karte");p.orientation = .vision
        if !holder {p.area=ScanArea(widthMM:63,heightMM:88)}
        load(p)
        if holder {area.selectItem(at:1);updateControls()}
    }
    @objc private func updateControls() {
        width.isEnabled=area.indexOfSelectedItem==1;height.isEnabled=width.isEnabled
        let mode=OrientationMode.allCases[max(0,orientation.indexOfSelectedItem)]
        front.isEnabled=mode != .epson;back.isEnabled=mode != .epson;offset.isEnabled=mode == .vision
        removeButton.isEnabled=snapshot.profiles.contains(where:{$0.id==current.id})
        var text="Außenmaße vor der Drehung. Beim Einzelscan schneidet die App die feste Fläche mittig aus dem Papierformat aus; automatischer Randzuschnitt ist aus. Epson-Drehung nur bei automatischer Fläche. Automatische Höhe ist noch nicht freigegeben."
        if mode == .vision && snapshot.duplex && (snapshot.automaticFeeding ? current.feedingMapping : current.icaMapping) == nil {
            text += "\nDie Duplex-Zuordnung dieses Scanwegs ist noch nicht kalibriert. Bis zur Geräteprüfung gelten die festen Ersatzdrehungen."
        } else if mode == .vision {text += "\nBei unsicherer Erkennung gelten die festen Ersatzdrehungen. Vorne/hinten bezeichnet die Scannerseite."}
        hint.stringValue=text
    }
    @objc private func save() {
        var p=current;p.name=name.stringValue.trimmingCharacters(in:.whitespacesAndNewlines)
        if area.indexOfSelectedItem==1 {
            guard let w=Double(width.stringValue.replacingOccurrences(of:",",with:".")),let h=Double(height.stringValue.replacingOccurrences(of:",",with:".")) else {showError("Bitte beide Außenmaße in Millimetern eingeben.");return}
            p.area=ScanArea(widthMM:w,heightMM:h)
        } else {p.area=ScanArea()}
        p.orientation=OrientationMode.allCases[orientation.indexOfSelectedItem]
        p.frontRotation=front.indexOfSelectedItem*90;p.backRotation=back.indexOfSelectedItem*90;p.printedBackOffset=offset.indexOfSelectedItem*90
        var next=snapshot
        if let index=next.profiles.firstIndex(where:{$0.id==p.id}) {next.profiles[index]=p} else {next.profiles.append(p)}
        next.activeProfileID=p.id
        do {try p.validateForCapture();try next.validate();finish(next)} catch {showError("Bitte Profilnamen, Drehungen und Maße prüfen. Breite:50,8–215,9mm, Höhe:50,8–297mm. Bei fester Fläche bitte feste Drehung oder Automatisch – macOS wählen.")}
    }
    @objc private func removeProfile() {
        var next=snapshot;next.profiles.removeAll{$0.id==current.id}
        if next.activeProfileID==current.id {next.activeProfileID=nil}
        finish(next)
    }
    @objc private func cancel() {finish(nil)}
    private func finish(_ next:ScanSettings?) {
        guard !completed,completion(next) else{return};completed=true;close()
    }
    func windowWillClose(_ notification:Notification) {if !completed {_=completion(nil);completed=true}}
    private func showError(_ text:String) {let a=NSAlert();a.messageText="Profil prüfen";a.informativeText=text;a.runModal()}
}
