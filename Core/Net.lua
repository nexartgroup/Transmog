-- Core\Net.lua
-- ---------------------------------------------------------------------------
-- Netzwerkschicht: Protokoll zum AzerothCore-Modul mod-transmog-plus.
--
-- Diese Datei ist REINES Parsen und Weiterreichen. Sie haelt keinen Spiel-
-- zustand (ausser dem Sitzungs-Cache fuer Sammlungsabfragen und dem Zustand
-- der Verbindung selbst). Was ankommt, wird zerlegt und an State.On*(...)
-- uebergeben; was State wissen will, geht ueber Net.Send / Net.Request*.
--
-- Transport
--
--   Client -> Server   SendAddonMessage("transmog", "Befehl[:Argument]",
--                                       "WHISPER", UnitName("player"))
--   Server -> Client   Chat-Fluestern mit LANG_ADDON; im Client kommt es als
--                      CHAT_MSG_ADDON (prefix, message, channel, sender) mit
--                      prefix == "transmog" und message == "Nutzdaten".
--
-- Verbindungszustand (Net.state)
--
--   UNKNOWN   noch keine Anfrage gesendet, oder gesendet und noch innerhalb
--             der Wartezeit
--   OK        mindestens eine gueltige ANTWORT auf eine Anfrage des Addons ist
--             angekommen (TransmogStatus, AvailableTransmogs, CollectionStatus,
--             TransmogCost, ApplyTransmogResult)
--   ABSENT    8 s nach der ersten Anfrage ist KEINE Antwort vom Server gekommen
--             (Modul fehlt oder ist abgeschaltet); jede spaetere gueltige
--             Antwort setzt den Zustand wieder auf OK
--
-- Parser
--
--   Nachrichten werden an ":" zerlegt. Jedes Feld wird einzeln geprueft
--   (nur Ziffern); verstuemmelte Nachrichten werden verworfen, nie geworfen.
--   Unbekannte Befehle werden ignoriert und zaehlen nicht als Lebenszeichen;
--   das gilt auch fuer das Echo der eigenen Befehle, das ein Server OHNE das
--   Modul an den Spieler zurueckfluestert ("GetTransmogStatus" usw.): die
--   Befehlsnamen des Clients und der Antworten sind ueberschneidungsfrei.
--   Nur eine GUELTIGE ANTWORT (eine, die an State.On* ausgeliefert wird)
--   setzt Net.state auf "OK" -- und zwar bevor State.On* laeuft. Die beiden
--   unaufgeforderten Nachrichten "Open" und "CollectionUpdated" werden
--   ausgeliefert, zaehlen aber NICHT als Lebenszeichen: bei Transmog.Enable=0
--   beantwortet der Server nichts, schickt sie aber weiter (NPC-Gossip und
--   Loot-/Ausruestungshaken pruefen Enable nicht).
--
-- Absender
--
--   Der Server fluestert dem Spieler an sich selbst. Optional (Net.checkSender,
--   Standard AUS, siehe Net.OnAddonMessage) werden nur Nachrichten angenommen,
--   deren Absender der Spieler selbst ist; sonst koennte jeder andere Spieler
--   per SendAddonMessage("transmog", ...) ein Fenster oeffnen oder Listen und
--   Kosten vortaeuschen (nur kosmetisch: der Server prueft jede Aenderung).
--   Standard AUS, weil sich die Absenderangabe des Clients ohne echten Client
--   nicht pruefen liess und eine falsche Annahme das Addon stumm schalten
--   wuerde. Nachrichten aus Gruppenkanaelen (GUILD, PARTY, RAID ...) werden
--   unabhaengig davon verworfen.
-- ---------------------------------------------------------------------------

local T = Transmog
T.Net = T.Net or {}
local Net = T.Net

local sfind, ssub, smatch = string.find, string.sub, string.match
local slower = string.lower
local floor = math.floor
local tonumber, tostring, type, pcall = tonumber, tostring, type, pcall
local tconcat = table.concat

