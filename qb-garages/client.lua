--  
-- 
-- 
--                                                                          
-- 
-- 
-- 
--                                                                          
-- 
-- 
-- 
--                                                                          
-- 
-- 
-- 
--                                                                          
-- 
-- 
-- 
--                                                                          
-- 
-- 
-- 
--                                                                          
-- 
-- 
-- 
--                                                                          
-- 
-- 
-- 
--                                                                          
-- 
-- 
-- 
--                                                                          
-- 
-- 
-- 
--                                                                          
-- 
-- 
-- 
--                                                                          
-- 
-- 
-- 
--                                                                          
-- 
-- 
-- 
--                                                                          
-- 
--             

local QBCore = exports['qb-core']:GetCoreObject()
local PlayerData = {}
local currentGarage = nil
local inGarageStation = false
local isMenuOpen = false
local currentVehicleData = nil
local isPlayerLoaded = false
local sharedGaragesData = {}
local pendingJoinRequests = {}
local isHoveringVehicle = false
local hoveredVehicle = nil
local lastHoveredVehicle = nil
local vehicleHoverInfo = nil
local hoveredNetId = nil
local isGarageMenuOpen = false
local isVehicleFaded = false
local fadedVehicle = nil
local parkingPromptShown = false
local canStoreVehicle = false
local isStorageInProgress = false
local vehicleOwnershipCache = {}
local optimalParkingDistance = 12.0
local isTransferringVehicle = false
local transferAnimationActive = false
local currentTransferVehicle = nil
local isAtImpoundLot = false
local currentImpoundLot = nil
local impoundBlips = {}
local lastGarageCheckTime = nil
local lastGarageId = nil
local lastGarageType = nil
local lastGarageCoords = nil
local lastGarageDist = nil
local activeConfirmation = nil
local activeAnimations = {}
local parkedJobVehicles = {}
local occupiedParkingSpots = {}
local jobParkingSpots = {}
local occupiedParkingSpots = {}


RegisterNetEvent('QBCore:Client:OnPlayerLoaded', function()
    PlayerData = QBCore.Functions.GetPlayerData()
end)

RegisterNetEvent('QBCore:Client:OnPlayerLoaded', function()
    PlayerData = QBCore.Functions.GetPlayerData()
    isPlayerLoaded = true
end)

AddEventHandler('onResourceStart', function(resourceName)
    if GetCurrentResourceName() ~= resourceName then return end
    
    Wait(1000)
    
    if LocalPlayer.state.isLoggedIn then
        PlayerData = QBCore.Functions.GetPlayerData()
        isPlayerLoaded = true
    end
end)

RegisterNetEvent('QBCore:Player:SetPlayerData', function(data)
    PlayerData = data
end)

RegisterNetEvent('QBCore:Client:OnJobUpdate', function(JobInfo)
    PlayerData.job = JobInfo
end)

RegisterNetEvent('QBCore:Client:OnGangUpdate', function(GangInfo)
    PlayerData.gang = GangInfo
end)

CreateThread(function()
    if Config.GarageBlip.Enable then
        for k, v in pairs(Config.Garages) do
            local blip = AddBlipForCoord(v.coords.x, v.coords.y, v.coords.z)
            SetBlipSprite(blip, Config.GarageBlip.Sprite)
            SetBlipDisplay(blip, Config.GarageBlip.Display)
            SetBlipScale(blip, Config.GarageBlip.Scale)
            SetBlipAsShortRange(blip, Config.GarageBlip.ShortRange)
            SetBlipColour(blip, Config.GarageBlip.Color)
            BeginTextCommandSetBlipName("STRING")
            AddTextComponentSubstringPlayerName(v.label)
            EndTextCommandSetBlipName(blip)
        end
        
        -- Job garages
        for k, v in pairs(Config.JobGarages) do
            local blip = AddBlipForCoord(v.coords.x, v.coords.y, v.coords.z)
            SetBlipSprite(blip, Config.GarageBlip.Sprite)
            SetBlipDisplay(blip, Config.GarageBlip.Display)
            SetBlipScale(blip, Config.GarageBlip.Scale)
            SetBlipAsShortRange(blip, Config.GarageBlip.ShortRange)
            SetBlipColour(blip, 38) -- Different color for job garages
            BeginTextCommandSetBlipName("STRING")
            AddTextComponentSubstringPlayerName(v.label)
            EndTextCommandSetBlipName(blip)
        end
        
        -- Gang garages
        for k, v in pairs(Config.GangGarages) do
            local blip = AddBlipForCoord(v.coords.x, v.coords.y, v.coords.z)
            SetBlipSprite(blip, Config.GarageBlip.Sprite)
            SetBlipDisplay(blip, Config.GarageBlip.Display)
            SetBlipScale(blip, Config.GarageBlip.Scale)
            SetBlipAsShortRange(blip, Config.GarageBlip.ShortRange)
            SetBlipColour(blip, 59) -- Different color for gang garages
            BeginTextCommandSetBlipName("STRING")
            AddTextComponentSubstringPlayerName(v.label)
            EndTextCommandSetBlipName(blip)
        end
    end
end)

-- Find an available parking spot for a job
function FindJobParkingSpot(jobName)
    local spotsList = nil
    
    if Config.JobParkingSpots[jobName] then
        spotsList = Config.JobParkingSpots[jobName]
    else
        for k, v in pairs(Config.JobGarages) do
            if v.job == jobName then
                if v.spawnPoints then
                    spotsList = v.spawnPoints
                elseif v.spawnPoint then
                    spotsList = {v.spawnPoint}
                end
                break
            end
        end
    end
    
    if not spotsList or #spotsList == 0 then
        return nil
    end
    
    if not occupiedParkingSpots[jobName] then
        occupiedParkingSpots[jobName] = {}
        
        local vehicles = GetGamePool('CVehicle')
        for _, veh in ipairs(vehicles) do
            local vehCoords = GetEntityCoords(veh)
            
            for i, spot in ipairs(spotsList) do
                local spotCoords = vector3(spot.x, spot.y, spot.z)
                if #(vehCoords - spotCoords) < 3.0 then
                    occupiedParkingSpots[jobName][i] = true
                    break
                end
            end
        end
    end
    
    for i, spot in ipairs(spotsList) do
        if not occupiedParkingSpots[jobName][i] then
            return i, spot
        end
    end
    
    return nil
end

-- Mark a spot as occupied or free
function SetParkingSpotState(jobName, spotIndex, isOccupied)
    if not occupiedParkingSpots[jobName] then
        occupiedParkingSpots[jobName] = {}
    end
    
    occupiedParkingSpots[jobName][spotIndex] = isOccupied
end

-- Simplified smooth animation for parking job vehicles
function ParkJobVehicle(vehicle, jobName)
    if not DoesEntityExist(vehicle) then return false end
    if not jobName then return false end
    
    local parkingSpots = Config.JobParkingSpots[jobName]
    if not parkingSpots or #parkingSpots == 0 then
        QBCore.Functions.Notify("No parking spots found", "error")
        return false
    end
    
    local foundSpot = nil
    for _, spot in ipairs(parkingSpots) do
        local occupied = false
        local spotCoords = vector3(spot.x, spot.y, spot.z)
        
        local vehicles = GetGamePool('CVehicle')
        for _, veh in ipairs(vehicles) do
            if veh ~= vehicle and DoesEntityExist(veh) then
                local vehCoords = GetEntityCoords(veh)
                if #(vehCoords - spotCoords) < 2.5 then
                    occupied = true
                    break
                end
            end
        end
        
        if not occupied then
            foundSpot = spot
            break
        end
    end
    
    if not foundSpot then
        QBCore.Functions.Notify("All parking spots are occupied", "error")
        return false
    end
    
    local plate = QBCore.Functions.GetPlate(vehicle)
    local props = QBCore.Functions.GetVehicleProperties(vehicle)
    local engineHealth = GetVehicleEngineHealth(vehicle)
    local bodyHealth = GetVehicleBodyHealth(vehicle)
    local fuelLevel = exports['cdn-fuel']:GetFuel(vehicle)
    
    SetEntityAsMissionEntity(vehicle, true, true)
    
    QBCore.Functions.Notify("Parking vehicle...", "primary")
    
    local initialVehicleCoords = GetEntityCoords(vehicle)
    local initialHeading = GetEntityHeading(vehicle)
    
    local spotCoords = vector3(foundSpot.x, foundSpot.y, foundSpot.z)
    local finalHeading = foundSpot.w
    
    SetEntityCollision(vehicle, false, false)
    SetEntityAlpha(vehicle, 200, false)
    
    local moveDuration = 2000
    local startTime = GetGameTimer()
    
    CreateThread(function()
        while GetGameTimer() - startTime < moveDuration do
            local progress = (GetGameTimer() - startTime) / moveDuration
            local currentX = Lerp(initialVehicleCoords.x, spotCoords.x, progress)
            local currentY = Lerp(initialVehicleCoords.y, spotCoords.y, progress)
            local currentZ = Lerp(initialVehicleCoords.z, spotCoords.z, progress)
            local currentHeading = Lerp(initialHeading, finalHeading, progress)
            
            SetEntityCoordsNoOffset(vehicle, currentX, currentY, currentZ, false, false, false)
            SetEntityHeading(vehicle, currentHeading)
            Wait(0)
        end
        
        SetEntityCoordsNoOffset(vehicle, spotCoords.x, spotCoords.y, spotCoords.z, false, false, false)
        SetEntityHeading(vehicle, finalHeading)
        
        SetEntityCollision(vehicle, true, true)
        SetEntityAlpha(vehicle, 255, false)
        
        SetVehicleDoorsLocked(vehicle, 1)
        SetVehicleEngineOn(vehicle, false, true, true)
        SetVehicleEngineHealth(vehicle, engineHealth)
        SetVehicleBodyHealth(vehicle, bodyHealth)
        exports['cdn-fuel']:SetFuel(vehicle, fuelLevel)
        
        TriggerServerEvent('qb-garages:server:TrackJobVehicle', plate, jobName, props)
        
        QBCore.Functions.Notify("Vehicle parked successfully", "success")
    end)
    
    return true
end

function Lerp(a, b, t)
    return a + (b - a) * t
end

function GetClosestRoad(x, y, z, radius, oneSideOfRoad, allowJunctions)
    local outPosition = vector3(0.0, 0.0, 0.0)
    local outHeading = 0.0
    
    if GetClosestVehicleNode(x, y, z, outPosition, outHeading, 1, 3.0, 0) then
        return outPosition
    end
    
    return nil
end

function ShowConfirmDialog(title, message, onYes, onNo)
    activeConfirmation = {
        yesCallback = onYes,
        noCallback = onNo
    }
    
    -- Creating a beautiful scaleform dialog
    local scaleform = RequestScaleformMovie("mp_big_message_freemode")
    while not HasScaleformMovieLoaded(scaleform) do
        Wait(0)
    end
    
    BeginScaleformMovieMethod(scaleform, "SHOW_SHARD_WASTED_MP_MESSAGE")
    ScaleformMovieMethodAddParamTextureNameString(title)
    ScaleformMovieMethodAddParamTextureNameString(message)
    ScaleformMovieMethodAddParamInt(5)
    EndScaleformMovieMethod()
    
    -- Controls display
    local key_Y = 246 -- Y
    local key_N = 306 -- N
    
    CreateThread(function()
        local startTime = GetGameTimer()
        local showing = true
        
        while showing do
            Wait(0)
            
            -- Display scaleform
            DrawScaleformMovieFullscreen(scaleform, 255, 255, 255, 255, 0)
            
            -- Display help text
            BeginTextCommandDisplayHelp("STRING")
            AddTextComponentSubstringPlayerName("Press ~INPUT_REPLAY_START_STOP_RECORDING~ for YES or ~INPUT_REPLAY_SCREENSHOT~ for NO")
            EndTextCommandDisplayHelp(0, false, true, -1)
            
            -- Check for key presses
            if IsControlJustPressed(0, key_Y) then
                showing = false
                if activeConfirmation and activeConfirmation.yesCallback then
                    activeConfirmation.yesCallback()
                end
            elseif IsControlJustPressed(0, key_N) then
                showing = false
                if activeConfirmation and activeConfirmation.noCallback then
                    activeConfirmation.noCallback()
                end
            end
            
            -- Timeout after 15 seconds (default to NO)
            if GetGameTimer() - startTime > 15000 then
                showing = false
                if activeConfirmation and activeConfirmation.noCallback then
                    activeConfirmation.noCallback()
                end
            end
        end
        
        -- Clean up
        SetScaleformMovieAsNoLongerNeeded(scaleform)
        activeConfirmation = nil
    end)
end

RegisterNetEvent('qb-garages:client:DeleteGarage')
AddEventHandler('qb-garages:client:DeleteGarage', function(garageId)
    -- Simply forward to server
    TriggerServerEvent('qb-garages:server:DeleteSharedGarage', garageId)
end)

-- Register NUI callbacks for confirmation dialogs
RegisterNUICallback('confirmRemoveVehicle', function(data, cb)
    local plate = data.plate
    
    -- Close NUI focus from the garage interface first
    SetNuiFocus(false, false)
    
    -- Wait a small moment before opening the menu
    Wait(100)
    
    -- Create menu options
    local removeMenu = {
        {
            header = "Remove Vehicle",
            isMenuHeader = true
        },
        {
            header = "Are you sure?",
            txt = "Remove this vehicle from the shared garage?",
            isMenuHeader = true
        },
        {
            header = "Yes, remove vehicle",
            txt = "The vehicle will be returned to your main garage",
            params = {
                isServer = true,
                event = "qb-garages:server:RemoveVehicleFromSharedGarage",
                args = {
                    plate = plate
                }
            }
        },
        {
            header = "No, cancel",
            txt = "Keep vehicle in shared garage",
            params = {
                event = ""
            }
        },
    }
    
    -- Open menu with QB-Menu
    exports['qb-menu']:openMenu(removeMenu)
    
    -- Always return success - we'll handle actual removal through server event
    cb({status = "success"})
end)

RegisterNetEvent('qb-garages:client:ConfirmDeleteGarage', function(data)
    TriggerServerEvent('qb-garages:server:DeleteSharedGarage', data.garageId)
    
    -- Execute callback with confirmation
    if callbackRegistry[data.callback] then
        callbackRegistry[data.callback](true)
        callbackRegistry[data.callback] = nil
    end
    
    -- Close NUI focus
    SetNuiFocus(false, false)
end)

RegisterNetEvent('qb-garages:client:CancelDeleteGarage')
AddEventHandler('qb-garages:client:CancelDeleteGarage', function()
    -- Do nothing, just catch the event
end)


RegisterNetEvent('qb-garages:client:ConfirmRemoveVehicle', function(data)
    TriggerServerEvent('qb-garages:server:RemoveVehicleFromSharedGarage', data.plate)
    
    -- Execute callback with confirmation
    if callbackRegistry[data.callback] then
        callbackRegistry[data.callback](true)
        callbackRegistry[data.callback] = nil
    end
    
    -- Close NUI focus
    SetNuiFocus(false, false)
end)

RegisterNetEvent('qb-garages:client:CancelRemoveVehicle', function(data)
    -- Execute callback with cancellation
    if callbackRegistry[data.callback] then
        callbackRegistry[data.callback](false)
        callbackRegistry[data.callback] = nil
    end
    
    -- Close NUI focus
    SetNuiFocus(false, false)
end)

-- Callback registry for menu responses
callbackRegistry = {}

RegisterNUICallback('confirmDeleteGarage', function(data, cb)
    local garageId = data.garageId
    
    -- Create menu but don't close NUI first
    exports['qb-menu']:openMenu({
        {
            header = "Confirm Deletion",
            isMenuHeader = true
        },
        {
            header = "Delete Garage",
            txt = "All vehicles will be returned to owners",
            params = {
                event = "qb-garages:client:ConfirmDeleteSharedGarage",
                args = {
                    garageId = garageId
                }
            }
        },
        {
            header = "Cancel",
            txt = "Keep this garage",
            params = {
                event = "qb-garages:client:CancelDeleteGarage"
            }
        }
    })
    
    -- Return success to keep UI active
    cb({status = "success"})
end)

