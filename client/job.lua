-- Variables
local currentGarage = 0
local inFingerprint = false
local fingerPrintSessionId = nil
local inStash = false
local inTrash = false
local inHelicopter = false
local inImpound = false
local inGarage = false
local inPrompt = false

local function openFingerprintUi()
    SendNUIMessage({
        type = "fingerprintOpen"
    })
    SetNuiFocus(true, true)
end

local function setCarItemsInfo()
	local items = {}
	for _, item in pairs(Config.CarItems) do
		local itemInfo = QBCore.Shared.Items[item.name:lower()]
		items[item.slot] = {
			name = itemInfo.name,
			amount = tonumber(item.amount),
			info = item.info,
			label = itemInfo.label,
			description = itemInfo.description or "",
			weight = itemInfo.weight,
			type = itemInfo.type,
			unique = itemInfo.unique,
			useable = itemInfo.useable,
			image = itemInfo.image,
			slot = item.slot
		}
	end
	Config.CarItems = items
end

local function doCarDamage(currentVehicle, veh)
	local smash = false
	local damageOutside = false
	local damageOutside2 = false
	local engine = veh.engine + 0.0
	local body = veh.body + 0.0

	if engine < 200.0 then engine = 200.0 end
    if engine  > 1000.0 then engine = 950.0 end
	if body < 150.0 then body = 150.0 end
	if body < 950.0 then smash = true end
	if body < 920.0 then damageOutside = true end
	if body < 920.0 then damageOutside2 = true end

    Wait(100)
    SetVehicleEngineHealth(currentVehicle, engine)

	if smash then
		SmashVehicleWindow(currentVehicle, 0)
		SmashVehicleWindow(currentVehicle, 1)
		SmashVehicleWindow(currentVehicle, 2)
		SmashVehicleWindow(currentVehicle, 3)
		SmashVehicleWindow(currentVehicle, 4)
	end

	if damageOutside then
		SetVehicleDoorBroken(currentVehicle, 1, true)
		SetVehicleDoorBroken(currentVehicle, 6, true)
		SetVehicleDoorBroken(currentVehicle, 4, true)
	end

	if damageOutside2 then
		SetVehicleTyreBurst(currentVehicle, 1, false, 990.0)
		SetVehicleTyreBurst(currentVehicle, 2, false, 990.0)
		SetVehicleTyreBurst(currentVehicle, 3, false, 990.0)
		SetVehicleTyreBurst(currentVehicle, 4, false, 990.0)
	end

	if body < 1000 then
		SetVehicleBodyHealth(currentVehicle, 985.1)
	end
end

local function takeOutImpound(vehicle)
    if not inImpound then return end
    local coords = Config.Locations.impound[currentGarage]
    if not coords then return end
    QBCore.Functions.TriggerCallback('QBCore:Server:SpawnVehicle', function(netId)
        local veh = NetToVeh(netId)
        QBCore.Functions.TriggerCallback('qb-garage:server:GetVehicleProperties', function(properties)
            QBCore.Functions.SetVehicleProperties(veh, properties)
            SetVehicleNumberPlateText(veh, vehicle.plate)
            SetVehicleFuelLevel(veh, vehicle.fuel)
            doCarDamage(veh, vehicle)
            TriggerServerEvent('police:server:TakeOutImpound', vehicle.plate, currentGarage)
            TaskWarpPedIntoVehicle(cache.ped, veh, -1)
            TriggerEvent("vehiclekeys:client:SetOwner", QBCore.Functions.GetPlate(veh))
            SetVehicleEngineOn(veh, true, true, false)
        end, vehicle.plate)
    end, vehicle.vehicle, coords, true)
end