-- Zeitfenster und Grenzen
local ABSENT_AFTER      = 8      -- s nach der ersten Anfrage ohne jede Antwort
local COLLECTION_RETRY  = 30     -- s, bevor eine unbeantwortete Abfrage wiederholt wird
local COLLECTION_RATE   = 30     -- Sammlungsabfragen je Sekunde (Flutschutz)
local NEGATIVE_TTL      = 45     -- s, nach denen ein gecachtes "nicht gesammelt" als unbekannt gilt
local MAX_SLOT          = 18     -- EQUIPMENT_SLOT_TABARD
local MAX_UINT          = 4294967295
local MAX_MESSAGE_LEN   = 255    -- Praefix + Text, Grenze von SendAddonMessage

-- Kanaele, ueber die nie eine Servernachricht kommt (der Server fluestert nur).
local GROUP_CHANNELS = {
   GUILD = true, OFFICER = true, PARTY = true, RAID = true, BATTLEGROUND = true,
}

-- Oeffentlicher Zustand (beim Laden zurueckgesetzt, siehe Tests)
Net.checkSender    = false       -- true: nur Nachrichten des Spielers selbst annehmen (siehe IsOwnSender)
Net.state          = "UNKNOWN"
Net.sentCount      = 0           -- erfolgreich gesendete Befehle
Net.receivedCount  = 0           -- erkannte Servernachrichten
Net.firstRequestAt = nil         -- GetTime() der ersten Anfrage
Net.lastReceiveAt  = nil         -- GetTime() der letzten erkannten Nachricht

local initialized = false
local gotAnything = false        -- irgendeine erkannte ANTWORT des Servers
local absentTimer = nil
local collection  = {}           -- [itemId] = 0 | 1 | 2
local colAt       = {}           -- [itemId] = Zeit der 0-Antwort (nur fuer Stand 0)
local colPending  = {}           -- [itemId] = Sendezeit
local rateStart, rateCount = 0, 0

-- ---------------------------------------------------------------------------
-- Hilfen
-- ---------------------------------------------------------------------------

-- Ereignis auf den internen Bus legen (Events darf fehlen, z. B. im Test).
local function Fire(name, ...)
   local E = T.Events
   if E and E.Fire then E.Fire(name, ...) end
end

local function Dbg(fmt, ...)
   local U = T.Util
   if U and U.Debug then U.Debug(fmt, ...) end
end

local function Now()
   if GetTime then return GetTime() end
   return 0
end

local function After(delay, fn, ...)
   local U = T.Util
   if U and U.After then return U.After(delay, fn, ...) end
   return nil
end

local function Cancel(handle)
   local U = T.Util
   if handle and U and U.Cancel then U.Cancel(handle) end
end

local function Prefix()
   return T.PREFIX or "transmog"
end

-- Fehler eines Handlers an den Fehlerhandler des Spiels melden, nie werfen.
local function Report(err)
   Dbg("Net: %s", tostring(err))
   if geterrorhandler then
      local eh = geterrorhandler()
      if type(eh) == "function" then pcall(eh, err) end
   end
end

-- Nicht negative Ganzzahl aus Zahl oder reinem Ziffernstring, sonst nil.
local function ToUInt(v)
   local n
   if type(v) == "number" then
      n = v
   elseif type(v) == "string" then
      local digits = smatch(v, "^%s*(%d+)%s*$")
      if not digits then return nil end
      n = tonumber(digits)
   else
      return nil
   end
   if not n or n ~= n or n < 0 or n > MAX_UINT or n ~= floor(n) then return nil end
   return n
end
Net.ToUInt = ToUInt