RegisterNetEvent('qb-garages:client:ConfirmDeleteSharedGarage')
AddEventHandler('qb-garages:client:ConfirmDeleteSharedGarage', function(data)
    local garageId = data.garageId
    
    -- Delete the garage on the server
    TriggerServerEvent('qb-garages:server:DeleteSharedGarage', garageId)
    
    -- Notify the UI that the deletion was successful
    SendNUIMessage({
        action = "garageDeleted",
        garageId = garageId
    })
end)

RegisterNUICallback('closeSharedGarageMenu', function(data, cb)
    SetNuiFocus(false, false)
    cb({status = "success"})
end)

function AnimateVehicleFade(vehicle, fromAlpha, toAlpha, duration, callback)
    if not DoesEntityExist(vehicle) then 
        if callback then callback() end
        return 
    end
    
    -- Cancel any existing animation for this vehicle
    if activeAnimations[vehicle] then
        activeAnimations[vehicle] = nil
    end
    
    local startTime = GetGameTimer()
    local endTime = startTime + duration
    local animationId = math.random(1, 100000) -- Unique ID for this animation
    
    activeAnimations[vehicle] = animationId
    
    CreateThread(function()
        while GetGameTimer() < endTime and DoesEntityExist(vehicle) and activeAnimations[vehicle] == animationId do
            local progress = (GetGameTimer() - startTime) / duration
            local currentAlpha = math.floor(fromAlpha + (toAlpha - fromAlpha) * progress)
            
            -- Apply alpha to vehicle and attached entities
            SetEntityAlpha(vehicle, currentAlpha, false)
            
            local attachedEntities = GetAllAttachedEntities(vehicle)
            for _, attached in ipairs(attachedEntities) do
                SetEntityAlpha(attached, currentAlpha, false)
            end
            
            Wait(10) -- Update frequently for smooth animation
        end
        
        -- Ensure final alpha is set correctly if animation completes
        if DoesEntityExist(vehicle) and activeAnimations[vehicle] == animationId then
            SetEntityAlpha(vehicle, toAlpha, false)
            
            local attachedEntities = GetAllAttachedEntities(vehicle)
            for _, attached in ipairs(attachedEntities) do
                SetEntityAlpha(attached, toAlpha, false)
            end
            
            activeAnimations[vehicle] = nil
            
            if callback then callback() end
        end
    end)
end

function AnimateVehicleMove(vehicle, toCoords, toHeading, duration, callback)
    if not DoesEntityExist(vehicle) then 
        if callback then callback() end
        return 
    end
    
    local startCoords = GetEntityCoords(vehicle)
    local startHeading = GetEntityHeading(vehicle)
    local startTime = GetGameTimer()
    local endTime = startTime + duration
    local animationId = math.random(1, 100000) -- Unique ID for this animation
    
    -- Register animation
    activeAnimations[vehicle] = animationId
    
    -- Ensure vehicle can be moved
    NetworkRequestControlOfEntity(vehicle)
    SetEntityAsMissionEntity(vehicle, true, true)
    SetEntityInvincible(vehicle, true)
    SetVehicleDoorsLocked(vehicle, 4) -- Lock doors during animation
    FreezeEntityPosition(vehicle, false)
    
    CreateThread(function()
        while GetGameTimer() < endTime and DoesEntityExist(vehicle) and activeAnimations[vehicle] == animationId do
            local progress = (GetGameTimer() - startTime) / duration
            local currentX = startCoords.x + (toCoords.x - startCoords.x) * progress
            local currentY = startCoords.y + (toCoords.y - startCoords.y) * progress
            local currentZ = startCoords.z + (toCoords.z - startCoords.z) * progress
            local currentHeading = startHeading + (toHeading - startHeading) * progress
            
            -- Smoothly update position and heading
            SetEntityCoordsNoOffset(vehicle, currentX, currentY, currentZ, false, false, false)
            SetEntityHeading(vehicle, currentHeading)
            
            Wait(0) -- Update every frame for smooth movement
        end
        
        -- Ensure final position is set correctly
        if DoesEntityExist(vehicle) and activeAnimations[vehicle] == animationId then
            SetEntityCoordsNoOffset(vehicle, toCoords.x, toCoords.y, toCoords.z, false, false, false)
            SetEntityHeading(vehicle, toHeading)
            
            activeAnimations[vehicle] = nil
            
            -- Reset vehicle state
            SetEntityInvincible(vehicle, false)
            SetVehicleDoorsLocked(vehicle, 1) -- Unlock but only for job members
            
            if callback then callback() end
        end
    end)
end

function InitializeJobParkingSpots()
    for garageId, garageConfig in pairs(Config.JobGarages) do
        local jobName = garageConfig.job
        
        -- If the garage doesn't already have predefined spots in our table
        if not jobParkingSpots[jobName] then
            -- Create parking spots array for this job
            jobParkingSpots[jobName] = {}
            
            -- If we have spawnPoints, use those coordinates for parking spots
            if garageConfig.spawnPoints and #garageConfig.spawnPoints > 0 then
                for _, spot in ipairs(garageConfig.spawnPoints) do
                    table.insert(jobParkingSpots[jobName], spot)
                end
            -- Otherwise, use the single spawnPoint if available
            elseif garageConfig.spawnPoint then
                table.insert(jobParkingSpots[jobName], garageConfig.spawnPoint)
            end
        end
    end
end

-- Call this on resource start
Citizen.CreateThread(function()
    Wait(1000) -- Wait for config to be loaded
    InitializeJobParkingSpots()
end)

function FindAvailableParkingSpot(jobName, currentVehicle)
    if not jobName then return nil end
    
    local parkingSpots = nil
    if Config.JobParkingSpots[jobName] then
        parkingSpots = Config.JobParkingSpots[jobName]
    else
        for k, v in pairs(Config.JobGarages) do
            if v.job == jobName then
                if v.spawnPoints then
                    parkingSpots = v.spawnPoints
                elseif v.spawnPoint then
                    parkingSpots = {v.spawnPoint}
                end
                break
            end
        end
    end
    
    if not parkingSpots or #parkingSpots == 0 then return nil end
    
    local allVehicles = GetGamePool('CVehicle')
    local occupiedSpots = {}
    
    for _, veh in ipairs(allVehicles) do
        if veh ~= currentVehicle and DoesEntityExist(veh) then
            local vehCoords = GetEntityCoords(veh)
            
            for spotIndex, spot in ipairs(parkingSpots) do
                local spotCoords = vector3(spot.x, spot.y, spot.z)
                if #(vehCoords - spotCoords) < 3.0 then
                    occupiedSpots[spotIndex] = true
                    break
                end
            end
        end
    end
    
    for spotIndex, spot in ipairs(parkingSpots) do
        if not occupiedSpots[spotIndex] then
            local spotCoords = vector3(spot.x, spot.y, spot.z)
            local _, _, _, _, entityHit = GetShapeTestResult(
                StartShapeTestBox(
                    spotCoords.x, spotCoords.y, spotCoords.z,
                    5.0, 2.5, 2.5,
                    0.0, 0.0, 0.0,
                    0, 2, currentVehicle, 4
                )
            )
            
            if not entityHit or entityHit == 0 then
                return spot
            end
        end
    end
    
    return nil
end


function IsJobVehicle(vehicle)
    if not DoesEntityExist(vehicle) then return false end
    
    local plate = QBCore.Functions.GetPlate(vehicle)
    if not plate then return false end
    
    -- Check for job vehicle pattern in plate
    if string.sub(plate, 1, 3) == "JOB" then
        return true
    end
    
    -- If not identified by plate, check by model against job vehicle configs
    local model = GetEntityModel(vehicle)
    local modelName = string.lower(GetDisplayNameFromVehicleModel(model))
    
    for jobName, jobGarage in pairs(Config.JobGarages) do
        if jobGarage.vehicles then
            for vehicleModel, vehicleInfo in pairs(jobGarage.vehicles) do
                if string.lower(vehicleModel) == modelName then
                    return true, jobName
                end
            end
        end
    end
    
    return false
end

function DoesPlayerJobMatchVehicleJob(vehicle)
    if not DoesEntityExist(vehicle) then return false end
    if not PlayerData.job then return false end
    
    local jobName = PlayerData.job.name
    if not jobName then return false end
    
    local isJobVehicle, vehicleJobName = IsJobVehicle(vehicle)
    if not isJobVehicle then return false end
    
    -- If we couldn't determine the specific job, check all job garages
    if not vehicleJobName then
        local model = GetEntityModel(vehicle)
        local modelName = string.lower(GetDisplayNameFromVehicleModel(model))
        
        for k, v in pairs(Config.JobGarages) do
            if v.job == jobName and v.vehicles then
                for vehModel, _ in pairs(v.vehicles) do
                    if string.lower(vehModel) == modelName then
                        return true
                    end
                end
            end
        end
        return false
    end
    
    return vehicleJobName == jobName
end

function FindJobVehicleParkingSpot(jobName)
    if not jobName then return nil end
    
    local jobGarage = nil
    for k, v in pairs(Config.JobGarages) do
        if v.job == jobName then
            jobGarage = v
            break
        end
    end
    
    if not jobGarage then return nil end
    
    -- Use spawn points as parking spots
    local parkingSpots = nil
    if jobGarage.spawnPoints then
        parkingSpots = jobGarage.spawnPoints
    else
        parkingSpots = {jobGarage.spawnPoint}
    end
    
    -- Find an empty spot
    for _, spot in ipairs(parkingSpots) do
        local spotCoords = vector3(spot.x, spot.y, spot.z)
        local heading = spot.w
        local clear = true
        
        -- Check if spot is clear
        local radius = 2.5
        local vehicles = GetGamePool('CVehicle')
        for i = 1, #vehicles do
            local vehCoords = GetEntityCoords(vehicles[i])
            if #(vehCoords - spotCoords) < radius then
                clear = false
                break
            end
        end
        
        if clear then
            return spotCoords, heading
        end
    end
    
    return nil
end


RegisterNUICallback('getJobVehicles', function(data, cb)
    local job = data.job
    if not job then
        cb({ jobVehicles = {} })
        return
    end
    
    local jobVehicles = {}
    
    for k, garage in pairs(Config.JobGarages) do
        if garage.job == job then
            local i = 1
            for model, vehicle in pairs(garage.vehicles) do
                table.insert(jobVehicles, {
                    id = i,
                    model = model,
                    name = vehicle.label,
                    fuel = 100,
                    engine = 100,
                    body = 100,
                    state = 1,
                    stored = true,
                    isJobVehicle = true,
                    icon = vehicle.icon or "🚗"
                })
                i = i + 1
            end
            break
        end
    end
    
    cb({ jobVehicles = jobVehicles })
end)

RegisterNUICallback('takeOutJobVehicle', function(data, cb)
    local model = data.model
    
    if not model then
        cb({status = "error", message = "Invalid model"})
        return
    end
    
    local job = PlayerData.job.name
    if not job then
        cb({status = "error", message = "No job found"})
        return
    end
    
    local garageInfo = nil
    for k, v in pairs(Config.JobGarages) do
        if v.job == job then
            garageInfo = v
            break
        end
    end
    
    if not garageInfo then
        cb({status = "error", message = "Job garage not found"})
        return
    end
    
    local spawnPoints = nil
    if garageInfo.spawnPoints then
        spawnPoints = garageInfo.spawnPoints
    else
        spawnPoints = {garageInfo.spawnPoint}
    end
    
    local clearPoint = FindClearSpawnPoint(spawnPoints)
    if not clearPoint then
        cb({status = "error", message = "All spawn locations are blocked!"})
        return
    end
    
    local spawnCoords = vector3(clearPoint.x, clearPoint.y, clearPoint.z)
    QBCore.Functions.SpawnVehicle(model, function(veh)
        if not veh or veh == 0 then
            QBCore.Functions.Notify("Error creating job vehicle. Please try again.", "error")
            cb({status = "error", message = "Failed to spawn vehicle"})
            return
        end
        
        SetEntityHeading(veh, clearPoint.w)
        exports['cdn-fuel']:SetFuel(veh, 100)
        
        FadeInVehicle(veh)
        
        SetVehicleEngineHealth(veh, 1000.0)
        SetVehicleBodyHealth(veh, 1000.0)
        SetVehicleDirtLevel(veh, 0.0) 
        SetVehicleUndriveable(veh, false)
        SetVehicleEngineOn(veh, true, true, false)
        
        FixEngineSmoke(veh)
        
        QBCore.Functions.Notify("Job vehicle taken out", "success")
        TriggerEvent('vehiclekeys:client:SetOwner', QBCore.Functions.GetPlate(veh))
        cb({status = "success"})
    end, spawnCoords, true)
    
    SetNuiFocus(false, false)
    isMenuOpen = false
end)

RegisterNUICallback('refreshVehicles', function(data, cb)
    local garageId = data.garageId
    local garageType = data.garageType
    
    if garageType == "public" then
        QBCore.Functions.TriggerCallback('qb-garages:server:GetPersonalVehicles', function(vehicles)
            if vehicles then
                SendNUIMessage({
                    action = "refreshVehicles",
                    vehicles = FormatVehiclesForNUI(vehicles)
                })
            end
        end, garageId)
    elseif garageType == "gang" then
        local gang = PlayerData.gang.name
        QBCore.Functions.TriggerCallback('qb-garages:server:GetGangVehicles', function(vehicles)
            if vehicles then
                SendNUIMessage({
                    action = "refreshVehicles",
                    vehicles = FormatVehiclesForNUI(vehicles)
                })
            end
        end, gang, garageId)
    elseif garageType == "shared" then
        QBCore.Functions.TriggerCallback('qb-garages:server:GetSharedGarageVehicles', function(vehicles)
            if vehicles then
                SendNUIMessage({
                    action = "refreshVehicles",
                    vehicles = FormatVehiclesForNUI(vehicles)
                })
            end
        end, garageId)
    elseif garageType == "impound" then
        QBCore.Functions.TriggerCallback('qb-garages:server:GetImpoundedVehicles', function(vehicles)
            if vehicles then
                SendNUIMessage({
                    action = "refreshVehicles",
                    vehicles = FormatVehiclesForNUI(vehicles)
                })
            end
        end)
    end
    
    cb({status = "refreshing"})
end)

-- Replace the FormatVehiclesForNUI function in client.lua (around line 1330)
function FormatVehiclesForNUI(vehicles)
    local formattedVehicles = {}
    local currentGarageId = currentGarage and currentGarage.id or nil    
    for i, vehicle in ipairs(vehicles) do
        local vehicleInfo = QBCore.Shared.Vehicles[vehicle.vehicle]
        if vehicleInfo then
            local enginePercent = round(vehicle.engine / 10, 1)
            local bodyPercent = round(vehicle.body / 10, 1)
            local fuelPercent = vehicle.fuel or 100
            
            local displayName = vehicleInfo.name
            if vehicle.custom_name and vehicle.custom_name ~= "" then
                displayName = vehicle.custom_name
            end
            
            local isInCurrentGarage = false
            if currentGarage and currentGarage.type == "job" then
                isInCurrentGarage = true
            elseif currentGarage and currentGarage.type == "shared" then
                -- For shared garages, check if vehicle is in THIS shared garage
                isInCurrentGarage = (vehicle.shared_garage_id and tostring(vehicle.shared_garage_id) == tostring(currentGarageId))
            else
                if vehicle.garage and currentGarageId then
                    isInCurrentGarage = (vehicle.garage == currentGarageId)
                end
            end
            
            local impoundFee = nil
            local impoundReason = nil
            local impoundedBy = nil
            local daysImpounded = nil
            
            if vehicle.state == 2 then
                impoundFee = Config.ImpoundFee  
                
                if vehicle.impoundfee ~= nil then
                    local customFee = tonumber(vehicle.impoundfee)
                    if customFee and customFee > 0 then
                        impoundFee = customFee
                    end
                end
                
                impoundReason = vehicle.impoundreason or "No reason specified"
                impoundedBy = vehicle.impoundedby or "Unknown Officer"
                daysImpounded = 1
            end
            
            -- IMPORTANT: Properly handle state for shared vehicles
            local isStored = vehicle.state == 1
            local isOut = vehicle.state == 0
            
            -- For shared garage vehicles, check if they're really stored in THIS garage
            if currentGarage and currentGarage.type == "shared" then
                if vehicle.shared_garage_id and tostring(vehicle.shared_garage_id) == tostring(currentGarageId) then
                    -- Vehicle belongs to this shared garage
                    isStored = (vehicle.state == 1)
                    isOut = (vehicle.state == 0)
                else
                    -- Vehicle doesn't belong to this shared garage, skip it
                    goto continue
                end
            end
            
            -- Include ALL vehicles
            table.insert(formattedVehicles, {
                id = i,
                plate = vehicle.plate,
                model = vehicle.vehicle,
                name = displayName,
                fuel = fuelPercent,
                engine = enginePercent,
                body = bodyPercent,
                state = vehicle.state,
                garage = vehicle.garage or "Unknown", 
                stored = isStored,
                isOut = isOut,
                inCurrentGarage = isInCurrentGarage,
                isFavorite = vehicle.is_favorite == 1,
                owner = vehicle.citizenid,
                ownerName = vehicle.owner_name,
                storedInGang = vehicle.stored_in_gang,
                storedInShared = vehicle.shared_garage_id ~= nil,
                sharedGarageId = vehicle.shared_garage_id,
                currentGarage = currentGarageId,
                impoundFee = impoundFee,
                impoundReason = impoundReason,
                impoundedBy = impoundedBy,
                daysImpounded = daysImpounded,
                impoundType = vehicle.impoundtype
            })
            
            ::continue::
        end
    end
    
    return formattedVehicles
