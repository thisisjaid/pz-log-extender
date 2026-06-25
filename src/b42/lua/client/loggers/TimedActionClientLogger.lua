--
-- Copyright (c) 2024 outdead.
-- Use of this source code is governed by the Apache 2.0 license.
--
-- TimedActionClientLogger adds more timed actions logs to the Logs directory
-- the Project Zomboid game.
--

local TimedActionClientLogger = {}

-- TimedActionPerform overrides the original ISBaseTimedAction: perform function to gain
-- access to player events.
TimedActionClientLogger.TimedActionPerform = function()
    local originalPerform = ISBaseTimedAction.perform;

    ISBaseTimedAction.perform = function(self)
        originalPerform(self);

        local player = self.character;

        if player then
            local location = logutils.GetLocation(player);

            -- B42: self.Type is never set; use instanceof() for class detection.
            if instanceof(self, 'ISTakeGenerator') then
                local message = logutils.GetLogLinePrefix(player, "taken IsoGenerator") .. " (appliances_misc_01_0) at " .. location;
                logutils.WriteLog(logutils.filemask.map, message);
                if SandboxVars.LogExtender.AlternativeMap then
                    logutils.WriteLog(logutils.filemask.map_alternative, message);
                end
            elseif instanceof(self, 'ISToggleStoveAction') then
                local message = logutils.GetLogLinePrefix(player, "stove.toggle") .. " @ " .. location;
                logutils.WriteLog(logutils.filemask.cmd, message);
            elseif instanceof(self, 'ISRemoveCampfireAction') then
                -- ISPlaceCampfireAction was removed in B42.
                local message = logutils.GetLogLinePrefix(player, "taken Campfire") .. " (camping_01_6) at " .. location;
                logutils.WriteLog(logutils.filemask.map, message);
                if SandboxVars.LogExtender.AlternativeMap then
                    logutils.WriteLog(logutils.filemask.map_alternative, message);
                end
            elseif instanceof(self, 'ISLightFromKindle') or instanceof(self, 'ISLightFromLiterature') or instanceof(self, 'ISLightFromPetrol')
                or instanceof(self, 'ISBBQLightFromKindle') or instanceof(self, 'ISBBQLightFromLiterature') or instanceof(self, 'ISBBQLightFromPetrol') then
                local message = logutils.GetLogLinePrefix(player, "campfire.light") .. " @ " .. location;
                logutils.WriteLog(logutils.filemask.cmd, message);
            elseif instanceof(self, 'ISPutOutCampfireAction') then
                local message = logutils.GetLogLinePrefix(player, "campfire.extinguish") .. " @ " .. location;
                logutils.WriteLog(logutils.filemask.cmd, message);
            elseif instanceof(self, 'ISRemoveTrapAction') then
                local message = logutils.GetLogLinePrefix(player, "taken Trap") .. " (" .. self.trap.openSprite .. ") at " .. location;
                logutils.WriteLog(logutils.filemask.map, message);
                if SandboxVars.LogExtender.AlternativeMap then
                    logutils.WriteLog(logutils.filemask.map_alternative, message);
                end
            end

            if SandboxVars.LogExtender.AlternativeMap then
                -- Action=removed - Destroyed with sledgehammer.
                if instanceof(self, 'ISDestroyStuffAction') then
                    local obj = self.item;
                    local objLocation = ""
                    if obj.GetX ~= nil then
                        objLocation = logutils.GetLocation(obj);
                    else
                        -- Workaround for destroying IsoRadio and IsoTelevision from Brush Tool.
                        -- Those objects don't have x,y,z position; get IsoGridSquare from coroutine stack.
                        local coroutine = getCurrentCoroutine();
                        local count = getCoroutineTop(coroutine);
                        for i = count - 1, 0, -1 do
                            local o = getCoroutineObjStack(coroutine, i);
                            if o ~= nil and instanceof(o, 'IsoGridSquare') then
                                objLocation = logutils.GetLocation(o);
                                break;
                            end
                        end

                        if objLocation == nil or objLocation == "" then
                            objLocation = location
                        end
                    end
                    local sprite = obj:getSprite();
                    local spriteName = sprite:getName() or "undefined"
                    local objName = obj:getName() or obj:getObjectName();
                    if objName == "" then
                        objName = instanceof(self.item, 'IsoThumpable') and "IsoThumpable" or "undefined"
                    end

                    local message = logutils.GetLogLinePrefix(player, "removed " .. objName) .. " (" .. spriteName .. ") at " .. objLocation .. " (" .. location .. ")";
                    logutils.WriteLog(logutils.filemask.map_alternative, message);
                elseif instanceof(self, 'ISMoveablesAction') then
                    -- Action=disassembled - Disassembled with tools.
                    if self.mode and self.mode=="scrap" and self.moveProps and self.moveProps.object then
                        local obj = self.moveProps.object;
                        local objLocation = logutils.GetLocation(self.square);
                        local sprite = obj:getSprite();
                        local spriteName = sprite:getName() or "undefined"
                        local objName = obj:getName() or obj:getObjectName();
                        if objName == "" then
                            objName = instanceof(self.item, 'IsoThumpable') and "IsoThumpable" or "undefined"
                        end

                        local message = logutils.GetLogLinePrefix(player, "disassembled " .. objName) .. " (" .. spriteName .. ") at " .. objLocation .. " (" .. location .. ")";
                        logutils.WriteLog(logutils.filemask.map_alternative, message);
                    end

                    -- Action=pickedup - Picked up to inventory.
                    if self.mode and self.mode=="pickup" and self.moveProps then
                        local objLocation = logutils.GetLocation(self.square);
                        local sprite = self.moveProps.sprite;
                        local spriteName = sprite:getName() or "undefined"
                        local objName = self.moveProps.isoType;

                        local message = logutils.GetLogLinePrefix(player, "pickedup " .. objName) .. " (" .. spriteName .. ") at " .. objLocation .. " (" .. location .. ")";
                        logutils.WriteLog(logutils.filemask.map_alternative, message);
                    end
                end
            end
        end

        -- B42: ISCraftAction no longer sets self.Type; detect by presence of self.recipe.
        -- ISHandcraftAction (new B42 crafting system) is detected by self.craftRecipe.
        if player then
            local location = logutils.GetLocation(player);

            if self.recipe and self.recipe.getResult then
                -- ISCraftAction (legacy recipe system, still present in B42)
                local recipe = self.recipe
                local recipeName = recipe:getOriginalname()
                local result = recipe:getResult()
                local resultType = result:getFullType()
                local resultCount = result:getCount()

                local message = logutils.GetLogLinePrefix(player, "crafted") .. " " .. resultCount .. " " .. resultType .. " with recipe \"" .. recipeName .. "\" (" .. location .. ")";
                logutils.WriteLog(logutils.filemask.craft, message);
            elseif self.craftRecipe then
                -- ISHandcraftAction (new B42 crafting system)
                local recipeName = self.craftRecipe:getName()

                local message = logutils.GetLogLinePrefix(player, "crafted") .. " recipe \"" .. recipeName .. "\" (" .. location .. ")";
                logutils.WriteLog(logutils.filemask.craft, message);
            end
        end
    end
end

-- OnGameStart adds callback for OnGameStart global event.
TimedActionClientLogger.OnGameStart = function()
    if SandboxVars.LogExtender.TimedActions then
        TimedActionClientLogger.TimedActionPerform()
    end
end

Events.OnGameStart.Add(TimedActionClientLogger.OnGameStart);