-- Klartext-Split; bevorzugt Util.Split, mit eigenem Rueckfall.
local function Split(str, sep)
   local U = T.Util
   if U and U.Split then
      local ok, res = pcall(U.Split, str, sep)
      if ok and type(res) == "table" then return res end
   end
   local out, from = {}, 1
   while true do
      local a, b = sfind(str, sep, from, true)
      if not a then break end
      out[#out + 1] = ssub(str, from, a - 1)
      from = b + 1
   end
   out[#out + 1] = ssub(str, from)
   return out
end

-- Ruft State.<name>(...) geschuetzt; fehlende Funktion = ignorieren.
local function Call(name, ...)
   local S = T.State
   local fn = S and S[name]
   if type(fn) ~= "function" then
      Dbg("Net: State.%s fehlt", name)
      return
   end
   local ok, err = pcall(fn, ...)
   if not ok then Report(err) end
end

-- Zustand der Verbindung setzen und melden.
local function SetState(newState)
   if Net.state == newState then return end
   Net.state = newState
   Fire("SERVER_STATE", newState)
end

-- Ablauf der 8-Sekunden-Frist: nichts gehoert => ABSENT.
local function CheckAbsent()
   absentTimer = nil
   if gotAnything then return end
   if Net.state == "UNKNOWN" then SetState("ABSENT") end
end

local function ArmAbsentCheck()
   if absentTimer or gotAnything or Net.state ~= "UNKNOWN" then return end
   absentTimer = After(ABSENT_AFTER, CheckAbsent)
end

-- Zaehlt eine erkannte Servernachricht (nur Statistik und Debug-Ausgabe).
local function CountReceived()
   Net.receivedCount = Net.receivedCount + 1
   Net.lastReceiveAt = Now()
end

-- Eine erkannte ANTWORT des Servers ist angekommen.
local function MarkAlive()
   gotAnything = true
   CountReceived()
   if absentTimer then
      Cancel(absentTimer)
      absentTimer = nil
   end
   if Net.state ~= "OK" then SetState("OK") end
end

-- Liefert eine GUELTIGE Antwort aus: erst als Lebenszeichen werten
-- (Net.state ist dann schon "OK", wenn State.On* feuert), dann State.<name>(...).
-- Rueckgabe immer true (= "Nachricht war gueltig").
local function Deliver(name, ...)
   MarkAlive()
   Call(name, ...)
   return true
end

-- Liefert eine UNAUFGEFORDERTE Servernachricht aus (Open, CollectionUpdated):
-- sie geht an State.<name>(...), ist aber KEIN Lebenszeichen. Bei
-- Transmog.Enable=0 beantwortet der Server nichts, schickt diese beiden aber
-- weiter; sie duerfen ABSENT weder verhindern noch aufheben.
-- Rueckgabe immer true (= "Nachricht war gueltig").
local function DeliverUnsolicited(name, ...)
   CountReceived()
   Call(name, ...)
   return true
end

-- ---------------------------------------------------------------------------
-- Senden
-- ---------------------------------------------------------------------------

-- Sendet einen Befehl ("Apply", "7:12345" als arg). Rueckgabe: true wenn
-- abgeschickt. Faellt nie mit einem Fehler aus.
function Net.Send(command, arg)
   if type(command) ~= "string" or command == "" then return false end
   local text = command
   if arg ~= nil then text = command .. ":" .. tostring(arg) end
   local prefix = Prefix()
   if #prefix + 1 + #text > MAX_MESSAGE_LEN then
      Dbg("Net: Nachricht zu lang (%d)", #text)
      return false
   end
   local name = UnitName and UnitName("player")
   if type(name) ~= "string" or name == "" then return false end
   if not SendAddonMessage then return false end
   local ok, err = pcall(SendAddonMessage, prefix, text, "WHISPER", name)
   if not ok then
      Dbg("Net: SendAddonMessage fehlgeschlagen: %s", tostring(err))
      return false
   end
   Net.sentCount = Net.sentCount + 1
   if not Net.firstRequestAt then Net.firstRequestAt = Now() end
   ArmAbsentCheck()
   Dbg("-> %s", text)
   return true
end

-- Fragt den Gesamtstatus ab (Antwort: TransmogStatus).
function Net.RequestStatus()
   return Net.Send("GetTransmogStatus")
end

-- Fragt die Listen aller 14 Slots ab (Antwort: je Slot ein Strom).
function Net.RequestLists()
   return Net.Send("GetAvailableTransmogs")
end

-- Fragt den Preis fuer Paare {slot, id} ab (Antwort: TransmogCost).
-- Rueckgabe: true wenn gesendet; ohne gueltige Paare wird nichts gesendet.
function Net.RequestCost(list)
   if type(list) ~= "table" then return false end
   local parts = {}
   for i = 1, #list do
      local p = list[i]
      if type(p) == "table" then
         local slot, id = ToUInt(p[1]), ToUInt(p[2])
         if slot and id and id ~= 0 and slot <= MAX_SLOT then
            parts[#parts + 1] = slot .. ":" .. id
         end
      end
   end
   if #parts == 0 then return false end
   return Net.Send("CalculateCost", tconcat(parts, ","))
end

-- Aussehen anwenden (Antwort: ApplyTransmogResult).
function Net.SendApply(slot, id)
   slot, id = ToUInt(slot), ToUInt(id)
   if not slot or not id or id == 0 or slot > MAX_SLOT then return false end
   return Net.Send("Apply", slot .. ":" .. id)
end

-- Aussehen eines Slots entfernen (Antwort: ApplyTransmogResult:1:slot,0).
function Net.SendRemove(slot)
   slot = ToUInt(slot)
   if not slot or slot > MAX_SLOT then return false end
   return Net.Send("Remove", slot)
end

-- Alle Aussehen entfernen (Antwort: TransmogStatus, KEIN ApplyTransmogResult).
function Net.SendRemoveAll()
   return Net.Send("RemoveAll")
end

-- ---------------------------------------------------------------------------
-- Sammlungsabfragen (Sitzungs-Cache)
-- ---------------------------------------------------------------------------

-- Gecachter Stand: 0 nicht gesammelt, 1 gesammelt, 2 nicht anwendbar, nil unbekannt.
-- Nur "nicht gesammelt" veraltet: ein anderer Zugang desselben Kontos (Begleiter-
-- Sitzung) kann den Gegenstand sammeln, ohne dass dieser Client ein
-- CollectionUpdated bekommt. Nach NEGATIVE_TTL Sekunden gilt der Stand 0 daher
-- als unbekannt (nil), und QueryCollection fragt neu. 1 und 2 bleiben.
function Net.CollectionState(id)
   id = ToUInt(id)
   if not id then return nil end
   local v = collection[id]
   if v == 0 then
      local age = Now() - (colAt[id] or 0)
      if age >= NEGATIVE_TTL or age < 0 then return nil end
   end
   return v
end

-- Schreibt den Cache (Antworten und CollectionUpdated). Ein "gesammelt" wird
-- nie von einer spaeter eintreffenden, aelteren "nicht gesammelt"-Antwort
-- zurueckgenommen. Rueckgabe: der effektive Stand.
function Net.SetCollectionState(id, state)
   id, state = ToUInt(id), ToUInt(state)
   if not id or id == 0 or state == nil or state > 2 then return nil end
   if collection[id] == 1 and state == 0 then state = 1 end
   collection[id] = state
   colAt[id] = (state == 0) and Now() or nil
   colPending[id] = nil
   return state
end

-- Fragt den Sammlungsstand eines Gegenstands ab. Gibt den bekannten Stand
-- zurueck (dann wird nichts gesendet) oder nil. Eine laufende Abfrage wird
-- nicht doppelt gesendet; nach 30 s ohne Antwort ist ein neuer Versuch erlaubt.
-- Ein "nicht gesammelt" gilt nur NEGATIVE_TTL Sekunden (siehe CollectionState).
function Net.QueryCollection(id)
   id = ToUInt(id)
   if not id or id == 0 then return nil end
   local known = Net.CollectionState(id)
   if known ~= nil then return known end
   local now = Now()
   local sentAt = colPending[id]
   if sentAt and (now - sentAt) < COLLECTION_RETRY then return nil end
   if now - rateStart >= 1 or now < rateStart then
      rateStart, rateCount = now, 0
   end
   if rateCount >= COLLECTION_RATE then return nil end
   if Net.Send("GetCollectionStatus", id) then
      rateCount = rateCount + 1
      colPending[id] = now
   end
   return nil
end

-- ---------------------------------------------------------------------------
-- Parser: ein Handler je Befehl, Argument = Feldarray (Feld 1 = Befehl).
-- Jeder Handler gibt true zurueck, wenn die Nachricht gueltig war und an State
-- ausgeliefert wurde, sonst false (verstuemmelt: verworfen, nichts passiert).
-- ---------------------------------------------------------------------------

local handlers = {}

-- "Open": der Server oeffnet gleich das Gossip-Fenster des Transmogrifizierers.
-- Unaufgefordert (kommt auch bei Transmog.Enable=0): kein Lebenszeichen.
handlers.Open = function()
   return DeliverUnsolicited("OnOpen")
end

-- "TransmogStatus:<n>[:<slot>,<fakeEntry>]*"
handlers.TransmogStatus = function(f)
   local n = ToUInt(f[2])
   if n == nil then return false end
   local map, count = {}, 0
   for i = 3, #f do
      local entry = f[i]
      if type(entry) == "string" then
         local a, b = smatch(entry, "^%s*(%d+)%s*,%s*(%d+)%s*$")
         local slot, fake = ToUInt(a), ToUInt(b)
         if slot and fake and slot <= MAX_SLOT and fake ~= 0 then
            map[slot] = fake
            count = count + 1
         end
      end
   end
   if n > 0 and count == 0 then
      Dbg("Net: TransmogStatus verstuemmelt")
      return false
   end
   return Deliver("OnStatus", map)
end

-- "AvailableTransmogs:<slot>:<bucket>:<amount>:<start | end | id[:id]*>"
handlers.AvailableTransmogs = function(f)
   local slot = ToUInt(f[2])
   if slot == nil or slot > MAX_SLOT then return false end
   local chunk = f[5]
   if type(chunk) ~= "string" then return false end
   local word = smatch(chunk, "^%s*(.-)%s*$")
   if word == "start" then
      return Deliver("OnListStart", slot, ToUInt(f[3]) or 0, ToUInt(f[4]) or 0)
   elseif word == "end" then
      return Deliver("OnListEnd", slot)
   end
   local ids, seen = {}, {}
   for i = 5, #f do
      local id = ToUInt(f[i])
      if id and id ~= 0 and not seen[id] then
         seen[id] = true
         ids[#ids + 1] = id
      end
   end
   if #ids == 0 then return false end
   return Deliver("OnListChunk", slot, ids)
end

-- "ApplyTransmogResult:0" | "ApplyTransmogResult:1:<slot>,<itemId>"
-- Eine Erfolgsmeldung ohne lesbare Slotangabe geht ohne slot/id an State
-- (dort: aelteste ausstehende Operation).
handlers.ApplyTransmogResult = function(f)
   local flag = ToUInt(f[2])
   if flag == 0 then
      return Deliver("OnApplyResult", false, nil, nil)
   elseif flag == 1 then
      local slot, id
      if type(f[3]) == "string" then
         local a, b = smatch(f[3], "^%s*(%d+)%s*,%s*(%d+)%s*$")
         slot, id = ToUInt(a), ToUInt(b)
         if slot == nil or id == nil or slot > MAX_SLOT then slot, id = nil, nil end
      end
      return Deliver("OnApplyResult", true, slot, id)
   end
   return false
end

-- "TransmogCost:<copper>:<0|1>"
handlers.TransmogCost = function(f)
   local copper, can = ToUInt(f[2]), ToUInt(f[3])
   if copper == nil or can == nil then return false end
   return Deliver("OnCost", copper, can ~= 0)
end

-- "CollectionUpdated:<itemId>"
-- Unaufgefordert (Loot-/Ausruestungshaken, auch bei Transmog.Enable=0): kein
-- Lebenszeichen.
handlers.CollectionUpdated = function(f)
   local id = ToUInt(f[2])
   if not id or id == 0 then return false end
   Net.SetCollectionState(id, 1)
   return DeliverUnsolicited("OnCollectionUpdated", id)
end

-- "CollectionStatus:<itemId>:<0|1|2>"
handlers.CollectionStatus = function(f)
   local id, state = ToUInt(f[2]), ToUInt(f[3])
   if not id or id == 0 or state == nil or state > 2 then return false end
   local effective = Net.SetCollectionState(id, state)
   return Deliver("OnCollectionStatus", id, effective)
end

-- Parst EINE Servernachricht (ohne "transmog\t"-Praefix; ein vorhandenes wird
-- toleriert) und ruft State.On*. Wirft nie. Rueckgabe: true wenn die Nachricht
-- ein bekannter, gueltiger Befehl war und ausgeliefert wurde; unbekannte oder
-- verstuemmelte Nachrichten ergeben false und aendern nichts (auch nicht
-- Net.state).
function Net.Handle(message)
   if type(message) ~= "string" then return false end
   local lead = Prefix() .. "\t"
   if ssub(message, 1, #lead) == lead then message = ssub(message, #lead + 1) end
   if message == "" then return false end
   local fields = Split(message, ":")
   local command = fields[1]
   local fn = type(command) == "string" and handlers[command] or nil
   if not fn then
      Dbg("Net: unbekannter Befehl")
      return false
   end
   local ok, res = pcall(fn, fields)
   if not ok then
      Report(res)
      return false
   end
   return res == true
end

-- ---------------------------------------------------------------------------
-- CHAT_MSG_ADDON
-- ---------------------------------------------------------------------------

-- Ist der Absender der Spieler selbst? (Der Server fluestert dem Spieler an
-- sich selbst: BuildChatPacket(CHAT_MSG_WHISPER, LANG_ADDON, player, player).)
-- Wird nur ausgewertet, wenn Net.checkSender gesetzt ist (Standard AUS): Schutz
-- gegen vorgetaeuschte Servernachrichten fremder Spieler (jeder kann
-- SendAddonMessage("transmog", ..., "WHISPER", Ziel) senden). Mit
-- Net.checkSender = true einschaltbar, falls der Client den Absender wie
-- erwartet liefert.
-- Gross-/Kleinschreibung zaehlt nicht, ein Realm-Anhang ("Name-Realm") wird
-- abgeschnitten. Fehlt Absender oder eigener Name (noch "Unknown"), wird die
-- Nachricht NICHT verworfen.
local function IsOwnSender(sender)
   if type(sender) ~= "string" or sender == "" then return true end
   local me = UnitName and UnitName("player")
   if type(me) ~= "string" or me == "" then return true end
   if me == "Unknown" or me == _G.UNKNOWNOBJECT then return true end
   local s, m = slower(sender), slower(me)
   if s == m then return true end
   local bare = smatch(s, "^([^%-]+)%-")
   return bare ~= nil and bare == m
end

-- Verarbeitet ein CHAT_MSG_ADDON. Praefixe ausser "transmog" werden ignoriert;
-- die zusammengezogene Form "transmog\tNutzdaten" wird toleriert. Gruppenkanaele
-- (GUILD, PARTY, RAID ...) werden immer verworfen, fremde Absender nur, wenn
-- Net.checkSender gesetzt ist.
function Net.OnAddonMessage(prefix, message, channel, sender)
   local mine = Prefix()
   local lead = mine .. "\t"
   local payload = nil
   if prefix == mine then
      if type(message) == "string" then payload = message end
   elseif type(prefix) == "string" and ssub(prefix, 1, #lead) == lead then
      payload = ssub(prefix, #lead + 1)
      if payload == "" and type(message) == "string" then payload = message end
   elseif (prefix == nil or prefix == "") and type(message) == "string"
         and ssub(message, 1, #lead) == lead then
      payload = message
   end
   if payload == nil then return false end
   if type(channel) == "string" and GROUP_CHANNELS[channel] then
      Dbg("Net: Gruppenkanal ignoriert")
      return false
   end
   if Net.checkSender and not IsOwnSender(sender) then
      Dbg("Net: fremder Absender ignoriert")
      return false
   end
   return Net.Handle(payload)
end

-- Event-Handler fuer Events.Game: fn(event, prefix, message, channel, sender).
local function OnChatMsgAddon(event, prefix, message, channel, sender)
   Net.OnAddonMessage(prefix, message, channel, sender)
end

-- Registriert CHAT_MSG_ADDON. Mehrfaches Aufrufen ist harmlos.
function Net.Init()
   if initialized then return end
   initialized = true
   if RegisterAddonMessagePrefix then
      pcall(RegisterAddonMessagePrefix, Prefix())
   end
   local E = T.Events
   if E and E.Game then E.Game("CHAT_MSG_ADDON", OnChatMsgAddon) end
end
