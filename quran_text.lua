--[[--
Quran text & translation access — reads the text-vN.sqlite data package
(built by quran-explorer kb/export/quran_text_extract.py, shipped as the
quran_text asset) PLUS any installed per-translation packages
(text_<slug>-vN.sqlite, ND-28: one sqlite per QUL edition, built by
quran-ebook tools/build_text_translations.py --packages). Provides the
ayah text the browser renders in-window (unified ayah page, Reader) and
the FTS queries; translation rosters merge base-first across every
installed package (mergeTransLists).

Tables (contract, schema_version 1): ayah(riwayah, surah, ayah, text,
text_plain, page, juz) — hafs + warsh, native numbering each; translation
(trans_id, surah, ayah, text) — Hafs numbering; trans_meta; ayah_fts /
trans_fts over pre-normalized text (see quran_norm.lua); meta.
Per-translation packages carry translation/trans_meta/trans_fts/meta
only (no ayah tables) — the BASE package stays required for Arabic text.
--]]

local logger = require("logger")
local _ = require("gettext")

local M = {}

M.SCHEMA_VERSION = "1"

-- ---------------------------------------------------------------------
-- Database access (same discovery/gate idiom as quran_roots/quran_qul)
-- ---------------------------------------------------------------------

-- Search dirs for text packages: asset-manager install dir first, then
-- the plugin dir (dev convenience; gitignored there).
local function searchDirs(quran)
    local dirs = {}
    local ok, DataStorage = pcall(require, "datastorage")
    if ok then
        table.insert(dirs, DataStorage:getDataDir() .. "/data/quran")
    end
    if quran and quran.path then
        table.insert(dirs, quran.path)
    end
    return dirs
end

-- Locate text-vN.sqlite (the BASE package: Arabic text + bundled
-- translations).
function M.findDb(quran)
    local lfs = require("libs/libkoreader-lfs")
    for _i, dir in ipairs(searchDirs(quran)) do
        if lfs.attributes(dir, "mode") == "directory" then
            for entry in lfs.dir(dir) do
                if entry:match("^text%-v%d+%.sqlite$") then
                    return dir .. "/" .. entry
                end
            end
        end
    end
end

