import SwiftUI

/// Explanations shown behind the (?) buttons. Written from the ConneX in-app help
/// screens and the observed behaviour, in our own words.
enum Help {
    static let volume = Text2(
        "Master volume of the speakers (0–30). It is the same setting as the volume knob on the active speaker, so turning the knob also moves this slider. Click the speaker icons at either end to step down or up by one (hold to repeat).",
        "A hangfalak fő hangereje (0–30). Ugyanaz, mint az aktív hangfal hangerőgombja: ha a gombot tekered, ez a csúszka is követi. A két végén lévő hangszóró ikonnal egyesével halkíthatsz vagy hangosíthatsz (nyomva tartva ismétel).")

    static let soundMode = Text2(
        "Monitor: relatively flat response, close to the original recording, for mixing and critical listening.\nMusic: balanced highs, mids and lows for everyday listening (classical, light music, etc.).\nCustom: your own 9-band EQ curve on top of Monitor or Music, edited right here below.",
        "Monitor: viszonylag lineáris hangzás, közel az eredeti felvételhez; keveréshez, kritikus hallgatáshoz.\nMusic: kiegyensúlyozott magas, közép és mély; mindennapi zenehallgatáshoz (klasszikus, könnyűzene stb.).\nCustom: saját 9 sávos EQ-görbe a Monitor vagy a Music hangzásra építve; lent, ebben a panelben szerkesztheted.")

    static let lowCut = Text2(
        "Attenuates frequencies below the chosen frequency (20–100 Hz). Useful with a subwoofer or when the bass booms in the room. Default: 30 Hz — the ↺ button restores it.",
        "A választott frekvencia (20–100 Hz) alatti hangokat csillapítja. Mélynyomó mellett hasznos, vagy ha a mély túl erős, dübörög a szobában. Alapérték: 30 Hz, a ↺ gomb ezt állítja vissza.")

    static let slope = Text2(
        "How steeply the low cutoff filter rolls off below the cutoff frequency: −6 dB/octave is gentle, −24 dB/octave is the steepest.",
        "Milyen meredeken vág a mélyvágó szűrő a frekvencia alatt: −6 dB/oktáv lágy, −24 dB/oktáv a legmeredekebb.")

    static let acousticSpace = Text2(
        "Compensates the bass boost caused by where the speakers stand. 0 dB in the middle of a room, down to −4 dB in a corner: the closer the speaker is to a wall or corner, the lower the value should be.",
        "A hangfalak elhelyezéséből adódó mélykiemelést kompenzálja. 0 dB a szoba közepén, −4 dB sarokban: minél közelebb van a hangfal a falhoz vagy sarokhoz, annál kisebb értéket válassz.")

    static let desktopControl = Text2(
        "When the speakers stand on a desk, or something is in front of them, certain frequencies get an audible boost from the reflections. Turn this on to reduce that effect.",
        "Ha a hangfalak asztalon állnak, vagy valami van előttük, a visszaverődések miatt egyes frekvenciák kiemelődnek. Ha bekapcsolod, ez a funkció csökkenti ezt a hatást.")

    static let channel = Text2(
        "Which channel the active speaker (the one with the power socket and controls) plays. By default it is the right channel and should stand on the right; if you swap the speakers' positions, switch this to Left.",
        "Melyik csatornát szólaltatja meg az aktív hangfal (amelyiken a tápcsatlakozó és a kezelőszervek vannak). Alapból a jobb csatorna, és jobb oldalon kell állnia; ha felcseréled a hangfalakat, válaszd a Bal beállítást.")

    static let codec = Text2(
        "LDAC is a high-quality Bluetooth audio codec. 96 kHz gives the best quality, 44.1/48 kHz balances quality and connection stability, Off uses the default codec. The source must support LDAC (most Android phones do; Macs don't — a Mac uses AAC/SBC either way). Higher LDAC bitrates can cause dropouts or latency depending on the phone and interference. The speaker reconnects after a change.",
        "Az LDAC egy jó minőségű Bluetooth-audiokodek. A 96 kHz-es beállítás adja a legjobb minőséget, a 44,1/48 kHz-es egyensúlyt tart a minőség és a kapcsolat stabilitása között. Ha az LDAC-ot kikapcsolod, a hangfal az alapértelmezett kodeket használja. A lejátszó eszköznek is támogatnia kell az LDAC-ot: a legtöbb Android telefon tudja, a Mac nem (az mindig AAC-t vagy SBC-t használ). Nagyobb LDAC-bitrátánál a telefontól és a környezeti zavaroktól függően akadozhat vagy késhet a hang. Váltás után a hangfal újracsatlakozik.")

    static let devices = Text2(
        "Devices paired with the speaker. At most two can be connected at the same time; switch one off to make room for another. Switching off this Mac stops its audio over Bluetooth, but this app stays connected for control.",
        "A hangfalhoz párosított eszközök. Egyszerre legfeljebb kettő kapcsolódhat; kapcsolj ki egyet, hogy helyet csinálj egy másiknak. Ha ezt a Macet kapcsolod ki, a Mac Bluetooth-hangja megszakad, de az app vezérlésre csatlakozva marad.")

    static let eqGain = Text2(
        "Gain is how much a frequency band is amplified, in decibels: the ratio between output and input. Each of the 9 bands goes from −3 to +3 dB in 0.5 dB steps; higher means louder at that frequency. Changes are sent when you release the slider.",
        "Az erősítés (gain) azt adja meg, mennyire emeli ki az adott frekvenciasávot, decibelben: a kimenet és a bemenet aránya. A 9 sáv mindegyike −3 és +3 dB között állítható, 0,5 dB-es lépésekben; minél nagyobb az érték, annál hangosabb az adott frekvencia. Az új érték a csúszka elengedésekor kerül át a hangfalra.")

    static let eqBase = Text2(
        "The custom EQ is applied on top of a preset: choose Monitor or Music as the base, then fine-tune each band.",
        "Az egyéni EQ egy alaphangzásra épül: válaszd ki a Monitor vagy a Music beállítást alapnak, aztán azon finomhangold a sávokat.")

    static let eqReset = Text2(
        "Sets every band back to 0 dB and the base to Monitor.",
        "Minden sávot 0 dB-re, az alapot Monitorra állítja vissza.")

    static let autoConnect = Text2(
        "The speaker accepts only one control app at a time over Bluetooth LE. Turn this off to release the speaker so the ConneX app on your phone can connect. Audio playback is not affected.",
        "A hangfalhoz BLE-n egyszerre csak egy vezérlőapp kapcsolódhat. Kapcsold ki, ha a telefonon a ConneX appal szeretnél csatlakozni. A zenelejátszást ez nem érinti.")
}

/// A small clickable (?) that shows an explanation in a popover.
struct HelpButton: View {
    let text: Text2
    let lang: AppLanguage
    @State private var shown = false

    var body: some View {
        Button { shown.toggle() } label: {
            Image(systemName: "questionmark.circle").foregroundStyle(.secondary)
        }
        .buttonStyle(.borderless)
        .help(lang == .english ? "What does this do?" : "Mire való?")
        .popover(isPresented: $shown, arrowEdge: .trailing) {
            Text(text(lang))
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: 260, alignment: .leading)
                .padding(12)
        }
    }
}
