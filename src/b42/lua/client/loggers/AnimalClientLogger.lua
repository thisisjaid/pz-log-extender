--
-- Copyright (c) 2024 outdead.
-- Use of this source code is governed by the Apache 2.0 license.
--
-- AnimalClientLogger logs B42 animal-related timed actions to the Logs
-- directory. Controlled by the AnimalActions sandbox option.
--

local AnimalClientLogger = {}

-- getAnimalName mirrors the naming logic from ISAnimalUI (the in-game animal panel):
--   1. getCustomName()  — player-assigned name ("Bessie"), if set
--   2. translated breed + translated type  ("Rhode Island Red Hen")
--   3. raw type key fallback  ("henrhodeisland")
--
-- Each B42 animal action stores its animal differently:
--   self.animal              — ISKillAnimal, ISPickupAnimal, ISAttachAnimalToPlayer,
--                              ISRemoveAnimalFromTrailer, ISAddAnimalInTrailer (world)
--   self.animalItem          — ISKillAnimalInInventory (InventoryItem → IsoAnimal)
--   self.animalInventoryItem — ISAddAnimalInTrailer fromHand (InventoryItem → IsoAnimal)
--   self.body                — ISPutAnimalOnHook, ISRemoveAnimalFromHook, ISButcherAnimal
--   self.hutch + index       — ISHutchGrabAnimal (must be read before hutch:removeAnimal)
--
-- getAnimalType() is used as a probe: only IsoAnimal/IsoDeadBody respond to it,
-- so a stray IsoPlayer in self.target is skipped rather than logged as the animal.
local function getAnimalName(action)
    local candidates = {}

    -- Checked individually (not via ipairs over a literal) because a nil hole
    -- would make ipairs stop early and miss later candidates.
    if action.animal ~= nil then candidates[#candidates + 1] = action.animal end
    if action.isoAnimal ~= nil then candidates[#candidates + 1] = action.isoAnimal end
    if action.target ~= nil then candidates[#candidates + 1] = action.target end

    if action.animalItem ~= nil then
        local ok, a = pcall(function() return action.animalItem:getAnimal() end)
        if ok and a ~= nil then candidates[#candidates + 1] = a end
    end

    if action.animalInventoryItem ~= nil then
        local ok, a = pcall(function() return action.animalInventoryItem:getAnimal() end)
        if ok and a ~= nil then candidates[#candidates + 1] = a end
    end

    if action.body ~= nil then candidates[#candidates + 1] = action.body end

    if action.hutch ~= nil and action.index ~= nil then
        local ok, a = pcall(function() return action.hutch:getAnimal(action.index) end)
        if ok and a ~= nil then candidates[#candidates + 1] = a end
    end

    for _, obj in ipairs(candidates) do
        local ok, rawType = pcall(function() return tostring(obj:getAnimalType()) end)
        if ok and rawType and rawType ~= "" and rawType ~= "nil" then
            local ok2, custom = pcall(function() return obj:getCustomName() end)
            if ok2 and custom and custom ~= "" and custom ~= "nil" then
                return custom
            end

            local displayType = rawType
            local ok3, t = pcall(function() return getText("IGUI_AnimalType_" .. rawType) end)
            if ok3 and t and t ~= "" and t ~= "nil" then displayType = t end

            local breedPrefix = ""
            local ok4, breedName = pcall(function() return obj:getData():getBreed():getName() end)
            if ok4 and breedName and breedName ~= "" and breedName ~= "nil" then
                local ok5, b = pcall(function() return getText("IGUI_Breed_" .. breedName) end)
                breedPrefix = ((ok5 and b and b ~= "" and b ~= "nil") and b or breedName) .. " "
            end

            return breedPrefix .. displayType
        end
    end

    return "unknown"
end

local function doLog(action, logAction)
    local player = action.character
    if not player then return end
    -- Prefer the name captured at start() — by the time a server-authoritative
    -- action finishes, Java may have removed the animal from the world.
    local animalName = action._b42le_animalName or getAnimalName(action)
    local location = logutils.GetLocation(player)
    local message = logutils.GetLogLinePrefix(player, logAction .. " \"" .. animalName .. "\"") .. " @ " .. location
    logutils.WriteLog(logutils.filemask.animal, message)
end

-- wrapClass patches an action class to log exactly once on completion.
--
-- Most animal actions complete through Lua perform()/complete(), which we wrap
-- directly. Three actions are server-authoritative — ISPickupAnimal,
-- ISKillAnimalInInventory and ISAddAnimalInTrailer run their real
-- perform()/complete() on the server. On the client they run for their full
-- duration and finish via stop(); perform()/complete() are never called
-- client-side. For those, completesViaStop=true logs from stop() instead,
-- gated on job progress so a genuine mid-action cancellation is ignored.
--
-- A per-instance _b42le_logged flag makes logging idempotent no matter which
-- callbacks fire, so wrapping every path is always safe.
local function wrapClass(clsName, cls, logAction, completesViaStop)
    if cls == nil then
        print("[B42LogExtender] AnimalClientLogger: " .. clsName .. " not found — skipped")
        return false
    end

    local function logOnce(action)
        if action._b42le_logged then return end
        action._b42le_logged = true
        pcall(doLog, action, logAction)
    end

    -- Capture the animal name at start(), while all data is still intact.
    local origStart = cls.start
    if origStart then
        cls.start = function(self)
            local ok, name = pcall(getAnimalName, self)
            self._b42le_animalName = (ok and name) or nil
            origStart(self)
        end
    end

    local origPerform = cls.perform
    cls.perform = function(self)
        logOnce(self)
        origPerform(self)
    end

    if cls.complete then
        local origComplete = cls.complete
        cls.complete = function(self)
            logOnce(self)
            return origComplete(self)
        end
    end

    if completesViaStop and cls.stop then
        local origStop = cls.stop
        cls.stop = function(self)
            -- Only log if the job actually finished (delta ~= 1.0). A cancelled
            -- action stops with a lower delta. Fail-open: if the delta can't be
            -- read, log anyway rather than silently drop a completion.
            local ok, delta = pcall(function() return self.action:getJobDelta() end)
            if not self._b42le_logged and (not ok or delta == nil or delta >= 0.9) then
                logOnce(self)
            end
            return origStop(self)
        end
    end

    return true
end

AnimalClientLogger.OnGameStart = function()
    if not SandboxVars.LogExtender.AnimalActions then return end

    -- The three flagged true complete via stop() on the client (server-authoritative).
    wrapClass("ISKillAnimal",              ISKillAnimal,              "animal.kill")
    wrapClass("ISKillAnimalInInventory",   ISKillAnimalInInventory,   "animal.kill_in_inventory", true)
    wrapClass("ISPickupAnimal",            ISPickupAnimal,            "animal.pickup",            true)
    wrapClass("ISButcherAnimal",           ISButcherAnimal,           "animal.butcher")
    wrapClass("ISPutAnimalOnHook",         ISPutAnimalOnHook,         "animal.put_on_hook")
    wrapClass("ISRemoveAnimalFromHook",    ISRemoveAnimalFromHook,    "animal.remove_from_hook")
    wrapClass("ISAddAnimalInTrailer",      ISAddAnimalInTrailer,      "animal.load_trailer",      true)
    wrapClass("ISRemoveAnimalFromTrailer", ISRemoveAnimalFromTrailer, "animal.unload_trailer")
    wrapClass("ISAttachAnimalToPlayer",    ISAttachAnimalToPlayer,    "animal.attach")
    wrapClass("ISHutchGrabAnimal",         ISHutchGrabAnimal,         "animal.grab_from_hutch")
    wrapClass("ISPutAnimalInHutch",        ISPutAnimalInHutch,        "animal.put_in_hutch")
end

Events.OnGameStart.Add(AnimalClientLogger.OnGameStart)