-- ND-28 per-translation packages: text_<slug>-vN.sqlite next to the base
-- package (underscore vs the base's dash — the patterns never overlap).
-- Highest version wins per name; results sorted by path for a stable
-- merge order. Returns { "/dir/text_en_sahih-v1.sqlite", ... }.
function M.findTranslationDbs(quran)
    local lfs = require("libs/libkoreader-lfs")
    local best = {}
    for _i, dir in ipairs(searchDirs(quran)) do
        if lfs.attributes(dir, "mode") == "directory" then
            for entry in lfs.dir(dir) do
                local name, ver = entry:match("^(text_[%w_]+)%-v(%d+)%.sqlite$")
                if name and (not best[name] or tonumber(ver) > best[name].ver) then
                    best[name] = { ver = tonumber(ver), path = dir .. "/" .. entry }
                end
            end
        end
    end
    local out = {}
    for _name, b in pairs(best) do table.insert(out, b.path) end
    table.sort(out)
    return out
end

-- Open one package read-only, gated on meta.schema_version (no caching).
local function openGated(path)
    local ok, SQ3 = pcall(require, "lua-ljsqlite3/init")
    if not ok then
        return nil, _("SQLite support not available in this KOReader build.")
    end
    local open_ok, conn = pcall(SQ3.open, path, "ro")
    if not open_ok or not conn then
        return nil, _("Could not open the Quran text database.")
    end
    local ver_ok, ver = pcall(function()
        local stmt = conn:prepare("SELECT value FROM meta WHERE key='schema_version'")
        local row = stmt:step()
        stmt:close()
        return row and tostring(row[1])
    end)
    if not ver_ok or ver ~= M.SCHEMA_VERSION then
        pcall(function() conn:close() end)
        return nil, _("Quran text database has an unsupported format. Update the plugin or the data package.")
    end
    return conn
end

-- Open (and cache) the base package. Returns conn or nil, err.
function M.openPath(path)
    if M._conn and M._db_path == path then
        return M._conn
    end
    local conn, err = openGated(path)
    if not conn then return nil, err end
    M._conn = conn
    M._db_path = path
    logger.info("quran.koplugin: opened text db", path)
    return conn
end

function M.ensureDb(quran)
    local path = M._db_path or M.findDb(quran)
    if not path then
        return nil, _("Quran text package not installed. Get it from Library & assets in the Quran Explorer.")
    end
    return M.openPath(path)
end

-- Open (and cache) every installed per-translation package. The cache
-- keys on the discovered path set, so a package installed mid-session is
-- picked up on the next call after M.invalidate() (or a re-scan finding
-- new files). Returns { conn, ... } (possibly empty).
function M.auxConns(quran)
    local paths = M.findTranslationDbs(quran)
    local sig = table.concat(paths, ";")
    if M._aux and M._aux.sig == sig then
        return M._aux.conns
    end
    if M._aux then
        for _i, c in ipairs(M._aux.conns) do pcall(function() c:close() end) end
    end
    local conns = {}
    for _i, path in ipairs(paths) do
        local conn, err = openGated(path)
        if conn then
            table.insert(conns, conn)
        else
            logger.info("quran.koplugin: skipping translation package", path, err)
        end
    end
    M._aux = { sig = sig, conns = conns }
    return conns
end

-- Drop every cached connection (called by the asset manager after a
-- translation/text package install or uninstall, so the next query
-- re-scans without a restart).
function M.invalidate()
    if M._conn then pcall(function() M._conn:close() end) end
    M._conn, M._db_path = nil, nil
    if M._aux then
        for _i, c in ipairs(M._aux.conns) do pcall(function() c:close() end) end
    end
    M._aux = nil
end

local function rows(conn, sql, bind)
    local out = {}
    local ok, err = pcall(function()
        local stmt = conn:prepare(sql)
        for i, v in ipairs(bind or {}) do
            stmt:bind1(i, v)
        end
        while true do
            local row = stmt:step()
            if not row then break end
            table.insert(out, row)
        end
        stmt:close()
    end)
    if not ok then
        logger.info("quran.koplugin: text query failed:", err)
    end
    return out
end

-- ---------------------------------------------------------------------
-- Queries
-- ---------------------------------------------------------------------

--- Ayah row for a riwayah (native numbering). Returns
-- { text, text_plain, page, juz } or nil.
function M.ayah(conn, riwayah, surah, ayah)
    local r = rows(conn, [[
        SELECT text, text_plain, page, juz FROM ayah
        WHERE riwayah = ? AND surah = ? AND ayah = ?]],
        { riwayah, surah, ayah })[1]
    if not r then return end
    return {
        text = r[1],
        text_plain = r[2] ~= nil and tostring(r[2]) or nil,
        page = tonumber(r[3]),
        juz = tonumber(r[4]),
    }
end

--- FTS over the normalized Hafs ayah text. fts_query must already be
-- normalized with quran_norm.norm — norm output contains no quotes or
-- FTS operators, so it is safe to pass bare (terms AND together).
-- Returns { surah, ayah, text } rows (text = plain imlaei, for display).
function M.searchAyahText(conn, fts_query, limit)
    local out = {}
    for _i, r in ipairs(rows(conn, [[
        SELECT f.surah, f.ayah, a.text_plain
        FROM ayah_fts f
        JOIN ayah a ON a.riwayah = 'hafs'
            AND a.surah = f.surah AND a.ayah = f.ayah
        WHERE ayah_fts MATCH ? ORDER BY rank LIMIT ?]],
        { fts_query, limit or 20 })) do
        table.insert(out, { surah = tonumber(r[1]), ayah = tonumber(r[2]),
            text = r[3] and tostring(r[3]) or "" })
    end
    return out
end

--- FTS over the normalized translation text (same query contract).
function M.searchTranslation(conn, fts_query, limit)
    local out = {}
    for _i, r in ipairs(rows(conn, [[
        SELECT f.surah, f.ayah, f.trans_id, t.text
        FROM trans_fts f
        JOIN translation t ON t.trans_id = f.trans_id
            AND t.surah = f.surah AND t.ayah = f.ayah
        WHERE trans_fts MATCH ? ORDER BY rank LIMIT ?]],
        { fts_query, limit or 20 })) do
        table.insert(out, { surah = tonumber(r[1]), ayah = tonumber(r[2]),
            trans_id = tostring(r[3]), text = tostring(r[4]) })
    end
    return out
end

--- Translation FTS across the base package AND every installed
-- per-translation package (rank ordering holds within each db; the
-- merged list keeps base hits first and truncates at limit).
function M.searchTranslationAll(quran, conn, fts_query, limit)
    limit = limit or 20
    local out = M.searchTranslation(conn, fts_query, limit)
    for _i, aux in ipairs(M.auxConns(quran)) do
        if #out >= limit then break end
        for _j, h in ipairs(M.searchTranslation(aux, fts_query, limit - #out)) do
            table.insert(out, h)
        end
    end
    return out
end

--- All shipped translations of a (Hafs-numbered) ayah, with source names.
function M.translations(conn, surah, ayah)
    local out = {}
    for _i, r in ipairs(rows(conn, [[
        SELECT t.trans_id, m.name, m.lang, t.text
        FROM translation t JOIN trans_meta m ON m.trans_id = t.trans_id
        WHERE t.surah = ? AND t.ayah = ? ORDER BY t.trans_id]],
        { surah, ayah })) do
        table.insert(out, {
            trans_id = tostring(r[1]), name = tostring(r[2]),
            lang = tostring(r[3]), text = tostring(r[4]),
        })
    end
    return out
end

--- Every translation in the package (trans_meta), db order.
function M.allTranslations(conn)
    local out = {}
    for _i, r in ipairs(rows(conn, [[
        SELECT trans_id, name, lang FROM trans_meta
        ORDER BY trans_id]])) do
        table.insert(out, { trans_id = tostring(r[1]),
            name = tostring(r[2]), lang = tostring(r[3]) })
    end
    return out
end

--- Pure: merge ordered translation lists, first occurrence of a
-- trans_id wins (ND-28: the base package leads, so a per-translation
-- package that duplicates a bundled edition never double-lists and the
-- user's trans_id-keyed settings keep applying).
function M.mergeTransLists(lists)
    local out, seen = {}, {}
    for _i, list in ipairs(lists) do
        for _j, t in ipairs(list or {}) do
            if t.trans_id and not seen[t.trans_id] then
                seen[t.trans_id] = true
                table.insert(out, t)
            end
        end
    end
    return out
end

--- M.translations across base + every installed translation package.
function M.translationsAll(quran, conn, surah, ayah)
    local lists = { M.translations(conn, surah, ayah) }
    for _i, aux in ipairs(M.auxConns(quran)) do
        table.insert(lists, M.translations(aux, surah, ayah))
    end
    return M.mergeTransLists(lists)
end

--- M.allTranslations across base + every installed translation package
-- (the Settings roster: every id the merge can surface).
function M.allTranslationsMerged(quran, conn)
    local lists = { M.allTranslations(conn) }
    for _i, aux in ipairs(M.auxConns(quran)) do
        table.insert(lists, M.allTranslations(aux))
    end
    return M.mergeTransLists(lists)
end

--- Pure: apply the user's roster settings to a translations list —
-- `off` = set of disabled trans_ids, `order` = array of trans_ids
-- (unlisted ids keep db order at the tail). Nil settings = unchanged.
function M.applyRoster(all, off, order)
    local out = {}
    for _i, t in ipairs(all) do
        if not (off and off[t.trans_id]) then table.insert(out, t) end
    end
    if order then
        local rank = {}
        for i, id in ipairs(order) do rank[id] = i end
        local BIG = #order + 1
        local pos = {}
        for i, t in ipairs(out) do pos[t] = i end
        table.sort(out, function(x, y)
            local rx, ry = rank[x.trans_id] or BIG, rank[y.trans_id] or BIG
            if rx ~= ry then return rx < ry end
            return pos[x] < pos[y]
        end)
    end
    return out
end

--- The user's translation roster for an ayah: base + installed
-- packages (translationsAll), filtered by the translations_off set and
-- ordered by translations_order (both plugin settings; owner
-- 2026-07-18 — enable/disable + sort; ND-28 folds packages in).
function M.enabledTranslations(quran, conn, surah, ayah)
    local s = quran and quran.settings
    -- default order: Saheeh International leads (the package's
    -- original sole translation — plain ORDER BY trans_id would
    -- promote en-asad), everything else keeps db order
    return M.applyRoster(M.translationsAll(quran, conn, surah, ayah),
        s and s:readSetting("translations_off") or nil,
        s and s:readSetting("translations_order") or { "en-sahih" })
end

return M
