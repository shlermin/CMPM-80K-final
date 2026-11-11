--
-- narrator.lua
--
-- Glue between the Narrator ink interpreter (libraries/narrator) and the
-- Talkies dialog UI (libraries/talkies). Exposes a tiny API for defining
-- characters, binding them to in-game NPCs, and running .ink scripts that
-- live under scripts/<name>.ink.
--
-- Usage (in main.lua):
--
--   narrator = require 'narrator'
--   narrator:init()
--
--   characterBella = narrator:newCharacter("Bella", "sprites/bella_avatar.png")
--   narrator:bindNPC(myNPC, characterBella, "BellaSaysHello")
--
--   -- in love.update(dt):
--   narrator:update(dt)
--
--   -- in love.draw (after cam:detach()):
--   narrator:draw()
--
--   -- in love.keypressed(key):
--   if key == "e" and not narrator:isOpen() then
--       narrator:startScript(myNPC)
--   end
--

local narrator = {}

-- Forward declarations
local Talkies
local NarratorLib

--
-- init -----------------------------------------------------------------------

--- One-time setup. Must be called from love.load (after LOVE has booted).
function narrator:init()
    -- Allow `require('narrator.something')` to resolve inside
    -- libraries/narrator/. LOVE uses its own loader (driven by
    -- love.filesystem.setRequirePath), which is separate from the standard
    -- Lua `package.path` — so we have to extend both to cover every loader.
    love.filesystem.setRequirePath(
        love.filesystem.getRequirePath()
        .. ';libraries/?.lua;libraries/?/init.lua'
    )
    package.path = package.path
        .. ';libraries/?.lua;libraries/?/init.lua'

    -- Narrator's parser hard-requires `lpeg`. LOVE doesn't ship with native
    -- LPeg, so we substitute the pure-Lua port (lulpeg) registered under the
    -- same module name. If real lpeg happens to be available, we use it.
    --
    -- We request a lulpeg instance with `factorize = false`: the default
    -- factorizer crashes on some of narrator's grammar shapes in LuaJIT. It
    -- makes parsing a hair slower but only runs once per script load.
    if not pcall(require, 'lpeg') then
        local lulpeg = require('lulpeg')
        package.loaded['lpeg'] = lulpeg.new({ factorize = false })
    end

    NarratorLib = require('libraries.narrator.narrator')
    Talkies     = require('libraries.talkies')

    -- A few sensible defaults for the dialog box. Users can tweak these
    -- after init by reaching into `Talkies` directly.
    Talkies.font      = love.graphics.newFont(16)
    Talkies.padding   = 12
    Talkies.rounding  = 4
    Talkies.thickness = 2

    -- Track which NPCs are currently bound so we can iterate them later.
    self._boundNPCs = {}
end

--
-- Character + binding --------------------------------------------------------

--- Create a character record (name + portrait image).
-- @param name        Display name shown in the dialog title bar.
-- @param avatarPath  Path to a portrait image, or nil for no avatar.
-- @return character table { name = ..., image = ... }
function narrator:newCharacter(name, avatarPath)
    local image = nil
    if avatarPath then
        image = love.graphics.newImage(avatarPath)
    end
    return { name = name, image = image }
end

--- Attach a character + ink script to an existing NPC.
-- After binding:
--   * The NPC pauses its wandering whenever it is the current speaker.
--   * The proximity logic in main.lua uses `npc.character` to know who to
--     greet and `npc.script` to know which .ink file to load.
-- @param npc         The NPC table returned by NPC.new(...)
-- @param character   A character record from narrator:newCharacter(...)
-- @param scriptName  Filename (without extension) under scripts/
function narrator:bindNPC(npc, character, scriptName)
    npc.character   = character
    npc.script      = scriptName
    npc.isTalking   = false

    -- Wrap the NPC's update so wandering halts while it's the active speaker.
    -- We do this once per NPC; calling bi  ndNPC twice on the same NPC won't
    -- double-wrap because we stash the original update under _origUpdate.
    if not npc._origUpdate then
        npc._origUpdate = npc.update
        npc.update = function(self_, dt)
            if self_.isTalking then
                -- Hold the idle pose, skip movement.
                if self_.anim and self_.anim.gotoFrame then
                    self_.anim:gotoFrame(2)
                end
                return
            end
            self_:_origUpdate(dt)
        end
    end

    table.insert(self._boundNPCs, npc)
    return npc
end

--
-- Running scripts ------------------------------------------------------------

--- Internal: pull the next batch of paragraphs+choices from the live story
-- and push them into the Talkies queue.
function narrator:_pump(state)
    local story = state.story

    -- Drain any paragraphs that ink can produce right now.
    local lines = {}
    while story:can_continue() do
        local batch = story:continue()
        for _, paragraph in ipairs(batch) do
            local text = paragraph.text or ""
            if text ~= "" then
                table.insert(lines, text)
            end
        end
    end

    local config = {}
    if state.character and state.character.image then
        config.image = state.character.image
    end

    if story:can_choose() then
        -- Build a Talkies options array. Each entry is { label, callback }.
        local choices = story:get_choices()
        local options = {}
        for i, choice in ipairs(choices) do
            options[i] = {
                choice.text,
                function()
                    story:choose(i)
                    narrator:_pump(state)
                end,
            }
        end
        config.options = options

        -- If the author wrote choices with no preceding paragraph, give the
        -- player something to read so the option list has somewhere to live.
        if #lines == 0 then
            lines = { "..." }
        end
    else
        -- Story is going to end after the player advances through `lines`.
        -- Mark the speaker free again once the dialog box closes.
        config.oncomplete = function()
            if state.npc then state.npc.isTalking = false end
        end

        if #lines == 0 then
            -- Nothing left at all (e.g. story:choose led straight to END).
            if state.npc then state.npc.isTalking = false end
            return
        end
    end

    local title = (state.character and state.character.name) or ""
    Talkies.say(title, lines, config)
end

--- Start a script. Accepts either a bound NPC (uses its character + script)
--- or a raw script name string.
function narrator:startScript(npcOrScriptName)
    local npc, scriptName, character

    if type(npcOrScriptName) == "string" then
        scriptName = npcOrScriptName
        character  = { name = "", image = nil }
    else
        npc        = npcOrScriptName
        scriptName = npc.script
        character  = npc.character or { name = "", image = nil }
        assert(scriptName, "narrator:startScript - this NPC has no bound script. Did you call narrator:bindNPC?")
    end

    -- Read the .ink file via love.filesystem so it works no matter where the
    -- game is launched from (or when packaged as a .love archive).
    local path = "scripts/" .. scriptName .. ".ink"
    local content, err = love.filesystem.read(path)
    assert(content, "narrator: could not load " .. path .. " (" .. tostring(err) .. ")")

    local book  = NarratorLib.parse_content(content)
    local story = NarratorLib.init_story(book)
    story:begin()

    if npc then npc.isTalking = true end

    local state = { story = story, npc = npc, character = character }
    self:_pump(state)
end

--
-- Forwarders to Talkies ------------------------------------------------------

function narrator:update(dt)
    Talkies.update(dt)
end

function narrator:draw()
    Talkies.draw()
end

function narrator:onAction()
    Talkies.onAction()
end

function narrator:prevOption()
    Talkies.prevOption()
end

function narrator:nextOption()
    Talkies.nextOption()
end

function narrator:isOpen()
    return Talkies.isOpen()
end

return narrator