local function takeOutVehicle(vehicleInfo)
    if not inGarage then return end
    local coords = Config.Locations.vehicle[currentGarage]
    if not coords then return end

    QBCore.Functions.TriggerCallback('QBCore:Server:SpawnVehicle', function(netId)
        local veh = NetToVeh(netId)
        setCarItemsInfo()
        SetVehicleNumberPlateText(veh, Lang:t('info.police_plate')..tostring(math.random(1000, 9999)))
        SetEntityHeading(veh, coords.w)
        SetVehicleFuelLevel(veh, 100.0)
        if Config.VehicleSettings[vehicleInfo] then
            if Config.VehicleSettings[vehicleInfo].extras then
                QBCore.Shared.SetDefaultVehicleExtras(veh, Config.VehicleSettings[vehicleInfo].extras)
            end
            if Config.VehicleSettings[vehicleInfo].livery then
                SetVehicleLivery(veh, Config.VehicleSettings[vehicleInfo].livery)
            end
        end
        TaskWarpPedIntoVehicle(cache.ped, veh, -1)
        TriggerEvent("vehiclekeys:client:SetOwner", QBCore.Functions.GetPlate(veh))
        TriggerServerEvent("inventory:server:addTrunkItems", QBCore.Functions.GetPlate(veh), Config.CarItems)
        SetVehicleEngineOn(veh, true, true, false)
    end, vehicleInfo, coords, true)
end

local function openGarageMenu()
    local authorizedVehicles = Config.AuthorizedVehicles[PlayerData.job.grade.level]
    local options = {}

    for veh, label in pairs(authorizedVehicles) do
        options[#options+1] = {
            title = label,
            onSelect = function()
                takeOutVehicle(veh)
            end,
        }
    end

    for veh, label in pairs(Config.WhitelistedVehicles) do
        options[#options+1] = {
            title = label,
            onSelect = function()
                takeOutVehicle(veh)
            end,
        }
    end

    lib.registerContext({
        id = 'qb_policejob_vehicles_menu',
        title = Lang:t('menu.garage_title'),
        options = options,
    })
    lib.showContext('qb_policejob_vehicles_menu')
end

local function openImpoundMenu()
    local options = {}
    local result = lib.callback.await("police:GetImpoundedVehicles", false)
    if not result then
        lib.notify({ description = Lang:t("error.no_impound"), type = 'error', })
    else
        for _, v in pairs(result) do
            local enginePercent = QBCore.Shared.Round(v.engine / 10, 0)
            local currentFuel = v.fuel
            local vName = QBCore.Shared.Vehicles[v.vehicle].name

            options[#options+1] = {
                title = vName.." ["..v.plate.."]",
                onSelect = function()
                    takeOutImpound(v)
                end,
                metadata = {
                    {label = 'Engine', value = enginePercent .. ' %'},
                    {label = 'Fuel', value = currentFuel .. ' %'},
                },
            }
        end
    end

    lib.registerContext({
        id = 'qb_policejob_impound_menu',
        title = Lang:t('menu.impound'),
        options = options,
    })
    lib.showContext('qb_policejob_impound_menu')
end

---TODO: global evidence lockers instead of location specific
local function openEvidenceLockerSelectInput(currentEvidence)
    local input = lib.inputDialog(Lang:t('info.evidence_stash', {value = currentEvidence}), {Lang:t('info.slot')})
    if not input then return end
    local slotNumber = tonumber(input[1])
    TriggerServerEvent("inventory:server:OpenInventory", "stash", Lang:t('info.current_evidence', {value = currentEvidence, value2 = slotNumber}), {
        maxweight = 4000000,
        slots = 500,
    })
    TriggerEvent("inventory:client:SetCurrentStash", Lang:t('info.current_evidence', {value = currentEvidence, value2 = slotNumber}))
end

local function openEvidenceMenu()
    local pos = GetEntityCoords(cache.ped)
    for k, v in pairs(Config.Locations.evidence) do
        if #(pos - v) < 1 then
            openEvidenceLockerSelectInput(k)
            return
        end
    end
end

local function spawnHelicopter()
    if not inHelicopter then return end
    if cache.vehicle then
        QBCore.Functions.DeleteVehicle(cache.vehicle)
    else
        local plyCoords = GetEntityCoords(cache.ped)
        local coords = vec4(plyCoords.x, plyCoords.y, plyCoords.z, GetEntityHeading(cache.ped))
        QBCore.Functions.TriggerCallback('QBCore:Server:SpawnVehicle', function(netId)
            local veh = NetToVeh(netId)
            SetVehicleLivery(veh , 0)
            SetVehicleMod(veh, 0, 48, false)
            SetVehicleNumberPlateText(veh, "ZULU"..tostring(math.random(1000, 9999)))
            SetEntityHeading(veh, coords.w)
            SetVehicleFuelLevel(veh, 100.0)
            TaskWarpPedIntoVehicle(cache.ped, veh, -1)
            TriggerEvent("vehiclekeys:client:SetOwner", QBCore.Functions.GetPlate(veh))
            SetVehicleEngineOn(veh, true, true, false)
        end, Config.PoliceHelicopter, coords, true)
    end
