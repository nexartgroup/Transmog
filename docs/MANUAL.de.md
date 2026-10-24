# Transmog - ausfuehrliche Beschreibung (Deutsch)

Kurzfassung, Installation und Status: [README.md](../README.md) - English manual:
[MANUAL.en.md](MANUAL.en.md) - Pruefliste fuer den Spieltest: [CHECKLIST.de.md](CHECKLIST.de.md).

Hinweis zur Schreibweise: Umlaute und ss stehen in dieser Beschreibung als ae, oe, ue, ss.

Addon fuer **World of Warcraft 3.3.5a (Interface 30300)** auf einem
**AzerothCore**-Server mit dem Modul **mod-transmog-plus**. Es ersetzt das
Gossip-Menue des Transmogrifizierers durch ein flaches, dunkles Fenster: grosse
3D-Vorschau, Raster der gesammelten Aussehen, Filter, Outfits und Kostenanzeige.

```
Servermodul -> was   gesammelte Aussehen (kontoweit), Regeln, Preis, Anwenden
Addon       -> wie   Auswahl, Vorschau, Filter, Outfits, Kosten, Bedienung
Spieler     -> ob    angewendet wird nur nach einem Klick auf Anwenden
```

Das Addon kann am Charakter nichts aendern, was der Server nicht gestattet: es
schickt Befehle, der Server prueft Sammlung, Regeln und Geld. Die Naehe zum NPC
prueft der Server **nicht**; bis Version 2.0 erzwang das Addon sie freiwillig, **ab
Version 2.1 nicht mehr**: transmoggen geht ueberall, ohne mit dem NPC zu sprechen
(Option "Anwenden auch ohne Transmogrifizierer", standardmaessig an; ausgeschaltet
gibt es wieder den Vorschau-Modus, siehe 2). Version 2.0 war eine Neufassung der
Version 1.x (CMaNGOS-Port); Ordnername und Daten des alten Addons bleiben nutzbar
(siehe 4). Was sich mit 2.1 geaendert hat, steht unter 10.

## 1. Kurzbeschreibung und Voraussetzungen

| Was | Warum |
|---|---|
| Client 3.3.5a | `## Interface: 30300` |
| **mod-transmog-plus** auf dem Server | liefert Listen, Preise und wendet an; ohne das Modul antwortet nichts (das Addon meldet es nach 8 s) |
| Transmogrifizierer-NPC | seit 2.1 **nicht noetig**: `/transmog` genuegt, Anwenden geht ueberall (der Server prueft den Abstand nicht). Spricht man den NPC an, oeffnet er das Fenster wie bisher; laut README des Moduls `.npc add 190012`. Nur wenn die Option "Anwenden auch ohne Transmogrifizierer" ausgeschaltet ist, gibt es ohne NPC den Vorschau-Modus |
| Ordner `Interface/AddOns/Transmog` | der Ordnername muss `Transmog` lauten, passend zu `Transmog.toc` |

Das Servermodul bringt unter `addon/Transmog` ein aelteres Addon gleichen Namens
mit; dieses hier ersetzt es (nicht beide installieren). Ohne Addon bleibt das
normale Gossip-Menue des NPCs in Betrieb.

### Installation

Ordner `Transmog` nach `World of Warcraft/Interface/AddOns/Transmog/` kopieren (beim
ZIP-Download von GitHub den Ordner `Transmog-main` in `Transmog` umbenennen; `tests/`
und `docs/` werden zum Spielen nicht gebraucht). Eine vorhandene Version 1.x
**ersetzen, nicht ueberkopieren** (alter Ordner vorher weg; Rueckweg siehe 9). Spiel
**neu starten**: neue Dateien liest der
Client nur beim Start, ein `/reload` genuegt nicht. Beim Anmelden erscheint eine
Zeile "Transmog 2.1 ... /transmog" im Chat.

## 2. Funktionen

### Slots und Anordnung

Alle **14** transmogbaren Slots stehen in zwei Spalten links und rechts der
Vorschau (feste Reihenfolge):

| Spalte | von oben nach unten |
|---|---|
| links | Kopf, Schulter, Ruecken, Brust, Hemd, Wappenrock, Handgelenke |
| rechts | Haende, Taille, Beine, Fuesse, (kleine Luecke) Haupthand, Nebenhand, Fernkampf |

* **Symbol**: das gewaehlte oder angewendete Aussehen, sonst der angelegte
  Gegenstand, sonst die abgedunkelte Leertextur des Slots.
* **Rand**: blau = ausgewaehlt, gelb mit `*` = Aenderung vorgemerkt, rosa =
  angewendet, rot mit `!` = inaktiv (siehe unten). Ein leerer Slot ist
  abgedunkelt, ein nicht transmogbarer zusaetzlich mit `x` gesperrt.
* **Zahl unten rechts**: Anzahl verfuegbarer Aussehen (ab 100 als `99+`).
* **Tooltip**: Slotname, angelegter Gegenstand, Zustand (Transmogrifiziert zu /
  Verborgen / Ausstehend / Inaktiv), Anzahl, Bedienhinweise; bei gesperrten
  Slots der Grund.
* **Nie transmogbar** (Server `CanNeverTransmog`): Hals, Ringe, Schmuck, Relikte,
  Munition, Koecher, Beutel. Ein Relikt im Fernkampf-Slot (Druide, Paladin,
  Schamane, Todesritter) sperrt diesen Slot; der Klick nennt den Grund.
* **Verborgen** ist nur in 11 Slots erlaubt (alle ausser Haupthand, Nebenhand,
  Fernkampf).

### Vorschau

* Grosse Figur des eigenen Charakters, angekleidet mit dem gewuenschten Aussehen
  jedes Slots (Auswahl, sonst Angewendetes, sonst angelegter Gegenstand); sie
  folgt jeder Auswahl sofort.
* Drehen, Verschieben, Zoomen mit der Maus, Knoepfe `<` `>` und "Zuruecksetzen"
  (siehe 3). Ein gewaehlter Umhang dreht die Figur nach hinten.
* Einhandwaffen in der Nebenhand kann die Vorschau nur in der Haupthand zeigen
  (siehe "Hinweis zur Nebenhand-Vorschau"): solange du den Nebenhand-Slot
  bearbeitest, erscheint die gewaehlte Waffe dort (mit Hinweis unter dem Modell);
  sonst bleibt sie weg. Schilde, Nebenhand-Gegenstaende und Nebenhandwaffen
  erscheinen links.

### Raster

* Je Aussehen eine Kachel mit 3D-Modell, Name in Qualitaetsfarbe und Marken:
  Stern = Favorit, rosa Rand mit Haken = angewendet, blauer Rand = ausgewaehlt
  (noch nicht angewendet), "NEU" = in dieser Sitzung neu gesammelt.
* Die Zahl der Spalten und Zeilen folgt der Fenstergroesse; die Kachelgroesse
  stellt man in den Optionen ein (Klein 0,8 / Mittel 1,0 / Gross 1,25 /
  Sehr gross 1,5; hoechstens 120 Kacheln je Seite).
* Blaetterleiste unten (erste, vorige, naechste, letzte Seite, "Seite x / y",
  "n von m Aussehen"; dahinter "(gefiltert)", wenn Filter etwas ausblenden, sonst
  "(k Doppelte ausgeblendet)", wenn nur "Doppelte ausblenden" etwas versteckt).
  Das Mausrad blaettert.
