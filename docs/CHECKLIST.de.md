# Transmog - Pruefliste fuer den Spieltest

Zurueck zur [Beschreibung](MANUAL.de.md) - [README](../README.md).

Alles, was ohne Spielclient nicht verifiziert werden konnte. Je Punkt: tun,
dann erwarten.

**Stand:** Als im echten Spiel bestaetigt gilt ausdruecklich nur die Zeile
"`/transmog` weit weg vom NPC" (der Autor hat Version 2.1 benutzt: Anwenden ohne NPC
funktioniert mit dem laufenden Server). Die uebrigen Punkte wurden nur teilweise und nicht
systematisch geprueft und sind hier nicht einzeln abgehakt; sie gelten als offen. Wer einen
Punkt prueft, kann das Ergebnis als Issue im Repository melden.

| Pruefpunkt | Erwartung |
|---|---|
| **Gossip-Ablauf am NPC**: Transmogrifizierer ansprechen | das Gossip-Fenster verschwindet sofort (hoechstens ein kurzes Aufblitzen, ein Sicherheitsnetz versteckt es nach 0,15 s erneut), das Transmog-Fenster erscheint ohne Hinweisleiste; erneutes Ansprechen bei offenem Fenster flackert nicht; Schliessen beendet das Gespraech |
| **Gossip-Ersatz-Addon** (Immersion, Storyline ...) aktiv: Transmogrifizierer ansprechen | dessen Sprechbox darf hoechstens etwa 0,15 s sichtbar sein und ist danach weg; seine Tasten (Leertaste, Rueckschritt) laufen wieder normal. Ob der 3.3.5a-Client `GOSSIP_CLOSED` bei `CloseGossip()` synchron feuert und nichts feuert, wenn das Gespraech schon zu ist, ist ungeprueft |
| NPC-Fenster offen, vom NPC weglaufen | das Fenster schliesst sich (`GOSSIP_CLOSED`); ob das Spiel das Ereignis in diesem Fall wirklich feuert, ist ungeprueft |
| **`/transmog` weit weg vom NPC (Standard seit 2.1)**: Aussehen waehlen, **Anwenden**; danach "Alle entfernen" und Rechtsklick auf einen Slot (Entfernen) | keine gelbe Leiste; Fortschritt in der Statuszeile, Slot blitzt, Ton, Geld abgezogen, Figur aktualisiert; "Alle entfernen" fragt nach und leert alles. **Im Spiel bestaetigt (Autor, 24.10.2026): Anwenden ohne NPC funktioniert, der Server verlangt keinen NPC.** Antwortet ein anderer (angepasster) Server mit Fehlschlag, Option ausschalten und den Befund melden |
| Option "Anwenden auch ohne Transmogrifizierer" **ausschalten**, `/transmog` weit weg vom NPC | gelbe Hinweisleiste "Vorschau-Modus ...", Anwenden und Alle entfernen gesperrt mit Grund; wieder einschalten: Leiste weg, Anwenden geht (auch bei offenem Fenster sofort) |
| Update von 2.0 mit gespeichertem "aus": erster Start mit 2.1 | Haken steht an (einmalig); ausschalten, `/reload` oder neu anmelden: bleibt aus |
| **Modell drehen, verschieben, zoomen**: Links-/Rechtsziehen, Mausrad, `<` `>`, "Zuruecksetzen" | ruckfrei, Figur bleibt im Bild, Zuruecksetzen stellt die Anfangsansicht her (ob Rotation und Facing der 3.3.5a-Engine **ein** Winkel sind, ist nicht gesichert) |
| Umhang waehlen, danach anderen Slot | Figur dreht nach hinten und wieder zurueck |
| Ankleiden: "Verborgen" am Kopf, danach ein Aussehen; Zweihaender; zwei Waffen; Fernkampf bearbeiten | Figur zeigt jeweils den gewaehlten Zustand, keine falsche Waffe in der Hand |
| Kachelkameras fuer mehrere Rassen und Slots (Kopf, Schulter, Ruecken, Waffen) | Modell sauber im Ausschnitt (die Zahlen sind aus Version 1.x uebernommen und per Test auf Gleichheit geprueft, nicht am Bildschirm) |
| **ESC mit Menues**: Sortier-/Filtermenue offen, Dialog "Outfit speichern" offen | ESC schliesst zuerst nur Menue bzw. Dialog, das Hauptfenster bleibt; danach schliesst ESC das Fenster (und am NPC das Gespraech) |
| **Groesse aendern**: Griff unten rechts ziehen, bis Minimum und Maximum | Raster zeigt mehr/weniger Spalten und Zeilen, nichts ragt ueber (Fusszeile, Kopf); nach dem Loslassen laden die Modelle neu; Groesse und Position bleiben nach `/reload`; `/transmog reset` stellt 880 x 600 her |
| Skalierung Auto und 60 bis 150 %; Aufloesung oder UI-Skala im Spiel aendern | Fenster bleibt komplett im Bild und passt sich nach hoechstens 1 s an |
| **Ton nach dem Anwenden**: Aussehen anwenden (Option "Sound beim Anwenden" an) | Muenzgeraeusch (Standardton `LOOTWINDOWCOINSOUND` des Clients; ersetzt die frueher mitgelieferte Tondatei, Namen und Hoerbarkeit im Spiel ungeprueft); Option aus: still |
| **Kosten**: Aussehen waehlen | `...`, dann Betrag in Gold/Silber/Kupfer; gruen mit genug Geld, rot ohne; "Original" oder "Verborgen" allein: Kostenlos; Betrag = `Transmog.PriceCopper` je Slot |
| **Anwenden**: mehrere Slots, zu wenig Geld, Server stumm | Fortschritt in der Statuszeile, Slots blitzen, Ton, Geld abgezogen, Figur aktualisiert; bei Fehlschlag rote Meldung mit Slotname und erhaltene Auswahl |
| **Entfernen**: Rechtsklick auf Slot, Kachel "Original", "Alle entfernen" | Knopf "Original anwenden"; Rueckfrage bei "Alle entfernen"; Zustand nach dem Abgleich stimmt |
| Inaktives Aussehen: Gegenstand wechseln, der das Aussehen nicht mehr traegt | Slot rot mit `!`, roter Tooltip, Slot zaehlt als "ohne Aussehen" |
| **Tooltips**: Gegenstand mit ungesammeltem Aussehen im Beutel; angelegtes Teil mit Transmog; Vergleichs-Tooltip | rosa Zeile erscheint (leicht verzoegert); "Transmogrifiziert zu: ..."; keine doppelten Zeilen |
| **Benachrichtigungen**: neues Aussehen looten; mehrere schnell hintereinander; frisch anmelden | Karte oben mittig; ab 4 in 2 s eine Sammelkarte; in den ersten 10 s nach dem Anmelden kein Kartenregen; Anker ziehen, Rechtsklick setzt zurueck, `x` schliesst |
| **Sprachwechsel** im Optionsfenster und per `/transmog lang fr` | alle Texte wechseln sofort ohne `/reload`; Kopf, Fuss und Filterleiste bei Mindestgroesse nicht abgeschnitten |
| **Schriftdarstellung ruRU, koKR, zhCN, zhTW** auf einem westlichen Client und auf einem passenden Client | westlich: Quadrate/Fragezeichen und gelber Schrifthinweis (erwartet); passender Client: lesbar, Texte passen in Knoepfe und Zeilen |
| Grosse Liste (einige hundert Aussehen), Vorschau "Klein", grosses Fenster | Ladebalken, danach fluessige Bildrate (bis zu 120 Modelle je Seite) |
| Typfilter | Typen (Stoff, Leder ...) erscheinen und filtern; sonst `/transmog debug` (siehe 9) |
| Outfit speichern, laden, ueberschreiben, umbenennen, loeschen | wie in 2 beschrieben; Laden wendet nichts an |
| Charakter mit Outfits aus Version 1.x anmelden | einmalige Zeile mit der Anzahl uebernommener Outfits; alte Outfits im Reiter |
| Absender von `CHAT_MSG_ADDON` | Standard: keine Absenderpruefung (`Net.checkSender = false`). Wer vorgetaeuschte Nachrichten fremder Spieler ausschliessen will: `/run Transmog.Net.checkSender = true`. Bleibt das Addon danach stumm ("Server antwortet nicht") obwohl das Modul laeuft, liefert der Client den Absender anders: wieder auf `false` stellen und den Befund melden |