end

local function scanFingerprint()
    if not inFingerprint then return end
    local playerId = lib.getClosestPlayer(GetEntityCoords(cache.ped), 2.5, false)
    if not playerId then
        lib.notify({ description = Lang:t("error.none_nearby"), type = 'error', })
        return
    end
    TriggerServerEvent("police:server:showFingerprint", playerId)
end

local function uiPrompt(promptType, id)
    if PlayerData.job.type ~= "leo" then return end
    CreateThread(function()
        while inPrompt do
            Wait(0)
            if IsControlJustReleased(0, 38) then
                if promptType == 'duty' then
                    ToggleDuty()
                    lib.hideTextUI()
                    break
                elseif promptType == 'garage' then
                    if not inGarage then return end
                    if cache.vehicle then
                        QBCore.Functions.DeleteVehicle(cache.vehicle)
                        lib.hideTextUI()
                        break
                    else
                        openGarageMenu()
                        lib.hideTextUI()
                        break
                    end
                elseif promptType == 'evidence' then
                    openEvidenceMenu()
                    lib.hideTextUI()
                    break
                elseif promptType == 'impound' then
                    if not inImpound then return end
                    if cache.vehicle then
                        QBCore.Functions.DeleteVehicle(cache.vehicle)
                        lib.hideTextUI()
                        break
                    else
                        openImpoundMenu()
                        lib.hideTextUI()
                        break
                    end
                elseif promptType == 'heli' then
                    spawnHelicopter()
                    lib.hideTextUI()
                    break
                elseif promptType == 'fingerprint' then
                    scanFingerprint()
                    lib.hideTextUI()
                    break
                elseif promptType == 'trash' then
                    if not inTrash then return end
                    exports.ox_inventory:openInventory('stash', ('policetrash_%s'):format(id))
                    break
                elseif promptType == 'stash' then
                    if not inStash then return end
                    exports.ox_inventory:openInventory('stash', { id = 'policelocker'})
                    break
                end
            end
        end
    end)
end

--NUI Callbacks
RegisterNUICallback('closeFingerprint', function(_, cb)
    SetNuiFocus(false, false)
    cb('ok')
end)

--Events
RegisterNetEvent('police:client:showFingerprint', function(playerId)
    openFingerprintUi()
    fingerPrintSessionId = playerId
end)

RegisterNetEvent('police:client:showFingerprintId', function(fid)
    SendNUIMessage({
        type = "updateFingerprintId",
        fingerprintId = fid
    })
    PlaySound(-1, "Event_Start_Text", "GTAO_FM_Events_Soundset", false, 0, true)
end)

RegisterNUICallback('doFingerScan', function(_, cb)
    TriggerServerEvent('police:server:showFingerprintId', fingerPrintSessionId)
    cb("ok")
end)

RegisterNetEvent('police:client:SendEmergencyMessage', function(coords, message)
    TriggerServerEvent("police:server:SendEmergencyMessage", coords, message)
    TriggerEvent("police:client:CallAnim")
end)

RegisterNetEvent('police:client:EmergencySound', function()
    PlaySound(-1, "Event_Start_Text", "GTAO_FM_Events_Soundset", false, 0, true)
end)

RegisterNetEvent('police:client:CallAnim', function()
    local isCalling = true
    local callCount = 5
    lib.requestAnimDict("cellphone@")
    TaskPlayAnim(cache.ped, 'cellphone@', 'cellphone_call_listen_base', 3.0, -1, -1, 49, 0, false, false, false)
    Wait(1000)
    CreateThread(function()
        while isCalling do
            Wait(1000)
            callCount -= 1
            if callCount <= 0 then
                isCalling = false
                StopAnimTask(cache.ped, 'cellphone@', 'cellphone_call_listen_base', 1.0)
            end
        end
    end)
end)