end

Citizen.CreateThread(function()
    -- Wait for QBCore to be fully loaded
    while QBCore == nil do
        Wait(0)
    end
    
    -- Store the original DeleteVehicle function
    local originalDeleteVehicle = QBCore.Functions.DeleteVehicle
    
    -- Override the function to include our impound logic
    QBCore.Functions.DeleteVehicle = function(vehicle)
        if DoesEntityExist(vehicle) then
            -- Get vehicle info before deleting
            local netId = NetworkGetNetworkIdFromEntity(vehicle)
            
            -- Trigger our server event to handle impound
            TriggerServerEvent('QBCore:Server:DeleteVehicle', netId)
            
            -- Call the original function to actually delete the vehicle
            return originalDeleteVehicle(vehicle)
        end
    end
end)

Citizen.CreateThread(function()
    -- Keep track of existing vehicles to detect deletions
    local trackedVehicles = {}
    
    while true do
        Wait(1000) -- Check every second
        
        -- Get all current vehicles in the game world
        local vehicles = GetGamePool('CVehicle')
        local currentVehicles = {}
        
        -- Mark all existing vehicles
        for _, vehicle in pairs(vehicles) do
            if DoesEntityExist(vehicle) then
                local plate = QBCore.Functions.GetPlate(vehicle)
                if plate then
                    currentVehicles[plate] = true
                end
            end
        end
        
        -- Check if any previously tracked vehicles are now missing
        for plate, _ in pairs(trackedVehicles) do
            if not currentVehicles[plate] then
                -- Vehicle has disappeared - trigger impound logic
                TriggerServerEvent('qb-garages:server:HandleDeletedVehicle', plate)
                trackedVehicles[plate] = nil
            end
        end
        
        -- Update tracking list
        trackedVehicles = currentVehicles
    end
end)

-- In client.lua
RegisterNetEvent('QBCore:Command:DeleteVehicle', function()
    local ped = PlayerPedId()
    local veh = GetVehiclePedIsIn(ped, false)
    
    if veh ~= 0 then
        -- Get plate before vehicle is deleted
        local plate = QBCore.Functions.GetPlate(veh)
        if plate then
            -- Send plate to server to update database
            TriggerServerEvent('qb-garages:server:HandleDeletedVehicle', plate)
        end
    else
        -- Look for nearby vehicles
        local coords = GetEntityCoords(ped)
        local vehicles = GetGamePool('CVehicle')
        for _, v in pairs(vehicles) do
            if #(coords - GetEntityCoords(v)) <= 5.0 then
                local plate = QBCore.Functions.GetPlate(v)
                if plate then
                    -- Send plate to server to update database
                    TriggerServerEvent('qb-garages:server:HandleDeletedVehicle', plate)
                end
            end
        end
    end
end)

RegisterNUICallback('checkVehicleState', function(data, cb)
    local plate = data.plate
    
    if not plate then
        cb({state = 1}) -- Default to in-garage if no plate
        return
    end
    
    -- Always get the latest state from the server
    QBCore.Functions.TriggerCallback('qb-garages:server:CheckVehicleStatus', function(isStored)
        if isStored then
            cb({state = 1}) -- Vehicle is in garage
        else
            cb({state = 0}) -- Vehicle is out
        end
    end, plate)
end)

RegisterNUICallback('refreshImpoundVehicles', function(data, cb)
    
    QBCore.Functions.TriggerCallback('qb-garages:server:GetImpoundedVehicles', function(vehicles)
        if vehicles then            
            for i, vehicle in ipairs(vehicles) do
                Wait (100)
            end
            
            local formattedVehicles = FormatVehiclesForNUI(vehicles)            
            SendNUIMessage({
                action = "refreshVehicles",
                vehicles = formattedVehicles
            })
        else
            SendNUIMessage({
                action = "refreshVehicles",
                vehicles = {}
            })
        end
    end)
    
    cb({status = "refreshing"})
end)