* Zu lange Namen werden an einer Zeichengrenze mit "..." gekuerzt; der volle Name
  steht im Tooltip. Grosse Seiten kleiden ihre Modelle schrittweise an (hoechstens
  16 je Durchgang, der Rest folgt Sekundenbruchteile spaeter), damit das Bild beim
  Blaettern nicht stockt; solange ein Modell fehlt, steht der Platzhalter da.
* Die Rasterflaeche meldet Sonderzustaende statt Kacheln: kein Slot gewaehlt,
  Slot leer, nicht transmogbar, Liste laedt (mit Fortschrittsbalken), noch keine
  passenden Aussehen, Filter blenden alles aus (mit Knopf "Filter
  zuruecksetzen"), Servermodul antwortet nicht.

### Filter, Suche, Sortierung

| Element | Wirkung |
|---|---|
| Suchfeld | Begriffe durch Leerzeichen getrennt, **alle** muessen passen: Name oder lokalisierter Typ (Teilstring, Gross/Klein egal, auch Umlaute und Kyrillisch), `#1234` nur Gegenstands-ID, eine reine Zahl auch als ID |
| Sortierung | Qualitaet (absteigend, dann Name; Standard), Name, Gegenstandsstufe (absteigend) |
| Qualitaets-Chips | farbige Quadrate, nur fuer Qualitaeten, die in der Liste vorkommen; Klick blendet aus/ein, Tooltip nennt die Anzahl |
| Menue "Filter" | "Doppelte ausblenden" (Standard an), "Nur Favoriten", "Nur neue", Liste der **Typen** (Stoff/Leder/Kette/Platte, Waffenarten ...) mit Anzahl; der Typ des angelegten Gegenstands laesst sich nicht ausblenden |
| Chips Stern und "Neu" | Schnellschalter fuer Favoriten bzw. neue Aussehen (verschwinden bei schmalem Fenster) |
| Knopf `x` | alle Filter zuruecksetzen (Suche, Qualitaeten, Typen, Favoriten, Neu; Sortierung und Doppelte bleiben) |

* **Doppelte ausblenden** ist eine Naeherung: gleiches Symbol, gleicher Typ und
  gleicher Ausruestungsplatz zaehlen als gleiches Aussehen (der Client kann das
  echte Modell nicht lesen). Es bleibt der Eintrag, der ausgewaehlt, angewendet,
  Favorit oder hoeherwertig ist.
* Ein Klick irgendwo ausserhalb des Suchfelds (Kachel, Slot, Knopf, Chip, Modell,
  freie Fensterflaeche) nimmt dem Suchfeld den Tastaturfokus; der bis dahin
  getippte Suchtext wird trotzdem uebernommen.
* Filter, Sortierung, Favoriten und Outfits gelten **je Charakter**.

### Kacheln "Original" und "Verborgen"

Sie stehen auf Seite 1 vor den Aussehen und werden von Filtern nie ausgeblendet.

* **Original**: zeigt den angelegten Gegenstand und entfernt die Transmogrifikation
  (Auswahl 0). Die Kachel ist immer die erste (stabile Reihenfolge); ohne
  angewendetes Aussehen gilt sie als "aktuell angewendet".
* **Verborgen**: blendet den Slot aus (Symbol "unsichtbar"). Nur in den 11
  verbergbaren Slots. Kostet nichts.

### Hinweis zur Nebenhand-Vorschau

Der 3.3.5-Client zeigt eine anprobierte Einhandwaffe immer in der **Haupthand**,
auch wenn du den Nebenhand-Slot bearbeitest (Grenze der Anprobe, die das alte
Addon ebenso hatte). Die Anwendung selbst ist davon nicht betroffen: der Server
setzt die Waffe in die Nebenhand. Im Tooltip der Kachel steht ein entsprechender
Hinweis. Im grossen Vorschaumodell gilt: solange der Nebenhand-Slot bearbeitet
wird und eine Auswahl aussteht, zeigt die Vorschau die gewaehlte Einhandwaffe in
der Haupthand (sie ersetzt dort die Haupthandwaffe, nur in der Vorschau; Hinweis
unter dem Modell). Wechselst du zu einem anderen Slot oder waehlst Schild,
Original oder Nebenhandwaffe, kehrt die echte bzw. gewaehlte Haupthandwaffe
zurueck. Bei einem anderen bearbeiteten Slot wird die Nebenhand-Waffe nicht
gezeigt (anderer Hinweis).

### Inaktive Aussehen

Der Server behaelt ein gespeichertes Aussehen auch dann, wenn der angelegte
Gegenstand wechselt und es nicht mehr passt; er **zeigt** dann das echte Item.
Das Addon erkennt das (Aussehen steht nicht in der fertig geladenen Liste des
Slots), markiert den Slot rot mit `!`, nennt es im Tooltip (rot: "Transmogrifikation
inaktiv: ...") und behandelt den Slot beim Bearbeiten wie "ohne Aussehen".

### Kostenanzeige

* Der Client kennt den Preis nicht; er fragt den Server (`CalculateCost`) fuer die
  vorgemerkten Aenderungen. Der Preis ist pauschal je angewendetem Aussehen
  (`Transmog.PriceCopper`, in der `conf.dist` 1000 Kupfer); **Verborgen und
  Entfernen kosten 0**.
* Fusszeile rechts: "Kosten:" mit Gold/Silber/Kupfer-Symbolen, gruen = bezahlbar,
  rot = zu wenig Geld, "Kostenlos" bei 0, `...` waehrend der Berechnung, `?` wenn
  der Server nicht antwortete.
* Zu wenig Geld sperrt **Anwenden**; der Tooltip des Knopfs nennt den Grund.

### Outfits

Reiter **Outfits**: den aktuellen Look (Auswahl und Angewendetes, auch
"Verborgen") unter einem Namen speichern.

* Hoechstens 50 Outfits je Charakter, Name bis 32 Zeichen, ohne Beachtung der
  Gross-/Kleinschreibung eindeutig; Standardname "Outfit n".
* Je Zeile: Name, bis zu 8 Symbole, "Teile: n" bzw. "Verfuegbar: x / n"; ein
  gruener Rand markiert das Outfit, das dem aktuellen Look entspricht.
* **Laden** merkt die Teile als Auswahl vor, wo sie fuer den angelegten
  Gegenstand verfuegbar sind (sichtbar im Reiter Gegenstaende und an der
  Figur); **nichts wird angewendet**, bis man Anwenden klickt. Die Fusszeile
  nennt, wie viele Teile geladen und wie viele nicht verfuegbar waren; der
  Tooltip der Zeile nennt je Slot das Teil und bei uebersprungenen Teilen den
  Grund (Slot leer, nicht transmogbar, Liste laedt noch, Aussehen nicht
  verfuegbar, Slot nicht verbergbar).
* **Ueberschreiben**, **Umbenennen**, **Loeschen** (mit Rueckfrage).

### Tooltips

* **Rosa Zeile "Aussehen nicht gesammelt"** in Item-Tooltips (auch Vergleichs- und
  Chat-Tooltips) fuer Ausruestung, die der Server als nicht gesammelt meldet. Je
  Gegenstand wird einmal gefragt (hoechstens 30 Abfragen je Sekunde); ein
  "nicht gesammelt" gilt 45 s, danach fragt der naechste Tooltip erneut (ein
  anderer Zugang desselben Kontos kann den Gegenstand inzwischen gesammelt haben).
  "Gesammelt" und "nicht anwendbar" bleiben fuer die Sitzung. Die Zeile erscheint
  mit kurzer Verzoegerung.
* **Rosa Zeile "Transmogrifiziert zu: ..."** (bzw. "Verborgen") im Tooltip der
  eigenen angelegten Gegenstaende; **rot "Transmogrifikation inaktiv: ..."**,
  wenn das Aussehen nicht mehr passt.
* Beide Zeilen lassen sich in den Optionen abschalten.

### Benachrichtigungen

Eine flache Karte (Symbol, "Neues Aussehen freigeschaltet", Name in
Qualitaetsfarbe) fuer jedes neu gesammelte Aussehen, standardmaessig oben mittig.

* Hoechstens 3 Karten gleichzeitig, weitere warten.
* Ab 4 Aussehen innerhalb von 2 s eine **Sammelkarte** ("Aussehen: n").
* In den ersten 10 s nach dem ersten Betreten der Welt einer Sitzung keine Karten
  (beim Anmelden traegt der Server Vorhandenes nach und meldet es in einem
  Schwung).
* Anker per `/transmog toast` oder Optionen verschiebbar; Position gespeichert.

### Sprachen

Acht Sprachen: Englisch (enUS), Deutsch (deDE), Franzoesisch (frFR), Spanisch
(esES), Russisch (ruRU), Koreanisch (koKR), Chinesisch vereinfacht (zhCN) und
traditionell (zhTW); im Auswahlmenue stehen sie mit ihren eigenen Namen. `enGB`
faellt auf enUS, `esMX` auf esES zurueck; fehlt ein Text, greift Englisch.

* Standard "Auto" = Sprache des Spielclients (`GetLocale()`); Wahl in den Optionen
  oder per `/transmog lang <code>`. Der Wechsel wirkt sofort, ohne `/reload`.
* Namen von Slots, Qualitaeten, Gegenstaenden und Typen kommen vom Spielclient
  und folgen dessen Sprache, nicht der des Addons.
* Eine Sprache, deren Schrift der Client nicht darstellen kann (Kyrillisch/CJK auf
  einem westlichen Client), steht im Menue mit Code dahinter, und die Optionen
  zeigen einen gelben Schrifthinweis.

### Fenster

* Standardgroesse 880 x 600, Minimum 740 x 520, Maximum: Bildschirm.
  Groesse per **Griff unten rechts**, Position per Ziehen an der Kopfzeile; beides
  wird gespeichert und an den Bildschirm geklemmt.
* **Skalierung** "Auto" (82 % des Bildschirms, begrenzt auf 0,7 bis 1,5) oder
  fest 60 bis 150 % in 5er-Schritten. Aendert sich Aufloesung oder UI-Skala,
  passt sich das Fenster nach hoechstens einer Sekunde an.
* Das Fenster entsteht erst beim ersten Oeffnen.

### Transmoggen ueberall (seit 2.1) und Vorschau-Modus

Ab Version 2.1 geht alles **ueberall**, ohne mit dem NPC zu reden: `/transmog` (oder
die Taste) oeffnet das Fenster, **Anwenden** und **Alle entfernen** sind frei. Es
gelten nur noch die ueblichen Gruende, die den Knopf sperren: nichts vorgemerkt,
Kosten werden berechnet, zu wenig Geld, ein Stapel laeuft, das Servermodul
antwortet nicht. Das Fenster zeigt keine Hinweisleiste. Spricht man den NPC an,
oeffnet das Fenster wie bisher (und schliesst beim Weglaufen); ein per `/transmog`
geoeffnetes Fenster bleibt dagegen offen.

Warum das geht: der Server prueft den Abstand zum Transmogrifizierer **nicht**.
Die Befehlsbehandler des Moduls (`HandleApply`, `HandleRemove`, `HandleRemoveAll`,
`HandleCalculateCost`, `HandleGetAvailableTransmogs` in `TransmogAddonProtocol.cpp`)
und `Transmog::ApplyAppearance` enthalten weder eine Entfernungs- noch eine
NPC-Pruefung; der NPC schickt nur `Open` und zeigt das Gossip-Menue. Die Sperre
war immer nur im Addon.

Der **Vorschau-Modus** gibt es nur noch, wenn die Option "Anwenden auch ohne
Transmogrifizierer" **ausgeschaltet** ist (Optionsfenster): dann oeffnet
`/transmog` das Fenster mit einer gelben Hinweisleiste "Vorschau-Modus ...". Alles
ausser **Anwenden** und **Alle entfernen** geht: Aussehen durchsehen, an der Figur
probieren, Kosten sehen, Outfits verwalten. Spricht man danach den NPC an, wird das
Fenster zum Transmogrifizierer-Fenster. Das Ein- und Ausschalten wirkt sofort auch
bei offenem Fenster.

Bestehende Installationen: Dateien aus 2.0 trugen den frueheren Standard "aus". Beim
ersten Start mit 2.1 wird die Option deshalb **einmalig** eingeschaltet (Marke
`noNpcDefault` in `TransmogGlobalDB`, siehe 4); danach gilt die eigene Wahl, auch
"aus", und bleibt ueber das Abmelden hinweg erhalten. Wer sie in 2.0 bewusst
ausgeschaltet hatte, muss sie nach dem Update noch einmal ausschalten (2.0 konnte
Standard und Wahl nicht unterscheiden).

**Im Spiel bestaetigt:** der Autor hat Version 2.1 im echten Spiel benutzt
und bestaetigt, dass das Anwenden ohne NPC mit dem laufenden Server funktioniert (die
Annahme "der Server prueft keinen Abstand" ist damit belegt). Hat ein angepasster Server
doch eine Entfernungspruefung, lehnt er die Befehle ab; dann die Option ausschalten.

## 3. Bedienung

### Fenster oeffnen und schliessen

| Weg | Ergebnis |
|---|---|
| **Transmogrifizierer ansprechen** | der Server sendet `Open` und kurz danach `GOSSIP_SHOW` (innerhalb von 3 s): das Addon versteckt das Gossip-Fenster und oeffnet sein Fenster im Anwendemodus. Nach 0,15 s prueft es noch einmal und beendet das Gespraech dann selbst (`CloseGossip()`), falls ein Gossip-Ersatz-Addon (Immersion, Storyline ...) das Blizzard-Fenster abgekoppelt hat: dessen Sprechbox und Tastenbelegung bauen sich ueber `GOSSIP_CLOSED` selbst ab und das fremde Fenster kann etwa 0,15 s sichtbar bleiben. Gelingt der Aufbau nicht, bleibt das normale Gossip-Fenster |
| `/transmog`, `/xmog` oder Taste | Fenster umschalten, ohne NPC (seit 2.1 mit Anwenden; bei ausgeschalteter Option "Anwenden auch ohne Transmogrifizierer" als Vorschau-Modus) |
| Knopf `*` in der Kopfzeile | Optionsfenster umschalten |
| Knopf `x`, ESC, Befehl/Taste noch einmal | schliessen; ein offenes Menue oder ein Dialog faengt ESC zuerst ab |

Am NPC beendet das Schliessen auch das Gespraech; endet das Gespraech (das Spiel
meldet `GOSSIP_CLOSED`, mindestens 1 s nach dem Oeffnen), schliesst das Fenster.
Ob das Spiel das Ereignis beim Weglaufen tatsaechlich feuert, ist nicht
geprueft (siehe 8).

### Befehle

| | |
|---|---|
| `/transmog`, `/xmog` | Fenster umschalten, auch ohne NPC (Vorschau-Modus nur bei ausgeschalteter Option) |
| `/transmog options`, `optionen` | Optionsfenster oeffnen |
| `/transmog reset` | Fensterposition und -groesse zuruecksetzen (Skalierung bleibt) |
| `/transmog toast` | Anker der Benachrichtigungen zeigen (ziehen; Rechtsklick = Standardposition; `x` schliesst) samt Probekarte |
| `/transmog lang` | aktuelle Sprache und gueltige Codes anzeigen |
| `/transmog lang <code>` | Sprache setzen: `auto`, `enUS`, `deDE`, `frFR`, `esES`, `ruRU`, `koKR`, `zhCN`, `zhTW`. Gross/Klein egal; Kurzformen `en` `de` `fr` `es` `ru` `ko`; `enGB` und `esMX` als Alias; `zh` ist mehrdeutig |
| `/transmog debug` | Diagnose ein/aus (siehe 9) |
| `/transmog help` | Befehlsliste; ein unbekannter Unterbefehl zeigt sie ebenfalls |
| `/transmogdebug`, `/transmogreset` | Kurzformen aus dem alten Addon (wie `debug`, `reset`) |

### Tastenbelegung

Spielmenue (Esc) -> **Tastaturbelegung** -> Abschnitt **Transmog**
(Transmogrifikation): "Fenster oeffnen/schliessen". Es ist keine Taste
vorbelegt. Die Taste wirkt wie `/transmog` (ohne NPC; Vorschau-Modus nur bei ausgeschalteter Option "Anwenden auch ohne Transmogrifizierer").

### Maus

| Wo | Aktion | Wirkung |
|---|---|---|
| Slot | Linksklick | Slot zum Bearbeiten waehlen |
| Slot | Rechtsklick | vorgemerkte Aenderung verwerfen, sonst das angewendete Aussehen zum Entfernen vormerken |
| Slot | Shift + Linksklick | Link des gewuenschten Aussehens in den Chat |
| Kachel | Linksklick | Aussehen waehlen; erneut auf die gewaehlte Kachel verwirft die Auswahl |
| Kachel | Rechtsklick | Favorit umschalten (nur echte Aussehen) |
| Kachel | Shift + Linksklick | Link in den Chat (nicht bei "Verborgen"; bei "Original" der angelegte Gegenstand) |
| Raster | Mausrad | Seite blaettern |
| Modell | Linksziehen | drehen |
| Modell | Rechtsziehen | verschieben |
| Modell | Mausrad | zoomen |
| `<` `>` unter dem Modell | halten | drehen |
| Qualitaets-Chip | Klick | Qualitaet ausblenden/einblenden |
| Kopfzeile | ziehen | Fenster verschieben |
| Griff unten rechts | ziehen | Groesse aendern |

"Shift + Linksklick" ist die Taste fuer Chat-Links des Spiels (Standard Shift).

### Ablauf

1. Slot waehlen (oder Rechtsklick fuer "Entfernen vormerken").
2. Kachel waehlen: Vorschau und Kosten folgen sofort, der Slot wird gelb markiert.
   Mehrere Slots lassen sich nacheinander vormerken.
3. **Anwenden** (der Tooltip listet die Aenderungen je Slot). Sind alle
   Aenderungen Entfernungen, heisst der Knopf "Original anwenden".
   **Verwerfen** nimmt alle Vormerkungen zurueck; **Alle entfernen** (mit
   Rueckfrage) entfernt jedes angewendete Aussehen.

Das Addon sendet die Aenderungen **eine nach der anderen** (der naechste Befehl
erst nach der Antwort, nach 5 s ohne Antwort gilt sie als fehlgeschlagen). Die
Statuszeile zeigt den Fortschritt und das Ergebnis; ein Fehlschlag nennt den
Slot, die Auswahl bleibt erhalten. Nach Erfolg spielt ein Standardton des Clients
(Muenzgeraeusch, `PlaySound("LOOTWINDOWCOINSOUND")`; das Addon bringt keine eigenen
Mediendateien mit; abschaltbar). Wechselt der angelegte
Gegenstand eines Slots, verfaellt dessen Auswahl.

## 4. Einstellungen

Optionsfenster: Knopf `*` in der Kopfzeile oder `/transmog options`. Aenderungen
wirken sofort.

| Einstellung | Standard | Wirkung |
|---|---|---|
| Sprache | Auto | Sprache aller Addon-Texte (Auto oder eine der acht) |
| Fensterskalierung | Auto | Regler: Auto, 60 bis 150 % |
| Vorschaugroesse | Mittel | Kachelgroesse im Raster: Klein, Mittel, Gross, Sehr gross |
| Fensterposition und -groesse zuruecksetzen | | Knopf; Skalierung bleibt |
| Sound beim Anwenden | an | Ton nach erfolgreichem Anwenden |
| Benachrichtigungen fuer neue Aussehen | an | Karten bei neu gesammelten Aussehen |
| Tooltip: "Aussehen nicht gesammelt" | an | rosa Zeile in Item-Tooltips |
| Tooltip: "Transmogrifiziert zu" | an | Zeile im Tooltip angelegter Gegenstaende |
| Anwenden auch ohne Transmogrifizierer | **an** (seit 2.1; bis 2.0 aus) | an: Anwenden und Alle entfernen gehen ueberall (der Server prueft die Naehe nicht). Aus: `/transmog` zeigt nur den Vorschau-Modus, angewendet wird nur am Transmogrifizierer |
| Benachrichtigung verschieben, Testbenachrichtigung | | Knoepfe |

### Gespeicherte Daten

| Variable | Gilt | Inhalt |
|---|---|---|
| `TransmogGlobalDB` | kontoweit | `version`, `locale`, `scale` (0 = Auto, sonst 0,6 bis 1,5), `width`, `height`, `point`, `previewSize`, `sound`, `toasts`, `toastPoint`, `tooltipCollected`, `tooltipApplied`, `allowAnywhere`, `noNpcDefault` (Marke der einmaligen Umstellung auf 2.1, immer `true`), `lastTab` |
| `TransmogDB` | je Charakter | `version`, `outfits` (Name, Slots, Zeit), `favorites`, `filter` (`qualities`, `typesOff`, `hideDuplicates`, `sort`, `favoritesOnly`, `newOnly`), `lastSlot`, `migrated` |
| `transmogOutfits`, `transmogSettings` | je Charakter | nur die **Altdaten** der Version 1.x; werden gelesen, nie veraendert und stehen nur in der TOC, damit das Spiel sie beim Abmelden nicht verwirft |

Beim Laden werden fehlende Werte mit Standards ergaenzt und ungueltige Werte auf
gueltige Bereiche gebracht; vorhandene Werte werden nie ueberschrieben. Die Dateien
liegen unter `WTF/Account/<Konto>/SavedVariables/Transmog.lua` und
`WTF/Account/<Konto>/<Realm>/<Charakter>/SavedVariables/Transmog.lua`.

### Umstellung "Anwenden ueberall" (einmalig, seit 2.1)

Vor allem anderen setzt das Laden (`DB.Init`) `allowAnywhere` auf `true` und dann die
Marke `noNpcDefault = true`, **solange die Marke fehlt**: eine Datei aus 2.0 hat sie
nicht und trug den frueheren Standard `false`. Danach wirkt die Umstellung nie wieder;
schaltet der Spieler die Option aus, bleibt sie aus (auch nach `/reload` und
Neuanmeldung). Eine Datei mit Marke und `false` wird nicht angefasst; ein
unbrauchbarer Wert (Text, Zahl, Tabelle) wird zur Vorgabe `true` repariert, eine
unbrauchbare Marke gilt als nicht gesetzt. Neue Installationen starten mit
`allowAnywhere = true`. Die Umstellung ist unabhaengig von der Altdaten-Uebernahme
unten und aendert `DB_VERSION` nicht.

### Migration der Altdaten (einmalig)

Beim ersten Anmelden **jedes Charakters** mit `TransmogDB.migrated < 2`:

* `transmogOutfits` (Name -> Client-Slot -> Gegenstand) wird zu Outfits mit
  Server-Slots; Eintraege `0` entfallen, "Verborgen" bleibt. Hoechstens 50, Namen
  auf 32 Zeichen gekuerzt, doppelte Namen erhalten " (2)", " (3)" ...
* `transmogSettings.hideDuplicates` wird uebernommen; Ruestungsstufen
  (`armorTypes`: Stoff, Leder, Kette, Platte), die im alten Addon aus waren,
  werden als ausgeblendete Typen uebernommen (fehlte ein Schluessel, galt nur
  Kette als an).
* Danach `migrated = 2`; die Altvariablen bleiben unberuehrt, ein Rueckweg zum
  alten Addon verliert nichts. Bei uebernommenen Outfits erscheint rund 4 s nach
  dem Anmelden eine Zeile mit der Anzahl.

## 5. Wie Aussehen freigeschaltet werden

Alles Folgende entscheidet der **Server** (Quellen siehe 6); das Addon zeigt nur,
was er liefert.

* **Kontoweit**: Der Server fuehrt je Account eine Sammlung (Tabelle
  `mod_transmog_plus_appearances`). Was ein Charakter freischaltet, steht allen
  Charakteren des Kontos zur Verfuegung.
* **Wann gesammelt wird** (laut `TransmogPlayerScript.cpp`): sobald ein
  Ruestungs- oder Waffen-Gegenstand ins Inventar kommt (Beute, Questbelohnung,
  Kauf, Herstellung), beim Anlegen, ueber Post/Handel/GM-Befehl (Abgleich alle
  3 s) und beim Anmelden fuer alles Vorhandene (Ausruestung, Taschen, Bank).
  Die Ruestungsfertigkeit spielt beim Sammeln keine Rolle. Nie gesammelt: Hals,
  Ringe, Schmuck, Relikte, Munition, Koecher, Beutel.
* **Was ein Slot anbietet**: nur gesammelte Aussehen, die nach den Serverregeln
  zum **aktuell angelegten Gegenstand** passen (Ruestungsstufe, Waffenart und
  Haendigkeit, Qualitaetsschalter, Klasse, Rasse, Fraktion, Fertigkeiten,
  Feiertage, `Transmog.Allowed` / `NotAllowed` ..., siehe
  `conf/mod_transmog_plus.conf.dist`). Der angelegte Gegenstand selbst und
  Gegenstaende mit identischem Aussehen (gleiche DisplayInfo) fehlen in der
  Liste. Wechselt der angelegte Gegenstand, entsteht eine neue Liste.

### Warum Listen leer sein koennen

| Meldung oder Beobachtung | Ursache |
|---|---|
| "Auf diesem Platz ist nichts angelegt" | Slot leer: erst einen Gegenstand anlegen |
| "Dieser Gegenstand kann nicht transmogrifiziert werden" | der Gegenstand ist nie transmogbar (siehe 2) |
| "Noch keine passenden Aussehen" | noch nichts gesammelt, das zu diesem Gegenstand passt (Serverregeln, zum Beispiel keine gemischten Ruestungsstufen) |
| "Keine Aussehen entsprechen deinen Filtern" | Filter oder Suche blenden alles aus: Knopf "Filter zuruecksetzen" |
| "Aussehen werden geladen... x / y" | die Liste kommt noch oder Gegenstandsdaten werden beim Server abgefragt |
| "Das Transmog-Servermodul antwortet nicht" | Modul fehlt, ist aus oder noch nicht geladen (siehe 9) |

## 6. Protokoll

Transport: **Client -> Server** `SendAddonMessage("transmog", Befehl[:Argument],
"WHISPER", eigener Name)`; **Server -> Client** ein Fluesterpaket mit `LANG_ADDON`,
das als `CHAT_MSG_ADDON` mit Praefix `transmog` ankommt. Felder durch `:` getrennt,
Slots **0-basiert** (Server-Slot; Client-Inventar-ID = Slot + 1). Quellen im
Modul `mod-transmog-plus/src/`.

| Client sendet | Server antwortet | Server-Quelle |
|---|---|---|
| `GetTransmogStatus` | `TransmogStatus:<n>[:<slot>,<fakeEntry>]*` (nur Slots mit Aussehen; `n = 0` = keins; `999999` = verborgen) | `TransmogAddonProtocol.cpp` (`SendStatus`) |
| `GetAvailableTransmogs` | je Slot (alle 14) ein Strom `AvailableTransmogs:<slot>:<bucket>:<amount>:start`, dann Stuecke `...:<id>[:<id>]*` (bis 20 IDs), dann `...:end`; `bucket` = Klasse + Unterklasse des angelegten Gegenstands | `TransmogAddonProtocol.cpp` (`SendAvailableForSlot`), Listenregeln `Transmog.cpp`, `TransmogRules.cpp`, `TransmogRuleMatching.cpp` |
| `GetCollectionStatus:<id>` | `CollectionStatus:<id>:<0 oder 1 oder 2>` (0 nicht gesammelt, 1 gesammelt, 2 nicht anwendbar) | `TransmogAddonProtocol.cpp` (`HandleGetCollectionStatus`) |
| `Apply:<slot>:<id>` | `ApplyTransmogResult:0` (Fehlschlag, **ohne** Slot) oder `ApplyTransmogResult:1:<slot>,<id>`; auch "schon angewendet" meldet Erfolg | `TransmogAddonProtocol.cpp` (`HandleApply`), `Transmog.cpp` (`ApplyAppearance`) |
| `Remove:<slot>` | `ApplyTransmogResult:1:<slot>,0` (bei ungueltigem Slot `ApplyTransmogResult:0`) | `TransmogAddonProtocol.cpp` (`HandleRemove`) |
| `RemoveAll` | `TransmogStatus:...` (neuer Gesamtstatus, **kein** `ApplyTransmogResult`) | `TransmogAddonProtocol.cpp` (`HandleRemoveAll`) |
| `CalculateCost:<slot>:<id>[,<slot>:<id>]*` | `TransmogCost:<kupfer>:<0 oder 1>` (1 = bezahlbar) | `TransmogAddonProtocol.cpp` (`HandleCalculateCost`), `Transmog.cpp` (`GetAppearanceCost`) |
| (ungefragt) `Open` | kommt unmittelbar vor dem Gossip-Fenster des NPCs | `TransmogGossip.cpp` (`OnGossipHello`) |
| (ungefragt) `CollectionUpdated:<id>` | ein Aussehen wurde neu gesammelt | `TransmogPlayerScript.cpp` |

Folgen fuer das Addon:

* Fehlantworten tragen keinen Slot, darum sendet das Addon beim Anwenden immer nur
  **einen** Befehl und ordnet die Antworten der Reihe nach zu.
* Kosten werden nur gefragt, wenn mindestens ein kostenpflichtiges Aussehen
  vorgemerkt ist; nur die Antwort der **letzten** Anfrage zaehlt.
* Nach jedem Anwenden fragt das Addon den Status erneut ab (Abgleich).
* `Net.state`: `UNKNOWN`, `OK` (eine gueltige **Antwort** auf eine Anfrage kam an:
  `TransmogStatus`, `AvailableTransmogs`, `CollectionStatus`, `TransmogCost`,
  `ApplyTransmogResult`) und `ABSENT` (8 s nach der ersten Anfrage keine Antwort;
  jede spaetere gueltige Antwort stellt `OK` wieder her). Unbekannte oder
  verstuemmelte Nachrichten werden verworfen und aendern den Zustand nicht (auch
  nicht das Echo eigener Befehle auf einem Server ohne Modul).
* Die ungefragten Nachrichten `Open` und `CollectionUpdated` werden ausgeliefert,
  zaehlen aber **nicht** als Lebenszeichen: bei `Transmog.Enable = 0` antwortet
  der Server auf nichts, schickt `Open` (NPC) und `CollectionUpdated` (Beute)
  aber weiter. Das Fenster oeffnet dann am NPC, zeigt die rote Leiste "Server
  antwortet nicht" und sperrt Anwenden.
* Nachrichten aus Gruppenkanaelen (`GUILD`, `PARTY`, `RAID` ...) werden immer
  verworfen. Optional laesst sich die Absenderpruefung einschalten
  (`/run Transmog.Net.checkSender = true`): dann gelten nur Nachrichten, deren
  Absender der eigene Charakter ist (ein fehlender Absender oder ein
  "Name-Realm" des eigenen Namens gilt als eigener). Standard ist AUS, weil die
  Absenderangabe des Clients ohne Spielclient nicht geprueft werden konnte und
  ein anderer Spieler per `SendAddonMessage("transmog", ...)` ohnehin nur
  Anzeigen (Fenster, Listen, Kosten) vortaeuschen kann: der Server prueft jede
  Aenderung selbst.
* Der Sitzungs-Cache der Sammlungsabfragen haelt "gesammelt" (1) und "nicht
  anwendbar" (2) bis zum Ende der Sitzung, ein "nicht gesammelt" (0) nur 45 s;
  eine unbeantwortete Abfrage wird nach 30 s wiederholt.
* Eine Nachricht ist hoechstens 255 Zeichen lang (Praefix inklusive).

## 7. Aufbau und Tests

### Module

| Datei | Inhalt |
|---|---|
| `Transmog.toc`, `Bindings.xml` | Ladereihenfolge, gespeicherte Variablen; Tastenbelegung `TRANSMOG_TOGGLE` |
| `Transmog.xml` | nur die zwei virtuellen Modell-Vorlagen (Vorschau 221 x 362, Kachel 80 x 107) |
| `docs/` | diese Beschreibung (Deutsch), die englische Beschreibung, die Pruefliste fuer den Spieltest |
| `LICENSE`, `NOTICE` | AGPL-3.0, Urheberangabe und Herkunft (siehe 11) |
| `Locales/Locale.lua` | Sprach-Framework: `Add`, `Set`, `Current`, `List`, Rueckfallkette |
| `Locales/enUS_*.lua` | englische Texte (12 Dateien, 254 Schluessel; **Quelle der Wahrheit**) |
| `Locales/deDE.lua` bis `zhTW.lua` | je Sprache alle 254 Schluessel (deDE frFR esES ruRU koKR zhCN zhTW) |
| `Core/Init.lua` | Version, Konstanten, Farben, Spielerinfo (Rasse, Klasse, Fraktion), Erkennung des Anmelde-Abgleichs (erste 10 s) |
| `Core/Util.lua` | Chat, Text, Zahlen und Geld, gemeinsamer Timer |
| `Core/Events.lua` | interner Ereignisbus und WoW-Ereignisse ueber einen Frame |
| `Core/DB.lua` | gespeicherte Variablen, Vorgaben, Pruefung, Migration der Altdaten |
| `Core/Slots.lua` | die 14 Slots, Anordnung, Namen, verbergbare Slots |
| `Core/Items.lua` | Gegenstandsdaten (gedrosselte Abfrage, Cache), Typen unabhaengig von der Sprache |
| `Core/Net.lua` | Protokoll: Senden, Parser, Verbindungszustand, Sammlungs-Cache |
| `Core/State.lua` | das Modell: angelegt, angewendet, gewaehlt, Listen, Kosten, Anwenden |
| `Core/Filter.lua` | Suche, Filter, Sortierung, Duplikate, Seiten (reine Logik) |
| `Core/Outfits.lua` | Outfits speichern, laden, ueberschreiben, umbenennen, loeschen |
| `Core/Boot.lua` | Start, Slash-Befehle, Gossip-Ablauf, Namen der Tastenbelegung |
| `UI/Skin.lua` | flacher Baukasten: Rahmen, Knoepfe, Menues, Dialoge, Tooltips |
| `UI/Cameras.lua` | Kamera je Rasse und Slot fuer die Kachelmodelle (Kalibrierwerte aus dem alten Addon uebernommen, siehe 11) |
| `UI/Preview.lua` | grosse Vorschau: Ankleiden, Drehen, Zoomen |
| `UI/SlotBar.lua` | die 14 Slotknoepfe mit Zustand und Tooltip |
| `UI/Grid.lua` | Raster, Kacheln, Blaetterleiste, Meldungen |
| `UI/FilterBar.lua` | Suchfeld, Sortierung, Filtermenue, Qualitaets-Chips |
| `UI/OutfitsTab.lua` | Reiter Outfits |
| `UI/Options.lua` | Optionsfenster |
| `UI/Window.lua` | Hauptfenster: Kopf, Reiter, Layout, Fuss, Groesse, Skalierung, Oeffnen |
| `Features/Tooltips.lua` | rosa/rote Zusatzzeilen in Item-Tooltips |
| `Features/Toasts.lua` | Benachrichtigungskarten und Anker |
| `tests/` | Pruefwerkzeuge und Tests (siehe unten); Kommentare und Testnamen verweisen teils auf "SPEC": die interne Bauvorgabe der Neufassung, sie gehoert nicht zum Repository |

Das Addon legt nur wenige Globals an: `Transmog`, `TransmogDB`,
`TransmogGlobalDB`, die Altvariablen, benannte Frames (`TransmogWindow`,
`TransmogOptionsFrame`, `TransmogToastAnchor`, `TransmogMenuFrame` ...),
`SLASH_TRANSMOG*` und die Tastenbelegungsnamen.

### Pruefen ohne Spiel

```
bash tests/check.sh                  # Syntax, Globals, Locale, Stil, API, Tests
bash tests/check.sh --strict         # Endabnahme: fehlende Sprachdateien/Module sind Fehler
bash tests/check.sh --partial        # Arbeitsstand: fehlende TOC-Dateien nur Warnungen
bash tests/check.sh --strict --smoke # zusaetzlich die Rauchtests tests/_*_smoke.lua
bash tests/check.sh --selftest       # zusaetzlich die Linter gegen eingebaute Fixtures
luajit tests/run.lua [filter] [-v]   # nur die Testdateien tests/test_*.lua
luajit tests/render_ui.lua [Szenario ...] [--lang CODE] [--out DIR] [--list]
```

Benoetigt `luajit` (Lua-5.1-kompatibel wie WoW, z. B. `brew install luajit`) und fuer
die XML-Pruefung `xmllint` oder `python3`; sonst nichts, alles liegt im Repository.
`check.sh` laeuft mit der bash 3.2 von macOS. Schritte:
`syntax` (alle Lua-Dateien uebersetzen), `globals` (unbekannte oder
versehentliche Globals), `locale` (Schluessel, Platzhalter, Kodierung), `style`
(Lua-5.1-Regeln, API, die es in 3.3.5a nicht gibt, Dateihygiene, TOC), `api`
(Schnittstellen der Module), `tests` (`tests/run.lua`, laedt das Addon in die
Attrappe `tests/mock_wow.lua`) und mit `--smoke` die Rauchtests.

Zuletzt gelaufen am 24.10.2026 (Momentaufnahme, die Zahlen aendern sich mit
jedem neuen Test): `bash tests/check.sh --strict --smoke --selftest` -> alle
Schritte bestanden, 1376 Tests (0 fehlgeschlagen, 265539 Pruefungen), 6
Rauchtests, 19 Fixture-Pruefungen der Linter. Gegenueber 2.0 (1302 Tests am
12.10.2026) kamen die Tests zu "Transmoggen ueberall" dazu (Standard, einmalige
Umstellung, Wahl des Spielers bleibt, Fenster ohne Hinweisleiste, Anwenden und
Alle entfernen ohne NPC, Texte in allen acht Sprachen); bei Rueckbau der
Aenderung schlagen sie fehl. `tests/test_anywhere_adversarial.lua` sind 14
Gegenproben dazu: eine typische Datei aus 2.0, eine Wahrheitstabelle ueber
alle Marken und Werte, Zufallsfolgen aus Init/Set/Abmelden/Anmelden, zweiter
Charakter, Zusammenspiel mit der Altdaten-Uebernahme, NPC-Ablauf und Weglaufen,
Absage des Servers, Umschalten mitten im Anwenden, Hinweisleiste gegen
`CanApply`/`CanRemoveAll` in allen 16 Zustaenden, Tooltip in allen Sprachen.
Mit 28 kuenstlichen Fehlern in `DB.lua`, `State.lua`, `Window.lua`, `Boot.lua`
und den Versionsangaben ueberprueft: 27 schlagen fehl, einer ist gleichwertig
(die Umstellung vor oder nach `SanitizeGlobal` ergibt dasselbe).

**`tests/render_ui.lua`** rendert das Fenster **ohne Spielclient** als SVG nach
`tests/out/<szenario>.svg` und eine Uebersichtsseite `tests/out/index.html` (im
Browser oeffnen; Symbole sind farbige Platzhalter; das Verzeichnis `tests/out/` ist
erzeugte Ausgabe und steht in `.gitignore`). Szenarien (`--list`):
`default`, `min`, `large`, `scale15`, `german`, `outfits-tab`, `options`,
`menu-type`, `loading`, `empty-slot`, `preview-mode`, `server-absent`, `toast`,
`skin-demo`. Mit `--lang all` entstehen alle acht Sprachen nacheinander. Die
Darstellung startet wie die Tests im Zustand "Option Anwenden auch ohne
Transmogrifizierer aus": nur so zeigt `preview-mode` (Fenster ohne NPC, wie
`server-absent`) den Vorschau-Modus, den es seit 2.1 nur noch mit ausgeschalteter
Option gibt. Alle anderen Szenarien oeffnen das Fenster am NPC.

Die Tests starten ohne eigene `TransmogGlobalDB` mit
`{ noNpcDefault = true, allowAnywhere = false }` (`H.boot`, `Fixtures.Boot`): so
behalten die vielen Tests des Vorschau-Modus, der weiter getestet wird, ihre
Bedeutung. Tests der neuen Vorgabe starten mit `noSeed = true` (Neuinstallation)
oder liefern eine eigene `TransmogGlobalDB`.

**Was das nicht prueft:** wie es im echten Client aussieht und sich anfuehlt
(Modelle, Kameras, Schrift, Ton), und ob die echte API sich so verhaelt wie die
Attrappe. Die Attrappe kennt nur Funktionen, die es in 3.3.5a gibt, ersetzt aber
keinen Test im Spiel. Dafuer ist die Liste unter 8.

## 8. Pruefliste fuer den ersten Spieltest

Alles, was ohne Spielclient nicht verifiziert werden konnte, steht mit Tun und
Erwartung in [CHECKLIST.de.md](CHECKLIST.de.md). Stand: ausdruecklich bestaetigt ist im
echten Spiel nur "Transmoggen ohne NPC" (siehe 2); die uebrigen Punkte wurden nur
teilweise und nicht systematisch geprueft und sind nicht einzeln abgehakt.

## 9. Bekannte Grenzen und Fehlersuche

### Bekannte Grenzen

* **Kaum Spieltest**: das Addon entstand ohne Spielclient und wurde gegen die Attrappe
  geprueft (siehe 7). Ausdruecklich bestaetigt ist im echten Spiel "Transmoggen ueberall"
  (2.1, siehe 2); die Pruefliste unter 8 ist sonst nur teilweise abgearbeitet, es gab
  keinen systematischen Test im Spiel.
* **Kosten ohne Anfragekennung**: Das Protokoll ordnet `TransmogCost`-Antworten
  nur der Reihe nach zu. Geht eine verloren (Neustart, Paketverlust), zeigt die
  Fusszeile `...`, bis nach 5 s die Anfrage einmal wiederholt und nach weiteren
  5 s aufgegeben wird; dann steht dort `?`, und **Anwenden** ist wieder frei. Im
  Normalbetrieb antwortet der Server immer.
* **Doppelte ausblenden** ist eine Naeherung (siehe 2).
* **Typfilter**: die Typen kommen aus den Auktionshaus-Listen des Clients. Sind
  die Listen nicht lesbar, greifen Rueckfalltabellen; geprueft sind nur enUS und
  deDE (esES stammt aus dem alten Addon, frFR und ruRU aus der Erinnerung, koKR und
  zh haben keine). Ein Gegenstand ohne erkannten Typ erscheint, laesst sich aber
  nicht nach Typ ausblenden.
* **"NEU"** gilt nur fuer die laufende Sitzung (wird nicht gespeichert).
* **Favoriten und Outfits** sind je Charakter, nicht kontoweit.
* **Vorschau**: Einhandwaffen in der Nebenhand erscheinen nur in der Haupthand
  (solange die Nebenhand bearbeitet wird); ein
  Fernkampfgegenstand wird nur angezogen, solange der Fernkampf-Slot bearbeitet wird
  (er wuerde sonst die Nahkampfwaffe verdecken).
* **Server** (laut README des Moduls): das Symbol eines verborgenen Slots wird im
  Charakterfenster unsichtbar (statt eines Sondersymbols); wird ein Gegenstand
  eines Ausruestungssets transmogrifiziert, zeigt das Charakterfenster eine
  falsche Set-Zahl (z. B. 5/6 statt 6/6), die Set-Boni wirken trotzdem.
* **Gegenstaende laden beim ersten Mal langsam**: 3.3.5a hat kein
  `GET_ITEM_INFO_RECEIVED`. Das Addon fragt unbekannte Gegenstaende ueber einen
  versteckten Tooltip ab (alle 0,1 s hoechstens 25), prueft per `GetItemInfo` und
  gibt nach 20 s auf (ein neuer Versuch nach 60 s). Grosse Listen laden daher beim
  ersten Oeffnen mit Fortschrittsbalken; spaeter liegen sie im Cache des Clients.

### Fehlersuche

| Beobachtung | Ursache / Abhilfe |
|---|---|
| rote Leiste "Das Transmog-Servermodul antwortet nicht", Raster leer | Modul fehlt oder ist aus (`Transmog.Enable = 0`, Serverlog pruefen), oder noch nicht geladen; kommt spaeter doch eine Antwort, normalisiert sich alles von selbst |
| rote Leiste trotz laufendem Servermodul (der Server beantwortet die Befehle nachweislich) | nur wenn die optionale Absenderpruefung eingeschaltet wurde: der Client liefert den Absender der Antworten nicht als eigenen Namen und sie werden verworfen. Mit `/transmog debug` erscheint dann je Antwort "Net: fremder Absender ignoriert". Abhilfe: `/run Transmog.Net.checkSender = false` (wirkt sofort, gilt bis zum naechsten Anmelden) |
| Anwenden grau | Tooltip des Knopfs nennt den Grund: nichts geaendert, kein Transmogrifizierer (nur bei ausgeschalteter Option "Anwenden auch ohne Transmogrifizierer"), laeuft gerade, Kosten werden berechnet, zu wenig Geld, Server stumm |
| Liste leer oder zu klein | siehe 5 ("Warum Listen leer sein koennen") |
| Raster zeigt lange "Aussehen werden geladen" | Gegenstandsdaten kommen vom Server (siehe oben); `/transmog debug` zeigt offene und fehlgeschlagene Abfragen |
| Texte erscheinen als Schluessel (`GRID_NO_SLOT` ...) | fehlende Uebersetzung oder gemischte Installation; `/transmog debug` nennt die Zahl fehlender Texte; Ordner vollstaendig ersetzen |
| Quadrate statt Schrift (ruRU, koKR, zh) | die Clientschrift hat die Zeichen nicht: Sprache auf "Auto" oder die Sprache des Clients stellen |
| Chatzeile "Das Modul <Name> konnte nicht gestartet werden" beim Anmelden | ein Modul fiel beim Start aus, die uebrigen laufen; die genaue Meldung steht im Fehlerbericht des Spiels (Lua-Fehler) |
| Fenster nach Aufloesungswechsel ausserhalb | `/transmog reset` |

**`/transmog debug`** schaltet die Diagnose um. Beim Einschalten erscheinen:
Version, Sprache, Serverzustand (`UNKNOWN`, `OK`, `ABSENT`) mit Zahl gesendeter
und empfangener Nachrichten; "am Transmogrifizierer ja/nein", Anzahl
vorgemerkter Aenderungen, ob alle Listen fertig sind; offene und fehlgeschlagene
Gegenstandsabfragen, Zahl der Timer und fehlender Texte; die erkannte Typtabelle
(`locale=... ah=...`, danach `Typschluessel = Name`). Solange die Diagnose an ist,
werden auch gesendete Befehle (`-> Apply:7:12345`) und weitere Diagnosezeilen
grau im Chat ausgegeben.

### Rueckweg zum alten Addon

Das Servermodul mod-transmog-plus bringt unter `addon/Transmog` das aeltere Addon
mit. Wer zurueck will: den Ordner `Transmog` aus `Interface/AddOns` entfernen und den
Ordner `addon/Transmog` des Moduls dorthin kopieren (nicht beide installieren). Die
gespeicherten Daten der alten Version (`transmogOutfits`, `transmogSettings`) hat das
neue Addon nie veraendert; die neuen Daten (`TransmogDB`, `TransmogGlobalDB`) liest das
alte Addon einfach nicht.

## 10. Versionshinweise

### 2.1

* **Transmoggen ueberall**: Die Option "Anwenden auch ohne Transmogrifizierer" ist
  standardmaessig **an** (vorher aus). `/transmog` oeffnet das Fenster ohne
  Vorschau-Modus, Anwenden und Alle entfernen gehen ohne NPC. Der Server prueft den
  Abstand nicht (gelesen in `TransmogAddonProtocol.cpp` und `Transmog.cpp` von
  mod-transmog-plus); die Sperre war nur im Addon.
* Der Vorschau-Modus (gelbe Leiste, Anwenden gesperrt) bleibt, aber nur mit
  ausgeschalteter Option; er ist weiter getestet.
* Bestehende Dateien: einmalige Umstellung auf "an" (Marke `noNpcDefault`), danach
  gilt die Wahl des Spielers (siehe 2 und 4).
* Tooltip der Option in allen acht Sprachen angepasst (nennt Vorgabe und
  Vorschau-Modus).
* Version in `Transmog.toc`, `T.VERSION` und in der Chatzeile beim Anmelden: 2.1.
* Ton nach dem Anwenden: ein Standardton des Clients (`LOOTWINDOWCOINSOUND`, ein
  Muenzgeraeusch) statt einer mitgelieferten Datei; das Addon enthaelt keine
  Mediendateien mehr. Im Spiel nicht geprueft, ob der Ton hoerbar ist.
* **Im Spiel bestaetigt** (Autor, 24.10.2026): Anwenden ohne NPC funktioniert mit dem
  laufenden Server. Alles Weitere nur durch Tests gegen die Attrappe; die Pruefpunkte
  unter 8 sind sonst nur teilweise abgearbeitet.

### 2.0

* Neufassung der Version 1.x (CMaNGOS-Port): Fenster, Raster, Filter, Outfits,
  Kostenanzeige, acht Sprachen, neues Protokoll (siehe 6). Altdaten der 1.x werden
  uebernommen (siehe 4).

## 11. Herkunft und Lizenz

* **Lizenz:** GNU Affero General Public License, Version 3 (`LICENSE`), Copyright (C)
  2026 nexartgroup (`NOTICE`).
* **Verwandtschaft:** Das Addon ersetzt das Addon, das mod-transmog-plus unter
  `addon/Transmog` mitliefert (AGPL-3.0). Dieses stammt als Portierung auf AzerothCore
  von malinmr aus `flekz-games/cmangos-transmog` (laut dessen GitHub-Seite GPL-3.0; nicht
  selbst geprueft). Version 1.x des hier gezeigten Addons war ein solcher Port; **Version
  2.0 ist von Grund auf neu geschrieben**: Aufbau, Code, Oberflaeche, Protokollbehandlung,
  Texte und Tests sind eigene Arbeit.
* **Uebernommen (Daten, kein Code):**
  1. die Kalibrierwerte der Kachelkameras in `UI/Cameras.lua` (Verschiebungen und
     Drehwinkel je Rasse und Slot), 1:1 aus `ui/appearance_list.lua` des alten Addons; im
     laufenden Spiel von Hand abgestimmt, daher nicht nachrechenbar;
  2. die spanischen Namen der Waffen- und Ruestungsunterklassen (Zeichenketten des
     Spielclients) in `Core/Items.lua`;
  3. die Protokollschnittstelle des Servermoduls (Befehls- und Antwortformate, siehe 6).
* **Nicht uebernommen:** kein Code des alten Addons, keine Mediendateien (die frueher
  mitgelieferte Tondatei stammte aus diesem Addon und ist durch einen Standardton des
  Clients ersetzt); nach dem Zeilenvergleich (siehe unten) nichts aus ElvUI oder anderen
  Addons.
* **Pruefung:** ein Zeilenvergleich (Leerraum normalisiert, Zeilen ab 25 Zeichen und
  Fenster aus 3 Zeilen) aller Dateien des Repositories gegen das Servermodul samt altem
  Addon, ElvUI-WotLK samt Erweiterungen und die uebrigen installierten Addons ergab keine
  uebernommenen Code-Abschnitte, nur gaengige Einzeiler der WoW-API
  (`GameTooltip:Show()`, `local format = string.format` ...) und Trennlinien in Kommentaren.
  Die Kalibrierwerte (1.) findet der Zeilenvergleich nicht, weil die Datenstruktur neu ist.
* **Folge fuer die Lizenz:** weil Werte und Namen aus AGPL-3.0- bzw. GPL-3.0-Quellen
  stammen, steht das Repository unter AGPL-3.0 (kompatibel mit beiden). Wer die
  Kalibrierwerte selbst neu abstimmt, koennte die Lizenz spaeter freier waehlen.