RegisterNetEvent('police:client:ImpoundVehicle', function(fullImpound, price)
    local vehicle = QBCore.Functions.GetClosestVehicle()
    if not DoesEntityExist(vehicle) then return end

    local bodyDamage = math.ceil(GetVehicleBodyHealth(vehicle))
    local engineDamage = math.ceil(GetVehicleEngineHealth(vehicle))
    local totalFuel = GetVehicleFuelLevel(vehicle)

    if #(GetEntityCoords(cache.ped) - GetEntityCoords(vehicle)) > 5.0 or cache.vehicle then return end

    if lib.progressCircle({
        duration = 5000,
        position = 'bottom',
        label = Lang:t("progressbar.impound"),
        useWhileDead = false,
        canCancel = true,
        disable = {
            move = true,
            car = true,
            combat = true,
            mouse = false,
        },
        anim = {
            dict = 'missheistdockssetup1clipboard@base',
            clip = 'base',
            flags = 1
        },
        prop = {
            {
            model = `prop_notepad_01`,
            bone = 18905,
            pos = { x = 0.1, y = 0.02, z = 0.05 },
            rot = { x = 10.0, y = 0.0, z = 0.0 },
            },
            {
                model = 'prop_pencil_01',
                bone = 58866,
                pos = { x = 0.11, y = -0.02, z = 0.001 },
                rot = { x = -120.0, y = 0.0, z = 0.0 },
            },
        },
    }) 
    then 
        local plate = QBCore.Functions.GetPlate(vehicle)
        TriggerServerEvent("police:server:Impound", plate, fullImpound, price, bodyDamage, engineDamage, totalFuel)
        QBCore.Functions.DeleteVehicle(vehicle)
        lib.notify({ description = Lang:t('success.impounded'), type = 'success' })
        ClearPedTasks(cache.ped)
    else
        ClearPedTasks(cache.ped)
        lib.notify({ description = Lang:t('error.canceled'), type = 'error' })
    end
end)

RegisterNetEvent('police:client:CheckStatus', function()
    if PlayerData.job.type ~= "leo" then return end

    local playerId = lib.getClosestPlayer(GetEntityCoords(cache.ped), 5.0, false)
    if not playerId then
        lib.notify({ description = Lang:t("error.none_nearby"), type = 'error' })
        return
    end
    local result = lib.callback.await('police:GetPlayerStatus', false, playerId)
    if not result then return end
    for _, v in pairs(result) do
        lib.notify({ description = v, type = 'success' })
    end
end)

function ToggleDuty()
    TriggerServerEvent("QBCore:ToggleDuty")
    TriggerServerEvent("police:server:UpdateCurrentCops")
end

-- Threads

if Config.UseTarget then
    CreateThread(function()
        -- Toggle Duty
        for k, v in pairs(Config.Locations.duty) do
            exports['qb-target']:AddBoxZone("box_zone_police_duty_"..k, v, 1, 1, {
                name = "box_zone_police_duty_"..k,
                heading = 11,
                debugPoly = false,
                minZ = v.z - 1,
                maxZ = v.z + 1,
            }, {
                options = {
                    {
                        type = "client",
                        action = ToggleDuty,
                        icon = "fas fa-sign-in-alt",
                        label = "Sign In",
                        job = "police",
                    },
                },
                distance = 1.5
            })
        end
    end)
else
    -- Toggle Duty
    for _, v in pairs(Config.Locations.duty) do
        lib.zones.box({
            coords = v,
            size = vec3(2, 2, 2),
            rotation = 0.0,
            onEnter = function()
                inPrompt = true
                if not PlayerData.job.onduty then
                    lib.showTextUI(Lang:t('info.on_duty'))
                else
                    lib.showTextUI(Lang:t('info.off_duty'))
                end
                uiPrompt('duty')
            end,
            onExit = function()
                inPrompt = false
                lib.hideTextUI()
            end
        })
    end
end