RegisterCommand('debuggarage', function(source, args)
    local garageId = args[1] or (currentGarage and currentGarage.id or "unknown")
    
    QBCore.Functions.TriggerCallback('qb-garages:server:GetJobGarageVehicles', function(vehicles)        
        for i, v in ipairs(vehicles) do
            Wait (100)
        end
        local formatted = FormatVehiclesForNUI(vehicles)
        
        local currentGarageTest = currentGarage
        currentGarage = {id = garageId, type = "job"}
        QBCore.Functions.Notify("Found " .. #vehicles .. " vehicles in " .. garageId .. " garage", "primary", 5000)
        
        currentGarage = currentGarageTest
    end, garageId)
end, false)

function GetClosestVehicleInGarage(garageCoords, maxDistance)
    local ped = PlayerPedId()
    local pedCoords = GetEntityCoords(ped)
    local vehicles = GetGamePool('CVehicle')
    local closestVehicle = 0
    local closestDistance = maxDistance
    
    for i = 1, #vehicles do
        local vehicle = vehicles[i]
        local vehicleCoords = GetEntityCoords(vehicle)
        
        local distToGarage = #(vehicleCoords - garageCoords)
        
        if distToGarage <= maxDistance then
            local distToPlayer = #(vehicleCoords - pedCoords)
            
            if distToPlayer < closestDistance then
                closestVehicle = vehicle
                closestDistance = distToPlayer
            end
        end
    end
    
    if DoesEntityExist(closestVehicle) then
        Wait (100)
    end
    
    return closestVehicle
end

function FadeOutVehicle(vehicle, callback)
    local alpha = GetEntityAlpha(vehicle)
    if alpha == 0 then alpha = 255 end
    
    local fadeTime = Config.VehicleFadeTime or 2000 -- 2 seconds default
    local steps = 20 -- Number of fade steps
    local stepTime = fadeTime / steps
    local stepSize = math.floor(alpha / steps)
    
    CreateThread(function()
        for i = steps, 0, -1 do
            alpha = i * stepSize
            if alpha < 0 then alpha = 0 end
            
            SetEntityAlpha(vehicle, alpha, false)
            
            Wait(stepTime)
        end
        
        QBCore.Functions.DeleteVehicle(vehicle)
        
        if callback then callback() end
    end)
end

function FadeInVehicle(vehicle)
    SetEntityAlpha(vehicle, 0, false)
    
    local fadeTime = Config.VehicleFadeTime or 2000 -- 2 seconds default
    local steps = 20 -- Number of fade steps
    local stepTime = fadeTime / steps
    local stepSize = math.floor(255 / steps)
    
    CreateThread(function()
        for i = 0, steps do
            local alpha = i * stepSize
            if alpha > 255 then alpha = 255 end
            
            SetEntityAlpha(vehicle, alpha, false)
            
            Wait(stepTime)
        end
        
        SetEntityAlpha(vehicle, 255, false)
    end)
end

function SetVehicleSemiTransparent(vehicle, isTransparent)
    if not DoesEntityExist(vehicle) then return end
    
    local alpha = isTransparent and 75 or 255 -- 75% transparent or fully visible
    
    SetEntityAlpha(vehicle, alpha, false)
    
    local attachedEntities = GetAllAttachedEntities(vehicle)
    for _, attached in ipairs(attachedEntities) do
        SetEntityAlpha(attached, alpha, false)
    end
end

function GetAllAttachedEntities(entity)
    local entities = {}
    
    if IsEntityAVehicle(entity) and IsVehicleAttachedToTrailer(entity) then
        local trailer = GetVehicleTrailerVehicle(entity)
        if trailer and trailer > 0 then
            table.insert(entities, trailer)
        end
    end
    
    return entities
end

function GetClosestGaragePoint()
    local playerPos = GetEntityCoords(PlayerPedId())
    local closestDist = 1000.0
    local closestGarage = nil
    local closestCoords = nil
    local closestGarageType = nil
    
    for k, v in pairs(Config.Garages) do
        local garageCoords = vector3(v.coords.x, v.coords.y, v.coords.z)
        local dist = #(playerPos - garageCoords)
        if dist < closestDist then
            closestDist = dist
            closestGarage = k
            closestCoords = garageCoords
            closestGarageType = "public"
        end
    end
    
    -- Check job garages
    if PlayerData.job then
        for k, v in pairs(Config.JobGarages) do
            if v.job == PlayerData.job.name then
                local garageCoords = vector3(v.coords.x, v.coords.y, v.coords.z)
                local dist = #(playerPos - garageCoords)
                if dist < closestDist then
                    closestDist = dist
                    closestGarage = k
                    closestCoords = garageCoords
                    closestGarageType = "job"
                end
            end
        end
    end
    
    -- Check gang garages
    if PlayerData.gang and PlayerData.gang.name ~= "none" then
        for k, v in pairs(Config.GangGarages) do
            if v.gang == PlayerData.gang.name then
                local garageCoords = vector3(v.coords.x, v.coords.y, v.coords.z)
                local dist = #(playerPos - garageCoords)
                if dist < closestDist then
                    closestDist = dist
                    closestGarage = k
                    closestCoords = garageCoords
                    closestGarageType = "gang"
                end
            end
        end
    end
    
    if closestDist <= optimalParkingDistance then
        return closestGarage, closestGarageType, closestCoords, closestDist
    end
    
    return nil, nil, nil, nil
end

function FindClearSpawnPoint(spawnPoints)
    for i, point in ipairs(spawnPoints) do
        local coords = vector3(point.x, point.y, point.z)
        local clear = true
        
        local vehicles = GetGamePool('CVehicle')
        for j = 1, #vehicles do
            local vehicleCoords = GetEntityCoords(vehicles[j])
            if #(vehicleCoords - coords) <= 3.0 then
                clear = false
                break
            end
        end
        
        if clear then
            return point
        end
    end
    
    return nil
end

function IsVehicleOwned(vehicle)
    local plate = QBCore.Functions.GetPlate(vehicle)
    if not plate then return false end
    
    if vehicleOwnershipCache[plate] ~= nil then
        return vehicleOwnershipCache[plate]
    end
    
    -- Set default to false, will be updated by callback
    vehicleOwnershipCache[plate] = false
    
    QBCore.Functions.TriggerCallback('qb-garages:server:CheckIfVehicleOwned', function(owned)
        vehicleOwnershipCache[plate] = owned
    end, plate)
    
    return vehicleOwnershipCache[plate]
end


CreateThread(function()
    while true do
        Wait(60000)
        vehicleOwnershipCache = {}
    end
end)

function FixEngineSmoke(vehicle)
    local engineHealth = GetVehicleEngineHealth(vehicle)
    
    SetVehicleEngineHealth(vehicle, 1000.0)
    Wait(50)
    
    if engineHealth < 300.0 then
        engineHealth = 300.0
    end
    
    SetVehicleEngineHealth(vehicle, engineHealth)
    SetVehicleEngineOn(vehicle, true, true, false)
    SetVehicleDamage(vehicle, 0.0, 0.0, 0.3, 0.0, 0.0, false)
    
    SetEntityProofs(vehicle, false, true, false, false, false, false, false, false)
    Wait(100)
    SetEntityProofs(vehicle, false, false, false, false, false, false, false, false)
end

function DrawText3D(x, y, z, text)
    local onScreen, _x, _y = World3dToScreen2d(x, y, z)
    
    if onScreen then
        local dist = #(GetGameplayCamCoords() - vector3(x, y, z))
        local scale = (1 / dist) * 2.5
        local fov = (1 / GetGameplayCamFov()) * 100
        scale = scale * fov * 0.7
        
        SetTextScale(0.0, 0.40 * scale)
        SetTextFont(4)
        SetTextProportional(1)
        SetTextColour(255, 255, 255, 215)
        SetTextDropShadow(0, 0, 0, 55)
        SetTextEdge(2, 0, 0, 0, 150)
        SetTextDropShadow()
        SetTextOutline()
        SetTextEntry("STRING")
        SetTextCentre(1)
        AddTextComponentString(text)
        DrawText(_x, _y)
        
        local factor = (string.len(text)) / 370
        DrawRect(_x, _y + 0.0125, 0.017 + factor, 0.03 * scale, 0, 0, 0, 75)
        
        local highlight = math.abs(math.sin(GetGameTimer() / 500)) * 50
        DrawRect(_x, _y + 0.0125 - 0.01 * scale, 0.017 + factor, 0.002 * scale, 255, 255, 255, highlight)
    end
end

CreateThread(function()
    while true do
        local sleep = 1000
        local ped = PlayerPedId()
        local isInVehicle = IsPedInAnyVehicle(ped, false)
        local vehicle = GetVehiclePedIsIn(ped, true)
        
        if not DoesEntityExist(vehicle) then 
            isVehicleFaded = false
            fadedVehicle = nil
            parkingPromptShown = false
            canStoreVehicle = false
            isStorageInProgress = false
            Wait(sleep)
            goto continue
        end
        
        if not isInVehicle and DoesEntityExist(vehicle) and vehicle > 0 then
            local garageId, garageType, garageCoords, garageDist = GetClosestGaragePoint()
            
            if garageId and garageDist <= optimalParkingDistance then
                local pedInDriverSeat = GetPedInVehicleSeat(vehicle, -1)
                local speed = GetEntitySpeed(vehicle)
                local isStationary = speed < 0.1
                
                if pedInDriverSeat == 0 and isStationary then
                    local vehicleCoords = GetEntityCoords(vehicle)
                    local playerCoords = GetEntityCoords(ped)
                    local distToVehicle = #(playerCoords - vehicleCoords)
                    local plate = QBCore.Functions.GetPlate(vehicle)
                    
                    if not plate then goto skip_vehicle end
                    
                    -- Job vehicle handling
                    if garageType == "job" and PlayerData.job then
                        local jobName = PlayerData.job.name
                        local jobGarage = Config.JobGarages[garageId]
                        
                        if jobGarage and jobGarage.job == jobName then
                            -- Check if this is a job vehicle
                            local isJobVehicle = false
                            local model = GetEntityModel(vehicle)
                            local modelName = string.lower(GetDisplayNameFromVehicleModel(model))
                            
                            if jobGarage.vehicles then
                                for jobVehModel, _ in pairs(jobGarage.vehicles) do
                                    if string.lower(jobVehModel) == modelName then
                                        isJobVehicle = true
                                        break
                                    end
                                end
                            end
                            
                            if isJobVehicle then
                                if distToVehicle < 10.0 then
                                    if not isVehicleFaded or fadedVehicle ~= vehicle then
                                        SetEntityAlpha(vehicle, 192, false)
                                        isVehicleFaded = true
                                        fadedVehicle = vehicle
                                        canStoreVehicle = true
                                    end
                                
                                    if distToVehicle < 5.0 and not isStorageInProgress then
                                        sleep = 0
                                        parkingPromptShown = true
                                        
                                        -- NUI הצגת הודעת
                                        SendNUIMessage({
                                            action = "showGaragePrompt",
                                            text = "PARK VEHICLE"
                                        })
                                        
                                        -- גם שמירה על DrawText3D למקרה שה-NUI לא עובד
                                        -- DrawText3D(vehicleCoords.x, vehicleCoords.y, vehicleCoords.z + 1.0, "PRESS [E] TO PARK VEHICLE")
                                        
                                        if IsControlJustPressed(0, 38) and canStoreVehicle then
                                            isStorageInProgress = true
                                            canStoreVehicle = false
                                            
                                            -- Park the job vehicle with animation
                                            ParkJobVehicle(vehicle, jobName)
                                            
                                            -- Reset after delay
                                            Citizen.SetTimeout(3000, function()
                                                isStorageInProgress = false
                                            end)
                                        end
                                    else
                                        -- הסתרת ההודעה אם התרחקנו
                                        if parkingPromptShown then
                                            SendNUIMessage({
                                                action = "hideGaragePrompt"
                                            })
                                            parkingPromptShown = false
                                        end
                                    end
                                else
                                    if isVehicleFaded and fadedVehicle == vehicle then
                                        SetEntityAlpha(vehicle, 255, false)
                                        isVehicleFaded = false
                                        fadedVehicle = nil
                                        parkingPromptShown = false
                                        canStoreVehicle = false
                                        
                                        -- הסתרת ההודעה אם התרחקנו
                                        SendNUIMessage({
                                            action = "hideGaragePrompt"
                                        })
                                    end
                                end
                                
                                goto skip_vehicle
                            end
                        end
                    end
                    
                    -- Handle regular owned vehicles
                    local isOwned = vehicleOwnershipCache[plate]
                    if isOwned == nil then
                        QBCore.Functions.TriggerCallback('qb-garages:server:CheckIfVehicleOwned', function(owned)
                            vehicleOwnershipCache[plate] = owned
                        end, plate)
                        isOwned = false
                    end

                    if isOwned then
                        -- OWNED VEHICLE - SHOW EFFECTS
                        if distToVehicle < 10.0 then
                            if not isVehicleFaded or fadedVehicle ~= vehicle then
                                SetEntityAlpha(vehicle, 192, false)
                                isVehicleFaded = true
                                fadedVehicle = vehicle
                                canStoreVehicle = true
                            end
                        
                            if distToVehicle < 5.0 and not isStorageInProgress then
                                sleep = 0
                                parkingPromptShown = true
                                
                                -- NUI הצגת הודעת
                                SendNUIMessage({
                                    action = "showGaragePrompt",
                                    text = "STORE VEHICLE"
                                })
                                
                                -- גם שמירה על DrawText3D למקרה שה-NUI לא עובד
                                -- DrawText3D(vehicleCoords.x, vehicleCoords.y, vehicleCoords.z + 1.0, "PRESS [E] TO STORE VEHICLE")
                                
                                if IsControlJustPressed(0, 38) and canStoreVehicle then
                                    TriggerEvent('qb-garages:client:StoreVehicle', {
                                        garageId = garageId,
                                        garageType = garageType
                                    })
                                end
                            else
                                -- הסתרת ההודעה אם התרחקנו
                                if parkingPromptShown then
                                    SendNUIMessage({
                                        action = "hideGaragePrompt"
                                    })
                                    parkingPromptShown = false
                                end
                            end
                        else
                            if isVehicleFaded and fadedVehicle == vehicle then
                                SetEntityAlpha(vehicle, 255, false)
                                isVehicleFaded = false
                                fadedVehicle = nil
                                parkingPromptShown = false
                                canStoreVehicle = false
                                
                                -- הסתרת ההודעה אם התרחקנו
                                SendNUIMessage({
                                    action = "hideGaragePrompt"
                                })
                            end
                        end
                    else
                        -- NOT OWNED - NO EFFECTS
                        if isVehicleFaded and fadedVehicle == vehicle then
                            SetEntityAlpha(vehicle, 255, false)
                            isVehicleFaded = false
                            fadedVehicle = nil
                            parkingPromptShown = false
                            canStoreVehicle = false
                            
                            -- הסתרת ההודעה אם לא הרכב שלך
                            SendNUIMessage({
                                action = "hideGaragePrompt"
                            })
                        end
                    end
                    
                    ::skip_vehicle::
                else
                    if isVehicleFaded and fadedVehicle == vehicle then
                        SetEntityAlpha(vehicle, 255, false)
                        isVehicleFaded = false
                        fadedVehicle = nil
                        parkingPromptShown = false
                        canStoreVehicle = false
                        
                        -- הסתרת ההודעה אם מישהו נמצא ברכב
                        SendNUIMessage({
                            action = "hideGaragePrompt"
                        })
                    end
                end
            else
                if isVehicleFaded and fadedVehicle == vehicle then
                    SetEntityAlpha(vehicle, 255, false)
                    isVehicleFaded = false
                    fadedVehicle = nil
                    parkingPromptShown = false
                    canStoreVehicle = false
                    
                    -- הסתרת ההודעה אם לא ליד מוסך
                    SendNUIMessage({
                        action = "hideGaragePrompt"
                    })
                end
            end
        elseif isInVehicle then
            local currentVehicle = GetVehiclePedIsIn(ped, false)
            
            if currentVehicle > 0 and DoesEntityExist(currentVehicle) then
                -- Job vehicle access check
                local plate = QBCore.Functions.GetPlate(currentVehicle)
                if plate then
                    QBCore.Functions.TriggerCallback('qb-garages:server:CheckJobAccess', function(hasAccess)
                        if not hasAccess then
                            -- Check if this is a job vehicle
                            local isJobVehicle = false
                            local jobName = nil
                            
                            for k, v in pairs(Config.JobGarages) do
                                local model = GetEntityModel(currentVehicle)
                                local modelName = string.lower(GetDisplayNameFromVehicleModel(model))
                                
                                if v.vehicles then
                                    for jobVehModel, _ in pairs(v.vehicles) do
                                        if string.lower(jobVehModel) == modelName then
                                            isJobVehicle = true
                                            jobName = v.job
                                            break
                                        end
                                    end
                                end
                                
                                if isJobVehicle then break end
                            end
                            
                            if isJobVehicle and jobName ~= PlayerData.job.name then
                                -- Kick player out of vehicle they don't have access to
                                TaskLeaveVehicle(ped, currentVehicle, 0)
                                QBCore.Functions.Notify("You don't have access to this job vehicle", "error")
                            end
                        end
                    end, plate)
                end

                -- Make vehicle fully visible when entered
                SetEntityAlpha(currentVehicle, 255, false)
                
                local attachedEntities = GetAllAttachedEntities(currentVehicle)
                for _, attached in ipairs(attachedEntities) do
                    SetEntityAlpha(attached, 255, false)
                end
                
                if isVehicleFaded and fadedVehicle == currentVehicle then
                    isVehicleFaded = false
                    fadedVehicle = nil
                    parkingPromptShown = false
                    canStoreVehicle = false
                    
                    -- הסתר הודעה אם נכנסנו לרכב
                    SendNUIMessage({
                        action = "hideGaragePrompt"
                    })
                end
            end
        end
        
        ::continue::
        Wait(sleep)
    end
end)

RegisterNetEvent('qb-garages:client:FreeJobParkingSpot', function(jobName, spotIndex)
    if occupiedParkingSpots[jobName] then
        occupiedParkingSpots[jobName][spotIndex] = nil
    end
end)


function CreateGarageAttendant(coords, heading, model)
    RequestModel(GetHashKey(model))
    while not HasModelLoaded(GetHashKey(model)) do
        Wait(1)
    end
    
    local ped = CreatePed(4, GetHashKey(model), coords.x, coords.y, coords.z - 1.0, heading, false, true)
    FreezeEntityPosition(ped, true)
    SetEntityInvincible(ped, true)
    SetBlockingOfNonTemporaryEvents(ped, true)
    TaskStartScenarioInPlace(ped, "WORLD_HUMAN_CLIPBOARD", 0, true)
    
    return ped
end

CreateThread(function()
    while not isPlayerLoaded do
        Wait(500)
    end
    
    local attendantModels = {
        "s_m_m_security_01", "s_m_y_valet_01", "s_m_m_gentransport", 
        "s_m_m_autoshop_01", "s_m_m_autoshop_02"
    }
    
    local garageAttendants = {}
    
    -- Public garages
    for k, v in pairs(Config.Garages) do
        local model = attendantModels[math.random(1, #attendantModels)]
        local ped = CreateGarageAttendant(v.coords, v.coords.w, model)
        table.insert(garageAttendants, {ped = ped, garageId = k, garageType = "public"})
    end
    
    -- Job garages 
    for k, v in pairs(Config.JobGarages) do
        local model = attendantModels[math.random(1, #attendantModels)]
        local ped = CreateGarageAttendant(v.coords, v.coords.w, model)
        table.insert(garageAttendants, {ped = ped, garageId = k, garageType = "job", jobName = v.job})
    end
    
    -- Gang garages
    for k, v in pairs(Config.GangGarages) do
        local model = attendantModels[math.random(1, #attendantModels)]
        local ped = CreateGarageAttendant(v.coords, v.coords.w, model)
        table.insert(garageAttendants, {ped = ped, garageId = k, garageType = "gang", gangName = v.gang})
    end
    
    -- Impound lots
    for k, v in pairs(Config.ImpoundLots) do
        local model = "s_m_y_cop_01"
        if k == "paleto" then model = "s_m_y_sheriff_01"
        elseif k == "sandy" then model = "s_m_y_ranger_01" end
        
        local ped = CreateGarageAttendant(v.coords, v.coords.w, model)
        table.insert(garageAttendants, {ped = ped, garageId = k, garageType = "impound"})
    end
    
    if Config.UseTarget then
        -- TARGET SYSTEM
        for _, data in pairs(garageAttendants) do
            if data.garageType == "public" then
                exports['qb-target']:AddTargetEntity(data.ped, {
                    options = {
                        {
                            type = "client",
                            event = "qb-garages:client:OpenGarage",
                            icon = "fas fa-car",
                            label = "Open Garage",
                            garageId = data.garageId,
                            garageType = data.garageType
                        }
                    },
                    distance = 2.5
                })
            elseif data.garageType == "job" then
                exports['qb-target']:AddTargetEntity(data.ped, {
                    options = {
                        {
                            type = "client",
                            event = "qb-garages:client:OpenGarage",
                            icon = "fas fa-car",
                            label = "Open Job Garage",
                            garageId = data.garageId,
                            garageType = data.garageType
                        }
                    },
                    distance = 2.5,
                    job = data.jobName
                })
            elseif data.garageType == "gang" then
                exports['qb-target']:AddTargetEntity(data.ped, {
                    options = {
                        {
                            type = "client",
                            event = "qb-garages:client:OpenGarage",
                            icon = "fas fa-car",
                            label = "Open Gang Garage",
                            garageId = data.garageId,
                            garageType = data.garageType
                        }
                    },
                    distance = 2.5,
                    gang = data.gangName
                })
            elseif data.garageType == "impound" then
                exports['qb-target']:AddTargetEntity(data.ped, {
                    options = {
                        {
                            type = "client",
                            event = "qb-garages:client:OpenImpoundLot",
                            icon = "fas fa-car",
                            label = "Check Impound Lot",
                            impoundId = data.garageId
                        }
                    },
                    distance = 2.5
                })
            end
        end
    else
        -- DRAWTEXT3D SYSTEM
while true do
    local sleep = 1000
    local ped = PlayerPedId()
    local pos = GetEntityCoords(ped)
    local nearAnyGarage = false
    
    for k, v in pairs(Config.Garages) do
        local dist = #(pos - vector3(v.coords.x, v.coords.y, v.coords.z))
        if dist <= 3.0 then 
            sleep = 0
            nearAnyGarage = true  -- סימון שאנחנו ליד מוסך
            SendNUIMessage({action = "showGaragePrompt", text = "Open Garage"})
            if IsControlJustReleased(0, 38) then
                TriggerEvent("qb-garages:client:OpenGarage", {garageId = k, garageType = "public"})
            end
        end
    end
    
    -- Job garages
    for k, v in pairs(Config.JobGarages) do
        if PlayerData.job and PlayerData.job.name == v.job then
            local dist = #(pos - vector3(v.coords.x, v.coords.y, v.coords.z))
            if dist <= 3.0 then 
                sleep = 0
                nearAnyGarage = true  -- חשוב להוסיף גם כאן!
                SendNUIMessage({action = "showGaragePrompt", text = "Open Job Garage"})                        
                if IsControlJustReleased(0, 38) then
                    TriggerEvent("qb-garages:client:OpenGarage", {garageId = k, garageType = "job"})
                end
            end
        end
    end
    
    -- Gang garages
    for k, v in pairs(Config.GangGarages) do
        if PlayerData.gang and PlayerData.gang.name == v.gang then
            local dist = #(pos - vector3(v.coords.x, v.coords.y, v.coords.z))
            if dist <= 3.0 then 
                sleep = 0
                nearAnyGarage = true  -- חשוב להוסיף גם כאן!
                SendNUIMessage({action = "showGaragePrompt", text = "Open Gang Garage"})                 
                if IsControlJustReleased(0, 38) then
                    TriggerEvent("qb-garages:client:OpenGarage", {garageId = k, garageType = "gang"})
                end
            end
        end
    end
    
    -- Impound lots
    for k, v in pairs(Config.ImpoundLots) do
        local dist = #(pos - vector3(v.coords.x, v.coords.y, v.coords.z))
        if dist <= 3.0 then 
            sleep = 0
            nearAnyGarage = true  -- חשוב להוסיף גם כאן!
            SendNUIMessage({action = "showGaragePrompt", text = "Check Impound Lot"})                    
            if IsControlJustReleased(0, 38) then
                TriggerEvent("qb-garages:client:OpenImpoundLot", {impoundId = k})
            end
        end
    end
    
    -- הסתר את הכפתור אם לא ליד אף מוסך
    if not nearAnyGarage then
        SendNUIMessage({action = "hideGaragePrompt"})
    end
    
    Wait(sleep)
end
    end
end)


function OpenGarageUI(vehicles, garageInfo, garageType)
    
    table.sort(vehicles, function(a, b)
        if a.is_favorite and not b.is_favorite then
            return true
        elseif not a.is_favorite and b.is_favorite then
            return false
        else
            return a.vehicle < b.vehicle -- Alphabetical as fallbackv
        end
    end)
    
    local vehicleData = FormatVehiclesForNUI(vehicles)
    
    local hasGang = false
    if PlayerData.gang and PlayerData.gang.name and PlayerData.gang.name ~= "none" then
        hasGang = true
    end
    
    local hasJobAccess = false
    
    local isInJobGarage = false
    if garageType == "job" then
        if garageInfo.job == PlayerData.job.name then
            isInJobGarage = true
            hasJobAccess = true
        end
    end
    
    QBCore.Functions.TriggerCallback('qb-garages:server:GetAllGarages', function(allGarages)
        SetNuiFocus(true, true)
        SendNUIMessage({
            action = "openGarage",
            vehicles = vehicleData,
            playerName = PlayerData.charinfo.firstname .. ' ' .. PlayerData.charinfo.lastname,
            playerCash = PlayerData.money["cash"] or 0,
            garage = {
                name = garageInfo.label,
                type = garageType,
                location = garageInfo.label,
                hasGang = hasGang,
                hasJobAccess = isInJobGarage, -- Only if in job garage
                hasSharedAccess = Config.EnableSharedGarages, -- Add support for shared garages
                showJobVehiclesTab = true, -- Always show the job vehicles tab in job garages
                gangName = PlayerData.gang and PlayerData.gang.name or nil,
                jobName = PlayerData.job and PlayerData.job.name or nil,
                isJobGarage = garageType == "job",
                isSharedGarage = garageType == "shared",
                isImpound = garageType == "impound",
                id = garageInfo.id
            },
            allGarages = allGarages,
            transferCost = Config.TransferCost or 500
        })
    end)
    
end

RegisterNetEvent('qb-garages:client:OpenGarage', function(data)
    if isMenuOpen then return end
    isMenuOpen = true
   
    local garageId = data.garageId
    local garageType = data.garageType
    local garageInfo = {}   
    currentGarage = {id = garageId, type = garageType}
   
    if garageType == "public" then
        garageInfo = Config.Garages[garageId]
    elseif garageType == "job" then
        garageInfo = Config.JobGarages[garageId]
    elseif garageType == "gang" then
        garageInfo = Config.GangGarages[garageId]
    elseif garageType == "shared" then
        garageInfo = data.garageInfo
    elseif garageType == "impound" then
        garageInfo = Config.ImpoundLots[garageId]
    end

    local isImpoundLot = (garageType == "impound")

    if garageType == "public" then
        QBCore.Functions.TriggerCallback('qb-garages:server:GetPersonalVehicles', function(vehicles)
            -- Add player info to data
            data.playerName = PlayerData.charinfo.firstname .. ' ' .. PlayerData.charinfo.lastname
            data.playerCash = PlayerData.money["cash"] or 0
            
            OpenGarageUI(vehicles or {}, garageInfo, garageType, isImpoundLot)
        end)
    elseif garageType == "job" then
        QBCore.Functions.TriggerCallback('qb-garages:server:GetJobGarageVehicles', function(vehicles)
            -- Add player info to data
            data.playerName = PlayerData.charinfo.firstname .. ' ' .. PlayerData.charinfo.lastname
            data.playerCash = PlayerData.money["cash"] or 0
            
            OpenGarageUI(vehicles or {}, garageInfo, garageType, isImpoundLot)
        end, garageId)
    elseif garageType == "gang" then
        QBCore.Functions.TriggerCallback('qb-garages:server:GetGangVehicles', function(vehicles)
            -- Add player info to data
            data.playerName = PlayerData.charinfo.firstname .. ' ' .. PlayerData.charinfo.lastname
            data.playerCash = PlayerData.money["cash"] or 0
            
            OpenGarageUI(vehicles or {}, garageInfo, garageType, isImpoundLot)
        end, garageInfo.gang, garageId)
    elseif garageType == "shared" then
        QBCore.Functions.TriggerCallback('qb-garages:server:GetSharedGarageVehicles', function(vehicles)
            -- Add player info to data
            data.playerName = PlayerData.charinfo.firstname .. ' ' .. PlayerData.charinfo.lastname
            data.playerCash = PlayerData.money["cash"] or 0
            
            OpenGarageUI(vehicles or {}, garageInfo, garageType, isImpoundLot)
        end, garageId)
    elseif garageType == "impound" then
        QBCore.Functions.TriggerCallback('qb-garages:server:GetImpoundedVehicles', function(vehicles)
            -- Add player info to data
            data.playerName = PlayerData.charinfo.firstname .. ' ' .. PlayerData.charinfo.lastname
            data.playerCash = PlayerData.money["cash"] or 0
            
            OpenGarageUI(vehicles or {}, garageInfo, garageType, isImpoundLot)
        end)
    end
end)


function DebugJobGarage(garageId)
    local jobGarageInfo = Config.JobGarages[garageId]
    if not jobGarageInfo then
      Wait (100)
        return
    end
    
    QBCore.Functions.TriggerCallback('qb-garages:server:GetPersonalVehicles', function(vehicles)
        
        local count = 0
        for i, vehicle in ipairs(vehicles) do
            if vehicle.garage == garageId then
                count = count + 1
            end
        end
        
        if count == 0 then
            Wait (100)
        end
    end)
end

function OpenJobGarageUI(garageInfo, isImpoundLot)
    local jobVehicles = {}
    local i = 1
    
    for k, v in pairs(garageInfo.vehicles) do
        
        table.insert(jobVehicles, {
            id = i,
            model = v.model,
            name = v.label,
            fuel = 100,
            engine = 100,
            body = 100,
            state = 1,
            stored = true,
            isFavorite = false,
            isJobVehicle = true,
            icon = v.icon or "🚗"
        })
        i = i + 1
    end
    SetNuiFocus(true, true)
    SendNUIMessage({
        action = "openGarage",
        vehicles = jobVehicles,
        garage = {
            name = garageInfo.label,
            type = "job",
            location = garageInfo.label,
            isJobGarage = true,
            jobName = PlayerData.job and PlayerData.job.name or nil,
            hasJobAccess = true,  -- Always true for job garages
            isImpound = isImpoundLot -- Add this flag
        }
    })
end

RegisterNetEvent('qb-garages:client:CloseGarage')
AddEventHandler('qb-garages:client:CloseGarage', function()
    SetNuiFocus(false, false)
end)

RegisterNUICallback('closeGarage', function(data, cb)
    SetNuiFocus(false, false)
    isMenuOpen = false  -- Important to reset this variable here
    cb({status = "success"})
end)

-- Replace the RegisterNUICallback('takeOutVehicle') in client.lua (around line 1700)
RegisterNUICallback('takeOutVehicle', function(data, cb)
    local garageId = currentGarage.id
    local garageType = currentGarage.type
    local plate = data.plate
    local model = data.model
    
    SetNuiFocus(false, false)
    isMenuOpen = false
    
    if data.state == 0 then
        QBCore.Functions.Notify("This vehicle is already out of the garage.", "error")
        cb({status = "error"})
        return
    end
    
    QBCore.Functions.TriggerCallback('qb-garages:server:GetVehicleByPlate', function(vehData, isOut)
        if isOut then
            QBCore.Functions.Notify("This vehicle is already outside.", "error")
            cb({status = "error"})
            return
        end
        
        local garageInfo = {}
        if garageType == "public" then
            garageInfo = Config.Garages[garageId]
        elseif garageType == "job" then
            garageInfo = Config.JobGarages[garageId]
        elseif garageType == "gang" then
            garageInfo = Config.GangGarages[garageId]
        elseif garageType == "shared" then
            garageInfo = sharedGaragesData[garageId]
        end
        
        local spawnPoints = nil
        if garageInfo.spawnPoints then
            spawnPoints = garageInfo.spawnPoints
        else
            spawnPoints = {garageInfo.spawnPoint}
        end
        
        local clearPoint = FindClearSpawnPoint(spawnPoints)
        if not clearPoint then
            QBCore.Functions.Notify("All spawn locations are blocked!", "error")
            cb({status = "error"})
            return
        end
        
        if garageType == "shared" then
            QBCore.Functions.TriggerCallback('qb-garages:server:CheckSharedAccess', function(hasAccess)
                if hasAccess then
                    TriggerServerEvent('qb-garages:server:TakeOutSharedVehicle', plate, garageId)
                    cb({status = "success"})
                else
                    QBCore.Functions.Notify("You don't have access to this vehicle", "error")
                    cb({status = "error"})
                end
            end, plate, garageId)
            return
        end
        
        local spawnCoords = vector3(clearPoint.x, clearPoint.y, clearPoint.z)
        
        QBCore.Functions.SpawnVehicle(model, function(veh)
            SetEntityHeading(veh, clearPoint.w)
            exports['cdn-fuel']:SetFuel(veh, data.fuel)
            SetVehicleNumberPlateText(veh, plate)
            
            FadeInVehicle(veh)
            
            if garageType == "public" or garageType == "gang" then
                QBCore.Functions.TriggerCallback('qb-garages:server:GetVehicleProperties', function(properties)
                    if properties then
                        QBCore.Functions.SetVehicleProperties(veh, properties)
                        
                        -- FIX: Set health to at least 900 for fresh spawns
                        -- Data comes in as percentage (0-100), multiply by 10 to get actual health (0-1000)
                        local engineHealth = math.max(data.engine * 10, 900.0)
                        local bodyHealth = math.max(data.body * 10, 900.0)
                        
                        -- Ensure minimum health values - if too low, set to perfect
                        if engineHealth < 900.0 then engineHealth = 1000.0 end
                        if bodyHealth < 900.0 then bodyHealth = 1000.0 end
                        
                        SetVehicleEngineHealth(veh, engineHealth)
                        SetVehicleBodyHealth(veh, bodyHealth)
                        SetVehicleDirtLevel(veh, 0.0)
                        
                        FixEngineSmoke(veh)
                        
                        SetVehicleUndriveable(veh, false)
                        SetVehicleEngineOn(veh, true, true, false)
                        
                        -- Update the vehicle state in the database
                        TriggerServerEvent('qb-garages:server:UpdateVehicleState', plate, 0)
                        
                        if garageType == "gang" and data.storedInGang then
                            TriggerServerEvent('qb-garages:server:UpdateGangVehicleState', plate, 0)
                        end
                        
                        QBCore.Functions.Notify("Vehicle taken out", "success")
                        TriggerEvent('vehiclekeys:client:SetOwner', plate)
                    end
                end, plate)
            else 
                -- Job vehicle
                SetVehicleEngineHealth(veh, 1000.0)
                SetVehicleBodyHealth(veh, 1000.0)
                SetVehicleDirtLevel(veh, 0.0)
                SetVehicleUndriveable(veh, false)
                SetVehicleEngineOn(veh, true, true, false)
                
                FixEngineSmoke(veh)
                
                QBCore.Functions.Notify("Job vehicle taken out", "success")
                TriggerEvent('vehiclekeys:client:SetOwner', QBCore.Functions.GetPlate(veh))
            end
        end, spawnCoords, true)
        
        cb({status = "success"})
    end, plate)
end)

RegisterNetEvent('qb-garages:client:TakeOutSharedVehicle', function(plate, vehicleData)
    local garageId = currentGarage.id
    local garageType = currentGarage.type
    
    if not garageId or not garageType then
        QBCore.Functions.Notify("Garage information is missing", "error")
        return
    end
    
    if not sharedGaragesData[garageId] then
        QBCore.Functions.Notify("Shared garage data not found", "error")
        return
    end
    
    if not plate or not vehicleData then
        QBCore.Functions.Notify("Vehicle data is incomplete", "error")
        return
    end
    
    local garageInfo = sharedGaragesData[garageId]
    
    local spawnPoints = nil
    if garageInfo.spawnPoints then
        spawnPoints = garageInfo.spawnPoints
    else
        spawnPoints = {garageInfo.spawnPoint}
    end
    
    local clearPoint = FindClearSpawnPoint(spawnPoints)
    if not clearPoint then
        QBCore.Functions.Notify("All spawn locations are blocked!", "error")
        return
    end
    
    local spawnCoords = vector3(clearPoint.x, clearPoint.y, clearPoint.z)
    
    QBCore.Functions.SpawnVehicle(vehicleData.vehicle, function(veh)
        if not veh or veh == 0 then
            QBCore.Functions.Notify("Error creating shared vehicle. Please try again.", "error")
            return
        end
        
        SetEntityHeading(veh, clearPoint.w)
        exports['cdn-fuel']:SetFuel(veh, vehicleData.fuel)
        SetVehicleNumberPlateText(veh, plate)
        
        FadeInVehicle(veh)
        
        QBCore.Functions.TriggerCallback('qb-garages:server:GetVehicleProperties', function(properties)
            if properties then
                QBCore.Functions.SetVehicleProperties(veh, properties)
                
                -- FIX: Ensure health is at least 900
                local engineHealth = math.max(vehicleData.engine, 900.0)
                local bodyHealth = math.max(vehicleData.body, 900.0)
                
                -- Set to perfect condition if health is low
                if engineHealth < 900.0 then engineHealth = 1000.0 end
                if bodyHealth < 900.0 then bodyHealth = 1000.0 end
                
                SetVehicleEngineHealth(veh, engineHealth)
                SetVehicleBodyHealth(veh, bodyHealth)
                SetVehicleDirtLevel(veh, 0.0) 
                
                FixEngineSmoke(veh)
                
                SetVehicleUndriveable(veh, false)
                SetVehicleEngineOn(veh, true, true, false)
                
                QBCore.Functions.Notify("Vehicle taken out from shared garage", "success")
                TriggerEvent('vehiclekeys:client:SetOwner', plate)
            else
                QBCore.Functions.Notify("Failed to load vehicle properties", "error")
            end
        end, plate)
    end, spawnCoords, true)
end)


function PlayVehicleTransferAnimation(plate, fromGarageId, toGarageId)
    local garageInfo = nil
    if currentGarage.type == "public" then
        garageInfo = Config.Garages[fromGarageId]
    elseif currentGarage.type == "job" then
        garageInfo = Config.JobGarages[fromGarageId]
    elseif currentGarage.type == "gang" then
        garageInfo = Config.GangGarages[fromGarageId]
    end
    
    if not garageInfo then 
        TriggerServerEvent('qb-garages:server:TransferVehicleToGarage', plate, toGarageId, Config.TransferCost or 500)
        QBCore.Functions.Notify("Vehicle transferred", "success")
        return 
    end
    
    local garageCoords = vector3(garageInfo.coords.x, garageInfo.coords.y, garageInfo.coords.z)
    
    if not garageInfo.transferSpawn or not garageInfo.transferArrival then
        TriggerServerEvent('qb-garages:server:TransferVehicleToGarage', plate, toGarageId, Config.TransferCost or 500)
        QBCore.Functions.Notify("Vehicle transferred", "success")
        return
    end
    
    local spawnPos = garageInfo.transferSpawn
    local arrivalPos = garageInfo.transferArrival
    local exitPos = garageInfo.transferExit or nil
    
    local truckModel = "flatbed"
    local driverModel = "s_m_m_trucker_01"
    
    RequestModel(GetHashKey(truckModel))
    RequestModel(GetHashKey(driverModel))
    
    local timeout = 0
    while (not HasModelLoaded(GetHashKey(truckModel)) or not HasModelLoaded(GetHashKey(driverModel))) and timeout < 50 do
        Wait(100)
        timeout = timeout + 1
    end
    
    if timeout >= 50 then
        TriggerServerEvent('qb-garages:server:TransferVehicleToGarage', plate, toGarageId, Config.TransferCost or 500)
        QBCore.Functions.Notify("Vehicle transferred", "success")
        return
    end
    
    QBCore.Functions.Notify("Vehicle transfer service is on the way...", "primary", 4000)
    
    QBCore.Functions.SpawnVehicle(truckModel, function(truck)
        if not DoesEntityExist(truck) then
            TriggerServerEvent('qb-garages:server:TransferVehicleToGarage', plate, toGarageId, Config.TransferCost or 500)
            QBCore.Functions.Notify("Vehicle transferred", "success")
            return
        end
        
        SetEntityAsMissionEntity(truck, true, true)
        SetEntityHeading(truck, spawnPos.w)
        SetVehicleEngineOn(truck, true, true, false)
        
        local driver = CreatePedInsideVehicle(truck, 26, GetHashKey(driverModel), -1, true, false)
        
        if not DoesEntityExist(driver) then
            DeleteEntity(truck)
            TriggerServerEvent('qb-garages:server:TransferVehicleToGarage', plate, toGarageId, Config.TransferCost or 500)
            QBCore.Functions.Notify("Vehicle transferred", "success")
            return
        end
        
        SetEntityAsMissionEntity(driver, true, true)
        SetBlockingOfNonTemporaryEvents(driver, true)
        SetDriverAbility(driver, 1.0)
        SetDriverAggressiveness(driver, 0.0)
        
        local blip = AddBlipForEntity(truck)
        SetBlipSprite(blip, 67)
        SetBlipColour(blip, 5)
        SetBlipDisplay(blip, 2)
        BeginTextCommandSetBlipName("STRING")
        AddTextComponentString("Transfer Truck")
        EndTextCommandSetBlipName(blip)
        SetEntityAlpha(truck, 0, false)
        SetEntityAlpha(driver, 0, false)
        
        local fadeSteps = 51 
        for i = 1, fadeSteps do
            local alpha = (i - 1) * 5
            if alpha > 255 then alpha = 255 end
            
            SetEntityAlpha(truck, alpha, false)
            SetEntityAlpha(driver, alpha, false)
            
            Wait(30) 
        end
        
        SetEntityAlpha(truck, 255, false)
        SetEntityAlpha(driver, 255, false)
        
        local vehicleFlags = 447 
        local speed = 10.0    
        
        TaskVehicleDriveToCoord(driver, truck, 
            arrivalPos.x, arrivalPos.y, arrivalPos.z, 
            speed, 0, GetHashKey(truckModel), 
            vehicleFlags, 
            10.0, 
            true 
        )
        
        local startTime = GetGameTimer()
        local maxDriveTime = 90000 
        local arrivalRange = 15.0  
        local lastPos = GetEntityCoords(truck)
        local stuckCounter = 0
        local arrived = false
        
        CreateThread(function()
            while not arrived do
                Wait(1000) 
                
                if not DoesEntityExist(truck) or not DoesEntityExist(driver) then
                    break
                end
                
                local curPos = GetEntityCoords(truck)
                local distToDestination = #(curPos - vector3(arrivalPos.x, arrivalPos.y, arrivalPos.z))
                
                if distToDestination < arrivalRange then
                    local curSpeed = GetEntitySpeed(truck) * 3.6 -- convert to km/h
                    
                    if curSpeed < 1.0 or distToDestination < 5.0 then
                        TaskVehicleTempAction(driver, truck, 27, 10000) -- Brake action
                        arrived = true
                        break
                    end
                end
                
                local distMoved = #(curPos - lastPos)
                local vehicleSpeed = GetEntitySpeed(truck)
                
                if distMoved < 0.3 and vehicleSpeed < 0.5 then
                    stuckCounter = stuckCounter + 1
                    
                    if stuckCounter >= 10 then
                        arrived = true
                        break
                    end
                    if stuckCounter % 3 == 0 then 
                        ClearPedTasks(driver)
                        Wait(500)
                        TaskVehicleDriveToCoord(driver, truck, 
                            arrivalPos.x, arrivalPos.y, arrivalPos.z, 
                            speed, 0, GetHashKey(truckModel), 
                            vehicleFlags, 
                            arrivalRange, true
                        )
                    end
                else
                    stuckCounter = 0
                end
                
                if GetGameTimer() - startTime > maxDriveTime then
                    arrived = true
                    break
                end
                
                lastPos = curPos
            end
            
            if DoesEntityExist(truck) and DoesEntityExist(driver) then
                ClearPedTasks(driver)
                TaskVehicleTempAction(driver, truck, 27, 10000) 
                SetVehicleIndicatorLights(truck, 0, true)
                SetVehicleIndicatorLights(truck, 1, true)
                QBCore.Functions.Notify("Loading your vehicle onto the transfer truck...", "primary", 4000)
                PlaySoundFromEntity(-1, "VEHICLES_TRAILER_ATTACH", truck, 0, 0, 0)
                Wait(5000)
                TriggerServerEvent('qb-garages:server:TransferVehicleToGarage', plate, toGarageId, Config.TransferCost or 500)
                QBCore.Functions.Notify("Vehicle transferred successfully!", "success")
                SetVehicleIndicatorLights(truck, 0, false)
                SetVehicleIndicatorLights(truck, 1, false)
                local driveToExit = false
                local exitX, exitY, exitZ, exitHeading
                if exitPos then
                    driveToExit = true
                    exitX = exitPos.x
                    exitY = exitPos.y
                    exitZ = exitPos.z
                    exitHeading = exitPos.w
                else
                    local curPos = GetEntityCoords(truck)
                    local curHeading = GetEntityHeading(truck)
                    local leaveHeading = (curHeading + 180.0) % 360.0
                    local leaveDistance = 100.0
                    local success, nodePos, nodeHeading = GetClosestVehicleNodeWithHeading(
                        curPos.x + math.sin(math.rad(leaveHeading)) * 20.0,
                        curPos.y + math.cos(math.rad(leaveHeading)) * 20.0,
                        curPos.z,
                        0, 3.0, 0
                    )
                    
                    if success then
                        driveToExit = true
                        exitX = nodePos.x
                        exitY = nodePos.y
                        exitZ = nodePos.z
                        exitHeading = nodeHeading
                    else
                        driveToExit = true
                        exitX = curPos.x + math.sin(math.rad(leaveHeading)) * leaveDistance
                        exitY = curPos.y + math.cos(math.rad(leaveHeading)) * leaveDistance
                        exitZ = curPos.z
                        exitHeading = leaveHeading
                    end
                end
                
                if driveToExit then
                    TaskVehicleDriveToCoord(driver, truck, exitX, exitY, exitZ, speed, 0, GetHashKey(truckModel), vehicleFlags, 2.0, true)
                    
                    Wait(5000)
                    
                    for i = 255, 0, -5 do
                        if DoesEntityExist(truck) then
                            SetEntityAlpha(truck, i, false)
                        end
                        
                        if DoesEntityExist(driver) then
                            SetEntityAlpha(driver, i, false)
                        end
                        
                        Wait(50) 
                    end
                end
                
                RemoveBlip(blip)
                DeleteEntity(driver)
                DeleteEntity(truck)
            end
        end)
    end, vector3(spawnPos.x, spawnPos.y, spawnPos.z), true)
end

function normalize(vec)
    local length = math.sqrt(vec.x * vec.x + vec.y * vec.y + vec.z * vec.z)
    if length > 0 then
        return vector3(vec.x / length, vec.y / length, vec.z / length)
    else
        return vector3(0, 0, 0)
    end
end

function normalize(vec)
    local length = math.sqrt(vec.x * vec.x + vec.y * vec.y + vec.z * vec.z)
    if length > 0 then
        return vector3(vec.x / length, vec.y / length, vec.z / length)
    else
        return vector3(0, 0, 0)
    end
end

RegisterNUICallback('directTransferVehicle', function(data, cb)
    local plate = data.plate
    local newGarageId = data.newGarageId
    local cost = data.cost or Config.TransferCost or 500
    
    cb({status = "success"})
    
    if Config.EnableTransferAnimation then
        -- Trigger the animation event if enabled
        local fromGarageId = currentGarage.id
        PlayVehicleTransferAnimation(plate, fromGarageId, newGarageId)
    else
        -- Otherwise just trigger the direct transfer
        TriggerServerEvent('qb-garages:server:TransferVehicleToGarage', plate, newGarageId, cost)
    end
    
    -- Give some time for the server to process before refreshing
    Citizen.SetTimeout(1000, function()
        TriggerEvent('qb-garages:client:RefreshVehicleList')
    end)
end)

RegisterNUICallback('transferVehicle', function(data, cb)
    local plate = data.plate
    local newGarageId = data.newGarageId
    local cost = data.cost or Config.TransferCost or 500
    
    
    if not plate or not newGarageId then
        cb({status = "error", message = "Invalid data"})
        return
    end
    
    if isTransferringVehicle then
        cb({status = "error", message = "Transfer already in progress"})
        return
    end
    
    isTransferringVehicle = true
    currentTransferVehicle = {plate = plate, garage = newGarageId}
    
    SetNuiFocus(false, false)
    TriggerServerEvent('qb-garages:server:TransferVehicleToGarage', plate, newGarageId, cost)
    
    Citizen.SetTimeout(2000, function()
        isTransferringVehicle = false
        currentTransferVehicle = nil
    end)
    cb({status = "success"})
end)

RegisterNetEvent("qb-garages:client:PlayTransferAnimation", function(plate, newGarageId)
    local ped = PlayerPedId()
    local garageType = currentGarage.type
    local currentGarageId = currentGarage.id
    
    -- Exit vehicle if in one
    if IsPedInAnyVehicle(ped, false) then
        local vehicle = GetVehiclePedIsIn(ped, false)
        TaskLeaveVehicle(ped, vehicle, 0)
        Wait(1500)
    end
    
    transferAnimationActive = true
    
    local currentGarageInfo = nil
    local newGarageInfo = nil
    
    if garageType == "public" then
        currentGarageInfo = Config.Garages[currentGarageId]
    elseif garageType == "job" then
        currentGarageInfo = Config.JobGarages[currentGarageId]
    elseif garageType == "gang" then
        currentGarageInfo = Config.GangGarages[currentGarageId]
    end
    
    local newGarageInfoFound = false
    for k, v in pairs(Config.Garages) do
        if k == newGarageId then
            newGarageInfo = v
            newGarageInfoFound = true
            break
        end
    end
    
    if not newGarageInfoFound and PlayerData.job then
        for k, v in pairs(Config.JobGarages) do
            if k == newGarageId and v.job == PlayerData.job.name then
                newGarageInfo = v
                newGarageInfoFound = true
                break
            end
        end
    end
    
    if not newGarageInfoFound and PlayerData.gang and PlayerData.gang.name ~= "none" then
        for k, v in pairs(Config.GangGarages) do
            if k == newGarageId and v.gang == PlayerData.gang.name then
                newGarageInfo = v
                newGarageInfoFound = true
                break
            end
        end
    end
    
    if not newGarageInfoFound then
        QBCore.Functions.Notify("Target garage not found", "error")
        isTransferringVehicle = false
        transferAnimationActive = false
        currentTransferVehicle = nil
        return
    end
    local animDict = "cellphone@"
    local animName = "cellphone_text_read_base"
    
    RequestAnimDict(animDict)
    while not HasAnimDictLoaded(animDict) do
        Wait(100)
    end
    TaskPlayAnim(ped, animDict, animName, 2.0, 2.0, -1, 51, 0, false, false, false)
    QBCore.Functions.Notify("Arranging vehicle transfer...", "primary", 3000)
    Wait(3000)
    animDict = "missheistdockssetup1clipboard@base"
    animName = "base"
    RequestAnimDict(animDict)
    while not HasAnimDictLoaded(animDict) do
        Wait(100)
    end
    TaskPlayAnim(ped, animDict, animName, 2.0, 2.0, -1, 51, 0, false, false, false)
    QBCore.Functions.Notify("Signing transfer papers...", "primary", 3000)
    Wait(3000)
    ClearPedTasks(ped)
    TriggerServerEvent('qb-garages:server:TransferVehicleToGarage', plate, newGarageId, Config.TransferCost or 500)
    transferAnimationActive = false
    Wait(1000)
    isTransferringVehicle = false
    currentTransferVehicle = nil
end)

RegisterNetEvent('qb-garages:client:TransferComplete', function(newGarageId, plate)
    QBCore.Functions.Notify("Vehicle transferred to " .. newGarageId .. " garage", "success")
    
    -- Refresh the vehicle list
    if currentGarage and isMenuOpen then
        QBCore.Functions.TriggerCallback('qb-garages:server:GetPersonalVehicles', function(vehicles)
            if vehicles then
                SendNUIMessage({
                    action = "refreshVehicles",
                    vehicles = FormatVehiclesForNUI(vehicles)
                })
            end
        end)
    end
end)

RegisterNUICallback('updateVehicleName', function(data, cb)
    local plate = data.plate
    local newName = data.name
    
    if plate and newName then
        TriggerServerEvent('qb-garages:server:UpdateVehicleName', plate, newName)
        cb({status = "success"})
    else
        cb({status = "error", message = "Invalid data"})
    end
end)

RegisterNUICallback('toggleFavorite', function(data, cb)
    local plate = data.plate
    local isFavorite = data.isFavorite
    
    if plate then
        TriggerServerEvent('qb-garages:server:ToggleFavorite', plate, isFavorite)
        cb({status = "success"})
    else
        cb({status = "error", message = "Invalid plate"})
    end
end)

RegisterNUICallback('storeInGang', function(data, cb)
    local plate = data.plate
    local gangName = PlayerData.gang.name
    
    if plate and gangName then
        TriggerServerEvent('qb-garages:server:StoreVehicleInGang', plate, gangName)
        cb({status = "success"})
    else
        cb({status = "error", message = "Invalid data"})
    end
end)


RegisterNUICallback('storeInShared', function(data, cb)
    local plate = data.plate
    
    if plate then
        OpenSharedGarageSelectionUI(plate)
        cb({status = "success"})
    else
        cb({status = "error", message = "Invalid data"})
    end
end)

RegisterNUICallback('removeFromShared', function(data, cb)
    local plate = data.plate
    
    if plate then
        TriggerServerEvent('qb-garages:server:RemoveVehicleFromSharedGarage', plate)
        cb({status = "success"})
    else
        cb({status = "error", message = "Invalid plate"})
    end
end)

function OpenSharedGarageSelectionUI(plate)
    QBCore.Functions.TriggerCallback('qb-garages:server:GetSharedGarages', function(garages)
        if #garages == 0 then
            QBCore.Functions.Notify("You don't have access to any shared garages", "error")
            return
        end
        
        local formattedGarages = {}
        for _, garage in ipairs(garages) do
            table.insert(formattedGarages, {
                id = garage.id,
                name = garage.name,
                owner = garage.isOwner
            })
        end
        
        SendNUIMessage({
            action = "openSharedGarageSelection",
            garages = formattedGarages,
            plate = plate
        })
    end)
end

RegisterNUICallback('storeInSelectedSharedGarage', function(data, cb)
    local plate = data.plate
    local garageId = data.garageId
    
    if not plate or not garageId then
        cb({status = "error", message = "Invalid data"})
        return
    end
    
    TriggerServerEvent('qb-garages:server:TransferVehicleToSharedGarage', plate, garageId)
    
    cb({status = "success"})
end)

function IsSpawnPointClear(coords, radius)
    local vehicles = GetGamePool('CVehicle')
    for i = 1, #vehicles do
        local vehicleCoords = GetEntityCoords(vehicles[i])
        if #(vehicleCoords - coords) <= radius then
            return false
        end
    end
    return true
end

RegisterNetEvent('qb-garages:client:StoreVehicle', function(data)
    local ped = PlayerPedId()
    local garageId = nil
    local garageType = nil
    local garageInfo = nil
    
    if data and data.garageId and data.garageType then
        garageId = data.garageId
        garageType = data.garageType
    elseif currentGarage and currentGarage.id and currentGarage.type then
        garageId = currentGarage.id
        garageType = currentGarage.type
    else
        local pos = GetEntityCoords(PlayerPedId())
        local closestDist = 999999
        local closestGarage = nil
        local closestType = nil
        
        for k, v in pairs(Config.Garages) do
            local dist = #(pos - vector3(v.coords.x, v.coords.y, v.coords.z))
            if dist < closestDist and dist < 10.0 then
                closestDist = dist
                closestGarage = k
                closestType = "public"
            end
        end
        
        if PlayerData.job then
            for k, v in pairs(Config.JobGarages) do
                if PlayerData.job.name == v.job then
                    local dist = #(pos - vector3(v.coords.x, v.coords.y, v.coords.z))
                    if dist < closestDist and dist < 10.0 then
                        closestDist = dist
                        closestGarage = k
                        closestType = "job"
                    end
                end
            end
        end
        
        if PlayerData.gang and PlayerData.gang.name ~= "none" then
            for k, v in pairs(Config.GangGarages) do
                if PlayerData.gang.name == v.gang then
                    local dist = #(pos - vector3(v.coords.x, v.coords.y, v.coords.z))
                    if dist < closestDist and dist < 10.0 then
                        closestDist = dist
                        closestGarage = k
                        closestType = "gang"
                    end
                end
            end
        end
        
        garageId = closestGarage
        garageType = closestType
    end
    
    if not garageId or not garageType then
        QBCore.Functions.Notify("Not in a valid parking zone", "error")
        return
    end
    
    if garageType == "public" then
        garageInfo = Config.Garages[garageId]
    elseif garageType == "job" then
        garageInfo = Config.JobGarages[garageId]
    elseif garageType == "gang" then
        garageInfo = Config.GangGarages[garageId]
    elseif garageType == "shared" then
        garageInfo = sharedGaragesData[garageId]
    end
    
    if not garageInfo then
        QBCore.Functions.Notify("Invalid garage", "error")
        return
    end
    
    local garageCoords = vector3(garageInfo.coords.x, garageInfo.coords.y, garageInfo.coords.z)
    
    local curVeh = GetVehiclePedIsIn(ped, false)
    
    if curVeh == 0 then
        curVeh = GetClosestVehicleInGarage(garageCoords, 15.0)
        
        if curVeh == 0 or not DoesEntityExist(curVeh) then
            QBCore.Functions.Notify("No vehicle found nearby to park", "error")
            return
        end
        
        if GetVehicleNumberOfPassengers(curVeh) > 0 or not IsVehicleSeatFree(curVeh, -1) then
            QBCore.Functions.Notify("Vehicle cannot be stored while occupied", "error")
            return
        end
    end
    
    currentGarage = {id = garageId, type = garageType}
    
    local plate = QBCore.Functions.GetPlate(curVeh)
    local props = QBCore.Functions.GetVehicleProperties(curVeh)
    local fuel = exports['cdn-fuel']:GetFuel(curVeh)
    local engineHealth = GetVehicleEngineHealth(curVeh)
    local bodyHealth = GetVehicleBodyHealth(curVeh)
    
    -- Check if this vehicle belongs to a shared garage
    QBCore.Functions.TriggerCallback('qb-garages:server:GetVehicleSharedGarageId', function(vehicleSharedGarageId)
        
        -- If vehicle is in a shared garage
        if vehicleSharedGarageId then
            print(string.format("^3[DEBUG] Vehicle %s belongs to shared garage %s^7", plate, vehicleSharedGarageId))
            
            -- Check if player has access to this shared garage
            QBCore.Functions.TriggerCallback('qb-garages:server:CheckSharedGarageAccess', function(hasAccess)
                if hasAccess then
                    print(string.format("^2[DEBUG] Player has access to shared garage %s^7", vehicleSharedGarageId))
                    
                    FadeOutVehicle(curVeh, function()
                        -- Store in shared garage with shared_garage_id preserved
                        TriggerServerEvent('qb-garages:server:StoreVehicle', plate, garageId, props, fuel, engineHealth, bodyHealth, "shared", vehicleSharedGarageId)
                        QBCore.Functions.Notify("Vehicle stored in shared garage", "success")
                        
                        -- Refresh the UI if open
                        if isMenuOpen and currentSharedGarageId then
                            QBCore.Functions.TriggerCallback('qb-garages:server:GetSharedGarageVehicles', function(vehicles)
                                if vehicles then
                                    SendNUIMessage({
                                        action = "refreshVehicles",
                                        vehicles = FormatVehiclesForNUI(vehicles)
                                    })
                                end
                            end, currentSharedGarageId)
                        end
                    end)
                else
                    print(string.format("^1[DEBUG] Player does NOT have access to shared garage %s^7", vehicleSharedGarageId))
                    QBCore.Functions.Notify("You don't have access to this shared garage", "error")
                end
            end, vehicleSharedGarageId)
        else
            -- Not a shared garage vehicle, check regular ownership
            print(string.format("^3[DEBUG] Vehicle %s is not in a shared garage, checking ownership^7", plate))
            
            QBCore.Functions.TriggerCallback('qb-garages:server:CheckOwnership', function(isOwner, isInGarage)
                if isOwner or (garageType == "gang" and isInGarage) then
                    FadeOutVehicle(curVeh, function()
                        TriggerServerEvent('qb-garages:server:StoreVehicle', plate, garageId, props, fuel, engineHealth, bodyHealth, garageType, nil)
                        QBCore.Functions.Notify("Vehicle stored in garage", "success")
                        
                        if isMenuOpen then
                            QBCore.Functions.TriggerCallback('qb-garages:server:GetPersonalVehicles', function(vehicles)
                                if vehicles then
                                    SendNUIMessage({
                                        action = "refreshVehicles",
                                        vehicles = FormatVehiclesForNUI(vehicles)
                                    })
                                end
                            end, garageId)
                        end
                    end)
                else
                    QBCore.Functions.Notify("You don't own this vehicle", "error")
                end
            end, plate, garageType)
        end
    end, plate)
end)

function round(num, numDecimalPlaces)
    local mult = 10^(numDecimalPlaces or 0)
    return math.floor(num * mult + 0.5) / mult
end

-- ===================== SHARED GARAGE MANAGEMENT =====================

RegisterNetEvent('qb-garages:client:ManageSharedGarages')
AddEventHandler('qb-garages:client:ManageSharedGarages', function()
    
    if not Config.EnableSharedGarages then
        SendNUIMessage({
            action = "openSharedGarageManager",
            garages = {},
            error = "Shared garages feature is disabled"
        })
        SetNuiFocus(true, true)
        return
    end
    
    QBCore.Functions.TriggerCallback('qb-garages:server:CheckSharedGaragesTables', function(tablesExist)
        if not tablesExist then
            TriggerServerEvent('qb-garages:server:CreateSharedGaragesTables')
            
            SendNUIMessage({
                action = "openSharedGarageManager",
                garages = {},
                error = "Initializing shared garages feature..."
            })
            SetNuiFocus(true, true)
            return
        end
        
        QBCore.Functions.TriggerCallback('qb-garages:server:GetSharedGarages', function(garages)
            sharedGaragesData = {}
            
            local formattedGarages = {}
            
            for _, garage in ipairs(garages) do
                sharedGaragesData[garage.id] = {
                    id = garage.id,
                    name = garage.name,
                    label = garage.name,
                    isOwner = garage.isOwner,
                    accessCode = garage.access_code,
                    spawnPoint = Config.Garages["legion"].spawnPoint,
                    spawnPoints = Config.Garages["legion"].spawnPoints
                }
                
                table.insert(formattedGarages, {
                    id = garage.id,
                    name = garage.name,
                    isOwner = garage.isOwner,
                    accessCode = garage.access_code
                })
            end
            
            SendNUIMessage({
                action = "openSharedGarageManager",
                garages = formattedGarages
            })
            SetNuiFocus(true, true)
        end)
    end)
end)


RegisterNUICallback('manageSharedGarages', function(data, cb)
    TriggerEvent('qb-garages:client:ManageSharedGarages')
    cb({status = "success"})
end)

RegisterNUICallback('createSharedGarage', function(data, cb)
    local garageName = data.name
    
    if not garageName or garageName == "" then
        cb({status = "error", message = "Invalid garage name"})
        return
    end
    
    QBCore.Functions.TriggerCallback('qb-garages:server:CreateSharedGarage', function(success, result)
        if success then
            QBCore.Functions.Notify("Shared garage created successfully. Code: " .. result.code, "success")
            cb({status = "success", garageData = result})
        else
            QBCore.Functions.Notify(result, "error")
            cb({status = "error", message = result})
        end
    end, garageName)
end)

RegisterNUICallback('joinSharedGarage', function(data, cb)
    local accessCode = data.code
    
    if not accessCode or accessCode == "" then
        cb({status = "error", message = "Invalid access code"})
        return
    end
    
    TriggerServerEvent('qb-garages:server:RequestJoinSharedGarage', accessCode)
    cb({status = "success"})
end)

RegisterNUICallback('openSharedGarage', function(data, cb)
    local garageId = data.garageId
    
    if not garageId then
        cb({status = "error", message = "Invalid garage ID"})
        return
    end
    
    local garageInfo = sharedGaragesData[garageId]
    if not garageInfo then
        cb({status = "error", message = "Garage data not found"})
        return
    end
    
    SetNuiFocus(false, false)
    
    TriggerEvent('qb-garages:client:OpenGarage', {
        garageId = garageId,
        garageType = "shared",
        garageInfo = garageInfo
    })
    
    cb({status = "success"})
end)

RegisterNUICallback('manageSharedGarageMembers', function(data, cb)
    local garageId = data.garageId
    
    if not garageId then
        cb({status = "error", message = "Invalid garage ID"})
        return
    end
    
    QBCore.Functions.TriggerCallback('qb-garages:server:GetSharedGarageMembers', function(members)
        if members then
            SendNUIMessage({
                action = "openSharedGarageMembersManager",
                members = members,
                garageId = garageId
            })
            cb({status = "success", members = members})
        else
            cb({status = "error", message = "Failed to fetch members"})
        end
    end, garageId)
end)

RegisterNUICallback('removeSharedGarageMember', function(data, cb)
    local memberId = data.memberId
    local garageId = data.garageId
    
    if not memberId or not garageId then
        cb({status = "error", message = "Invalid data"})
        return
    end
    
    TriggerServerEvent('qb-garages:server:RemoveMemberFromSharedGarage', memberId, garageId)
    cb({status = "success"})
end)

RegisterNUICallback('deleteSharedGarage', function(data, cb)
    local garageId = data.garageId
    
    if not garageId then
        cb({status = "error", message = "Invalid garage ID"})
        return
    end
    
    TriggerServerEvent('qb-garages:server:DeleteSharedGarage', garageId)
    cb({status = "success"})
end)

RegisterNetEvent('qb-garages:client:ReceiveJoinRequest', function(data)
    table.insert(pendingJoinRequests, data)
    
    QBCore.Functions.Notify(data.requesterName .. " wants to join your " .. data.garageName .. " garage", "primary", 10000)
    
    SetNuiFocus(true, true)
    SendNUIMessage({
        action = "openJoinRequest",
        request = data
    })
end)

RegisterNUICallback('handleJoinRequest', function(data, cb)
    local requestId = data.requestId
    local approved = data.approved
    
    if not requestId then
        cb({status = "error", message = "Invalid request ID"})
        return
    end
    
    local requestData = nil
    for i, request in ipairs(pendingJoinRequests) do
        if request.requesterId == requestId then
            requestData = request
            table.remove(pendingJoinRequests, i)
            break
        end
    end
    
    if not requestData then
        cb({status = "error", message = "Request not found"})
        return
    end
    
    if approved then
        TriggerServerEvent('qb-garages:server:ApproveJoinRequest', requestData)
    else
        TriggerServerEvent('qb-garages:server:DenyJoinRequest', requestData)
    end
    
    cb({status = "success"})
end)

RegisterNetEvent('qb-garages:client:RefreshVehicleList', function()
    if not currentGarage or not isMenuOpen then return end
    
    local garageId = currentGarage.id
    local garageType = currentGarage.type
    
    if garageType == "public" then
        QBCore.Functions.TriggerCallback('qb-garages:server:GetPersonalVehicles', function(vehicles)
            if vehicles then
                SendNUIMessage({
                    action = "refreshVehicles",
                    vehicles = FormatVehiclesForNUI(vehicles)
                })
            end
        end, garageId)
    elseif garageType == "gang" then
        QBCore.Functions.TriggerCallback('qb-garages:server:GetGangVehicles', function(vehicles)
            if vehicles then
                SendNUIMessage({
                    action = "refreshVehicles",
                    vehicles = FormatVehiclesForNUI(vehicles)
                })
            end
        end, PlayerData.gang.name, garageId)
    elseif garageType == "shared" then
        QBCore.Functions.TriggerCallback('qb-garages:server:GetSharedGarageVehicles', function(vehicles)
            if vehicles then
                SendNUIMessage({
                    action = "refreshVehicles",
                    vehicles = FormatVehiclesForNUI(vehicles)
                })
            end
        end, garageId)
    end
end)

RegisterNetEvent('qb-garages:client:VehicleTransferCompleted', function(successful, plate)
    if successful then
        if currentGarage and isMenuOpen then
            local garageId = currentGarage.id
            local garageType = currentGarage.type
            
            if garageType == "public" then
                QBCore.Functions.TriggerCallback('qb-garages:server:GetPersonalVehicles', function(vehicles)
                    if vehicles then
                        SendNUIMessage({
                            action = "refreshVehicles",
                            vehicles = FormatVehiclesForNUI(vehicles)
                        })
                    end
                end, garageId)
            elseif garageType == "shared" then
                QBCore.Functions.TriggerCallback('qb-garages:server:GetSharedGarageVehicles', function(vehicles)
                    if vehicles then
                        SendNUIMessage({
                            action = "refreshVehicles",
                            vehicles = FormatVehiclesForNUI(vehicles)
                        })
                    end
                end, garageId)
            end
        end
    end
end)

function GetVehicleClassName(vehicleClass)
    local classes = {
        [0] = "Compact",
        [1] = "Sedan",
        [2] = "SUV",
        [3] = "Coupe",
        [4] = "Muscle",
        [5] = "Sports Classic",
        [6] = "Sports",
        [7] = "Super",
        [8] = "Motorcycle",
        [9] = "Off-road",
        [10] = "Industrial",
        [11] = "Utility",
        [12] = "Van",
        [13] = "Cycle",
        [14] = "Boat",
        [15] = "Helicopter",
        [16] = "Plane",
        [17] = "Service",
        [18] = "Emergency",
        [19] = "Military",
        [20] = "Commercial",
        [21] = "Train",
        [22] = "Open Wheel"
    }
    return classes[vehicleClass] or "Unknown"
end

function GetVehicleHoverInfo(vehicle)
    if not DoesEntityExist(vehicle) then return nil end
    
    local ped = PlayerPedId()
    local plate = QBCore.Functions.GetPlate(vehicle)
    local model = GetEntityModel(vehicle)
    local displayName = GetDisplayNameFromVehicleModel(model)
    local make = GetMakeNameFromVehicleModel(model)
    local vehicleClass = GetVehicleClass(vehicle)
    local className = GetVehicleClassName(vehicleClass)
    local inVehicle = (GetVehiclePedIsIn(ped, false) == vehicle)
    local engineHealth = GetVehicleEngineHealth(vehicle)
    local bodyHealth = GetVehicleBodyHealth(vehicle)
    local fuelLevel = 0
    
    if GetResourceState('cdn-fuel') ~= 'missing' then
        fuelLevel = exports['cdn-fuel']:GetFuel(vehicle)
    elseif GetResourceState('ps-fuel') ~= 'missing' then
        fuelLevel = exports['ps-fuel']:GetFuel(vehicle)
    elseif GetResourceState('cdn-fuel') ~= 'missing' then
        fuelLevel = exports['cdn-fuel']:GetFuel(vehicle)
    else
        fuelLevel = GetVehicleFuelLevel(vehicle)
    end
    
    local vehicleInfo = nil
    QBCore.Functions.TriggerCallback('qb-garages:server:GetVehicleInfo', function(info)
        vehicleInfo = info
    end, plate)
    
    local info = {
        plate = plate,
        model = displayName,
        make = make,
        class = className,
        netId = NetworkGetNetworkIdFromEntity(vehicle),
        inVehicle = inVehicle,
        fuel = fuelLevel,
        engine = engineHealth / 10,
        body = bodyHealth / 10,
        ownerName = "You",
        garage = "Unknown",
        state = 1 
    }
    
    if vehicleInfo then
        info.name = vehicleInfo.name or info.model
        info.ownerName = vehicleInfo.ownerName or "You"
        info.garage = vehicleInfo.garage or "Unknown"
        info.state = vehicleInfo.state or 1
    end
    
    return info
end


function RayCastGamePlayCamera(distance)
    local cameraRotation = GetGameplayCamRot()
    local cameraCoord = GetGameplayCamCoord()
    local direction = RotationToDirection(cameraRotation)
    local destination = {
        x = cameraCoord.x + direction.x * distance,
        y = cameraCoord.y + direction.y * distance,
        z = cameraCoord.z + direction.z * distance
    }
    local rayHandle = StartExpensiveSynchronousShapeTestLosProbe(
        cameraCoord.x, cameraCoord.y, cameraCoord.z,
        destination.x, destination.y, destination.z,
        1, PlayerPedId(), 0
    )
    local _, hit, endCoords, _, entityHit = GetShapeTestResult(rayHandle)
    return hit, endCoords, entityHit
end

function RotationToDirection(rotation)
    local adjustedRotation = {
        x = (math.pi / 180) * rotation.x,
        y = (math.pi / 180) * rotation.y,
        z = (math.pi / 180) * rotation.z
    }
    local direction = {
        x = -math.sin(adjustedRotation.z) * math.abs(math.cos(adjustedRotation.x)),
        y = math.cos(adjustedRotation.z) * math.abs(math.cos(adjustedRotation.x)),
        z = math.sin(adjustedRotation.x)
    }
    return direction
end

RegisterNUICallback('enterVehicle', function(data, cb)
    local netId = data.netId
    local vehicle = NetworkGetEntityFromNetworkId(netId)
    
    if DoesEntityExist(vehicle) then
        local ped = PlayerPedId()
        TaskEnterVehicle(ped, vehicle, -1, -1, 1.0, 1, 0)
    end
    
    cb({status = "success"})
end)

RegisterNUICallback('exitVehicle', function(data, cb)
    local ped = PlayerPedId()
    TaskLeaveVehicle(ped, GetVehiclePedIsIn(ped, false), 0)
    cb({status = "success"})
end)

RegisterNUICallback('storeHoveredVehicle', function(data, cb)
    local plate = data.plate
    local netId = data.netId
    local vehicle = NetworkGetEntityFromNetworkId(netId)
    
    if DoesEntityExist(vehicle) then
        local garageId, garageType = GetClosestGarage()
        
        if garageId then
            StoreVehicleInGarage(vehicle, garageId, garageType)
            cb({status = "success"})
        else
            QBCore.Functions.Notify("Not near a garage", "error")
            cb({status = "error", message = "Not near a garage"})
        end
    else
        cb({status = "error", message = "Vehicle not found"})
    end
end)

RegisterNUICallback('showVehicleDetails', function(data, cb)
    local plate = data.plate
    local netId = data.netId
    local vehicle = NetworkGetEntityFromNetworkId(netId)
    
    if DoesEntityExist(vehicle) then
        if vehicleHoverInfo then
            showVehicleInfoModal(vehicleHoverInfo)
            cb({status = "success"})
        else
            cb({status = "error", message = "Vehicle info not found"})
        end
    else
        cb({status = "error", message = "Vehicle not found"})
    end
end)

function GetClosestGarage()
    local playerCoords = GetEntityCoords(PlayerPedId())
    local closestDistance = 999999
    local closestGarage = nil
    local closestGarageType = nil
    
    for k, v in pairs(Config.Garages) do
        local distance = #(playerCoords - vector3(v.coords.x, v.coords.y, v.coords.z))
        if distance < closestDistance and distance < 30.0 then
            closestDistance = distance
            closestGarage = k
            closestGarageType = "public"
        end
    end
    
    for k, v in pairs(Config.JobGarages) do
        if PlayerData.job and PlayerData.job.name == v.job then
            local distance = #(playerCoords - vector3(v.coords.x, v.coords.y, v.coords.z))
            if distance < closestDistance and distance < 30.0 then
                closestDistance = distance
                closestGarage = k
                closestGarageType = "job"
            end
        end
    end
    
    for k, v in pairs(Config.GangGarages) do
        if PlayerData.gang and PlayerData.gang.name == v.gang then
            local distance = #(playerCoords - vector3(v.coords.x, v.coords.y, v.coords.z))
            if distance < closestDistance and distance < 30.0 then
                closestDistance = distance
                closestGarage = k
                closestGarageType = "gang"
            end
        end
    end
    
    return closestGarage, closestGarageType
end

function StoreVehicleInGarage(vehicle, garageId, garageType)
    local plate = QBCore.Functions.GetPlate(vehicle)
    local props = QBCore.Functions.GetVehicleProperties(vehicle)
    local fuel = 0
    
    if GetResourceState('cdn-fuel') ~= 'missing' then
        fuel = exports['cdn-fuel']:GetFuel(vehicle)
    elseif GetResourceState('ps-fuel') ~= 'missing' then
        fuel = exports['ps-fuel']:GetFuel(vehicle)
    elseif GetResourceState('cdn-fuel') ~= 'missing' then
        fuel = exports['cdn-fuel']:GetFuel(vehicle)
    else
        fuel = GetVehicleFuelLevel(vehicle)
    end
    
    local engineHealth = GetVehicleEngineHealth(vehicle)
    local bodyHealth = GetVehicleBodyHealth(vehicle)
    
    FadeOutVehicle(vehicle, function()
        TriggerServerEvent('qb-garages:server:StoreVehicle', plate, garageId, props, fuel, engineHealth, bodyHealth, garageType)
        QBCore.Functions.Notify("Vehicle stored in garage", "success")
    end)
end

CreateThread(function()
    if Config.EnableImpound then
        for k, v in pairs(Config.ImpoundLots) do
            local blip = AddBlipForCoord(v.coords.x, v.coords.y, v.coords.z)
            SetBlipSprite(blip, v.blip.sprite)
            SetBlipDisplay(blip, v.blip.display)
            SetBlipScale(blip, v.blip.scale)
            SetBlipAsShortRange(blip, v.blip.shortRange)
            SetBlipColour(blip, v.blip.color)
            BeginTextCommandSetBlipName("STRING")
            AddTextComponentSubstringPlayerName(v.label)
            EndTextCommandSetBlipName(blip)
            
            table.insert(impoundBlips, blip)
        end
    end
end)



RegisterNetEvent('qb-garages:client:OpenImpoundLot')
AddEventHandler('qb-garages:client:OpenImpoundLot', function(data)
    local impoundId = data.impoundId
    local impoundInfo = Config.ImpoundLots[impoundId]
    
    if not impoundInfo then
        QBCore.Functions.Notify("Invalid impound lot", "error")
        return
    end
    
    currentImpoundLot = {id = impoundId, label = impoundInfo.label, coords = impoundInfo.coords}
    
    QBCore.Functions.TriggerCallback('qb-garages:server:GetImpoundedVehicles', function(vehicles)
        if vehicles and #vehicles > 0 then
            SetNuiFocus(true, true)
            SendNUIMessage({
                action = "setImpoundOnly",
                forceImpoundOnly = true
            })
            
            SendNUIMessage({
                action = "openImpound",
                vehicles = FormatVehiclesForNUI(vehicles),
                impound = {
                    name = impoundInfo.label,
                    id = impoundId,
                    location = impoundInfo.label
                }
            })
        else
            QBCore.Functions.Notify("No vehicles in impound", "error")
        end
    end)
end)

RegisterCommand('impound', function(source, args)
    if not PlayerData.job or not Config.ImpoundJobs[PlayerData.job.name] then
        QBCore.Functions.Notify("You are not authorized to impound vehicles", "error")
        return
    end
    
    local impoundFine = tonumber(args[1]) or Config.ImpoundFee  -- Default to config fee if not specified
    
    impoundFine = math.max(100, math.min(10000, impoundFine))  -- Between $100 and $10,000
    
    local ped = PlayerPedId()
    local coords = GetEntityCoords(ped)
    local vehicle = nil
    
    if IsPedInAnyVehicle(ped, false) then
        vehicle = GetVehiclePedIsIn(ped, false)
    else
        vehicle = GetClosestVehicle(coords.x, coords.y, coords.z, 5.0, 0, 71)
    end
    
    if not DoesEntityExist(vehicle) then
        QBCore.Functions.Notify("No vehicle nearby to impound", "error")
        return
    end
    
    local plate = QBCore.Functions.GetPlate(vehicle)
    if not plate then
        QBCore.Functions.Notify("Could not read vehicle plate", "error")
        return
    end
    
    local props = QBCore.Functions.GetVehicleProperties(vehicle)
    
    local dialog = exports['qb-input']:ShowInput({
        header = "Impound Vehicle",
        submitText = "Submit",
        inputs = {
            {
                text = "Reason for impound",
                name = "reason", 
                type = "text"
            }
        }
    })
    
    if dialog and dialog.reason then
        local impoundType = "police"
        
        TaskStartScenarioInPlace(ped, "PROP_HUMAN_CLIPBOARD", 0, true)
        QBCore.Functions.Progressbar("impounding_vehicle", "Impounding Vehicle...", 10000, false, true, {
            disableMovement = true,
            disableCarMovement = true,
            disableMouse = false,
            disableCombat = true,
        }, {}, {}, {}, function() -- Done
            ClearPedTasks(ped)
            
            TriggerServerEvent('qb-garages:server:ImpoundVehicleWithParams', plate, props, dialog.reason, impoundType, 
                PlayerData.job.name, PlayerData.charinfo.firstname .. " " .. PlayerData.charinfo.lastname, impoundFine)
            
            FadeOutVehicle(vehicle, function()
                DeleteVehicle(vehicle)
                QBCore.Functions.Notify("Vehicle impounded with $" .. impoundFine .. " fine", "success")
            end)
        end, function() -- Cancel
            ClearPedTasks(ped)
            QBCore.Functions.Notify("Impound cancelled", "error")
        end)
    end
end, false)

TriggerEvent('chat:addSuggestion', '/impound', 'Impound a vehicle with custom fine', {
    { name = "fine", help = "Fine amount ($100-$10,000)" }
})


function OpenImpoundUI(vehicles, impoundInfo, impoundId)
    local formattedVehicles = {}
   
    for i, vehicle in ipairs(vehicles) do
        local vehicleInfo = QBCore.Shared.Vehicles[vehicle.vehicle]
        if vehicleInfo then
            local enginePercent = round(vehicle.engine / 10, 1)
            local bodyPercent = round(vehicle.body / 10, 1)
            local fuelPercent = vehicle.fuel or 100
           
            local displayName = vehicleInfo.name
            if vehicle.custom_name and vehicle.custom_name ~= "" then
                displayName = vehicle.custom_name
            end
           
            local totalFee = Config.ImpoundFee  -- Default fee
            if vehicle.impoundfee ~= nil then
                local customFee = tonumber(vehicle.impoundfee)
                if customFee and customFee > 0 then
                    totalFee = customFee
                end
            end
           
            local reasonString = vehicle.impoundreason or "No reason specified"
            if reasonString and #reasonString > 50 then
                reasonString = reasonString:sub(1, 47) .. "..."
            end
           
            table.insert(formattedVehicles, {
                id = i,
                plate = vehicle.plate,
                model = vehicle.vehicle,
                name = displayName,
                fuel = fuelPercent,
                engine = enginePercent,
                body = bodyPercent,
                impoundFee = totalFee,
                impoundReason = reasonString,
                impoundType = vehicle.impoundtype or "police",
                impoundedBy = vehicle.impoundedby or "Unknown Officer"
            })
        end
    end
   
    SetNuiFocus(true, true)
    SendNUIMessage({
        action = "openImpound",
        vehicles = formattedVehicles,
        impound = {
            name = impoundInfo.label,
            id = impoundId,
            location = impoundInfo.label
        }
    })
end

RegisterNUICallback('releaseImpoundedVehicle', function(data, cb)
    local plate = data.plate
    local impoundId = currentImpoundLot.id
    local fee = data.fee
    
    print("Searching for plate:", plate)
    if not plate or not impoundId then
        cb({status = "error", message = "Invalid data"})
        return
    end
    
    QBCore.Functions.TriggerCallback('qb-garages:server:CanPayImpoundFee', function(canPay)
        if canPay then
            local impoundInfo = Config.ImpoundLots[impoundId]
            local spawnPoint = FindClearSpawnPoint(impoundInfo.spawnPoints)
            
            if not spawnPoint then
                QBCore.Functions.Notify("All spawn locations are blocked!", "error")
                cb({status = "error", message = "Spawn blocked"})
                return
            end
            
            QBCore.Functions.TriggerCallback('qb-garages:server:GetVehicleByPlate', function(vehData)
                
                print(vehData)
                if vehData then
                    QBCore.Functions.SpawnVehicle(vehData.vehicle, function(veh)
                        SetEntityHeading(veh, spawnPoint.w)
                        SetEntityCoords(veh, spawnPoint.x, spawnPoint.y, spawnPoint.z)
                        
                        exports['cdn-fuel']:SetFuel(veh, vehData.fuel or 100)
                        SetVehicleNumberPlateText(veh, plate)
                        
                        FadeInVehicle(veh)
                        
                        QBCore.Functions.TriggerCallback('qb-garages:server:GetVehicleProperties', function(properties)
                            if properties then
                                QBCore.Functions.SetVehicleProperties(veh, properties)
                                
                                local engineHealth = math.max(vehData.engine * 10, 200.0)
                                local bodyHealth = math.max(vehData.body * 10, 200.0)
                                
                                SetVehicleEngineHealth(veh, engineHealth)
                                SetVehicleBodyHealth(veh, bodyHealth)
                                SetVehicleDirtLevel(veh, 0.0) -- Clean vehicle
                                
                                FixEngineSmoke(veh)
                                
                                SetVehicleUndriveable(veh, false)
                                SetVehicleEngineOn(veh, true, true, false)
                                
                                TriggerServerEvent('qb-garages:server:PayImpoundFee', plate, fee)
                                
                                QBCore.Functions.Notify("Vehicle released from impound", "success")
                                cb({status = "success"})
                                TriggerEvent('vehiclekeys:client:SetOwner', plate)
                            else
                                QBCore.Functions.Notify("Failed to load vehicle properties", "error")
                                cb({status = "error", message = "Failed to load vehicle"})
                            end
                        end, plate)
                    end, vector3(spawnPoint.x, spawnPoint.y, spawnPoint.z), true)
                else
                    QBCore.Functions.Notify("Vehicle data not found", "error")
                    cb({status = "error", message = "Vehicle not found"})
                end
            end, plate)
        else
            QBCore.Functions.Notify("You don't have enough money to pay the impound fee", "error")
            cb({status = "error", message = "Insufficient funds"})
        end
    end, fee)
end)

RegisterNetEvent('qb-garages:client:ImpoundVehicle')
AddEventHandler('qb-garages:client:ImpoundVehicle', function()
    if not PlayerData.job or not Config.ImpoundJobs[PlayerData.job.name] then
        QBCore.Functions.Notify("You are not authorized to impound vehicles", "error")
        return
    end
    
    local ped = PlayerPedId()
    local coords = GetEntityCoords(ped)
    local vehicle = nil
    
    if IsPedInAnyVehicle(ped, false) then
        vehicle = GetVehiclePedIsIn(ped, false)
    else
        vehicle = GetClosestVehicle(coords.x, coords.y, coords.z, 5.0, 0, 71)
    end
    
    if not DoesEntityExist(vehicle) then
        QBCore.Functions.Notify("No vehicle nearby to impound", "error")
        return
    end
    
    local plate = QBCore.Functions.GetPlate(vehicle)
    if not plate then
        QBCore.Functions.Notify("Could not read vehicle plate", "error")
        return
    end
    
    local props = QBCore.Functions.GetVehicleProperties(vehicle)
    local model = GetEntityModel(vehicle)
    local displayName = GetDisplayNameFromVehicleModel(model)
    local impoundType = "police"
    
    local dialog = exports['qb-input']:ShowInput({
        header = "Impound Vehicle",
        submitText = "Submit",
        inputs = {
            {
                text = "Reason for Impound",
                name = "reason",
                type = "text",
                isRequired = true
            },
            {
                text = "Impound Type",
                name = "type",
                type = "select",
                options = Config.ImpounderTypes,
                default = "police"
            }
        }
    })
    
    if dialog and dialog.reason then
        TaskStartScenarioInPlace(ped, "PROP_HUMAN_CLIPBOARD", 0, true)
        QBCore.Functions.Progressbar("impounding_vehicle", "Impounding Vehicle...", 10000, false, true, {
            disableMovement = true,
            disableCarMovement = true,
            disableMouse = false,
            disableCombat = true,
        }, {}, {}, {}, function() 
            ClearPedTasks(ped)
            
            TriggerServerEvent('qb-garages:server:ImpoundVehicle', plate, props, dialog.reason, dialog.type, PlayerData.job.name, PlayerData.charinfo.firstname .. " " .. PlayerData.charinfo.lastname)
            
            FadeOutVehicle(vehicle, function()
                DeleteVehicle(vehicle)
                QBCore.Functions.Notify("Vehicle impounded successfully", "success")
            end)
        end, function() 
            ClearPedTasks(ped)
            QBCore.Functions.Notify("Impound cancelled", "error")
        end)
    end
end)

RegisterNUICallback('closeImpound', function(data, cb)
    SetNuiFocus(false, false)
    cb({status = "success"})
end)
--  
-- 
-- 
--                                                                          
-- 
-- 
-- 
--                                                                          
-- 
-- 
-- 
--                                                                          
-- 
-- 
-- 
--                                                                          
-- 
-- 
-- 
--                                                                          
-- 
-- 
-- 
--                                                                          
-- 
-- 
-- 
--                                                                          
-- 
-- 
-- 
--                                                                          
-- 
-- 
-- 
--                                                                          
-- 
-- 
-- 
--                                                                          
-- 
-- 
-- 
--                                                                          
-- 
-- 
-- 
--                                                                          
-- 
-- 
-- 
--                                                                          
-- 
--             
