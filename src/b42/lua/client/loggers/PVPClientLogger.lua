--
-- Copyright (c) 2024 outdead.
-- Use of this source code is governed by the Apache 2.0 license.
--
-- PVPClientLogger adds logr for PVP actions to the Logs directory the Project Zomboid game.
--

local PVPClientLogger = {}

-- WeaponHitCharacter adds player hit record to pvp log file.
-- [06-07-22 04:12:00.737] user Player1 (6823,5488,0) hit user Player2 (6822,5488,0) with Base.HuntingKnife damage 1.137.
-- B42: OnWeaponHitCharacter removed; replaced by OnWeaponHitXp(owner, weapon, hitObject, damage, hitCount).
PVPClientLogger.WeaponHitCharacter = function(owner, weapon, hitObject, damage, hitCount)
    if not SandboxVars.LogExtender.HitPVP then
        return
    end

    if owner ~= getPlayer() or not instanceof(hitObject, 'IsoPlayer') then
        return
    end

    if hitObject:isDead() then
        return
    end

    local message = 'user ' .. owner:getUsername() .. ' (' .. logutils.GetLocation(owner) ..  ') hit user ';
    message = message .. hitObject:getUsername() .. ' (' .. logutils.GetLocation(hitObject) ..  ') with ';
    message = message .. weapon:getFullType();
    message = message .. ' damage ' .. string.format("%.3f", damage);

    logutils.WriteLog(logutils.filemask.pvp, message);
end

-- OnGameStart adds callback for OnGameStart global event.
PVPClientLogger.OnGameStart = function()
    Events.OnWeaponHitXp.Add(PVPClientLogger.WeaponHitCharacter)
end

Events.OnGameStart.Add(PVPClientLogger.OnGameStart)