CreateThread(function()
    -- Evidence Storage
    for _, v in pairs(Config.Locations.evidence) do
        lib.zones.box({
            coords = v,
            size = vec3(2, 2, 2),
            rotation = 0.0,
            onEnter = function()
                if PlayerData.job.type == 'leo' and PlayerData.job.onduty then
                    inPrompt = true
                    lib.showTextUI(Lang:t("info.evidence"))
                    uiPrompt('evidence')
                end
            end,
            onExit = function()
                lib.hideTextUI()
                inPrompt = false
            end
        })
    end

    -- Personal Stash
    for _, v in pairs(Config.Locations.stash) do
        lib.zones.box({
            coords = v,
            size = vec3(2, 2, 2),
            rotation = 0.0,
            onEnter = function()
                inStash = true
                inPrompt = true
                lib.showTextUI(Lang:t('info.stash_enter'))
                uiPrompt('stash')
            end,
            onExit = function()
                lib.hideTextUI()
                inPrompt = false
                inStash = false
            end
        })
    end

    -- Police Trash
    for i = 1, #Config.Locations.trash do
        local v = Config.Locations.trash[i]
        lib.zones.box({
            coords = v,
            size = vec3(2, 2, 2),
            rotation = 0.0,
            onEnter = function()
                inTrash = true
                inPrompt = true
                if PlayerData.job.onduty then
                    lib.showTextUI(Lang:t('info.trash_enter'))
                    uiPrompt('trash', i)
                end
            end,
            onExit = function()
                inTrash = false
                inPrompt = false
                lib.hideTextUI()
            end
        })
    end

    -- Fingerprints
    for _, v in pairs(Config.Locations.fingerprint) do
        lib.zones.box({
            coords = v,
            size = vec3(2, 2, 2),
            rotation = 0.0,
            onEnter = function()
                inFingerprint = true
                inPrompt = true
                if PlayerData.job.onduty then
                    lib.showTextUI(Lang:t('info.scan_fingerprint'))
                    uiPrompt('fingerprint')
                end
            end,
            onExit = function()
                inFingerprint = false
                inPrompt = false
                lib.hideTextUI()
            end
        })
    end

    -- Helicopter
    for _, v in pairs(Config.Locations.helicopter) do
        lib.zones.box({
            coords = v,
            size = vec3(4, 4, 4),
            rotation = 0.0,
            onEnter = function()
                inHelicopter = true
                inPrompt = true
                if PlayerData.job.onduty then
                    uiPrompt('heli')
                    if cache.vehicle then
                        lib.showTextUI(Lang:t('info.store_heli'))
                    else
                        lib.showTextUI(Lang:t('info.take_heli'))
                    end
                end
            end,
            onExit = function()
                inHelicopter = false
                inPrompt = false
                lib.hideTextUI()
            end
        })
    end

    -- Police Impound
    for k, v in pairs(Config.Locations.impound) do
        lib.zones.box({
            coords = v,
            size = vec3(2, 2, 2),
            rotation = 0.0,
            onEnter = function()
                inImpound = true
                inPrompt = true
                currentGarage = k
                if PlayerData.job.onduty then
                    if cache.vehicle then
                        lib.showTextUI(Lang:t('info.impound_veh'))
                        uiPrompt('impound')
                    else
                        lib.showTextUI('menu.pol_impound')
                        uiPrompt('impound')
                    end
                end
            end,
            onExit = function()
                inImpound = false
                inPrompt = false
                lib.hideTextUI()
                currentGarage = 0
            end
        })
    end

    -- Police Garage
    for k, v in pairs(Config.Locations.vehicle) do
        lib.zones.box({
            coords = v,
            size = vec3(2, 2, 2),
            rotation = 0.0,
            onEnter = function()
                if PlayerData.job.onduty and PlayerData.job.type == 'leo' then
                    inGarage = true
                    inPrompt = true
                    currentGarage = k
                    if cache.vehicle then
                        lib.showTextUI(Lang:t('info.store_veh'))
                    else
                        lib.showTextUI('[E] - Vehicle Garage')
                    end
                    uiPrompt('garage')
                end
            end,
            onExit = function()
                inGarage = false
                inPrompt = false
                lib.hideTextUI()
            end
        })
    end
end)
