-- enUS_Core.lua
-- ---------------------------------------------------------------------------
-- Englische Texte der Basismodule (Locale, Util, DB, Slots) und allgemeine
-- Texte. Die Module State/Filter/Net/Items/Outfits/UI haben eigene Dateien.
--
-- Regeln: Schluessel = ASCII-GROSSBUCHSTABEN_MIT_UNTERSTRICH; Format-Strings
-- nur mit %s und %d, in allen Sprachen gleiche Platzhalter in gleicher
-- Reihenfolge. Datei: UTF-8 ohne BOM.
-- ---------------------------------------------------------------------------

local T = Transmog

T.Locale.Add("enUS", {
   -- Tausendertrenner fuer Util.FormatNumber / Util.FormatMoney
   THOUSANDS_SEP = ",",

   -- Meldung beim Anmelden (Boot): Name, Version
   LOADED = "%s %s loaded - type /transmog to open the window.",

   -- Einmalige Meldung nach der Uebernahme der Daten der alten Version
   MIGRATED_OUTFITS = "Imported outfits from the previous Transmog version: %d",
})
