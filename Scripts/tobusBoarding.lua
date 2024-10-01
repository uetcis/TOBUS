if PLANE_ICAO == "A319" or PLANE_ICAO == "A20N" or PLANE_ICAO == "A321"  or PLANE_ICAO == "A346"
then

local VERSION = "1.4-2-hotbso"
logMsg("TOBUS " .. VERSION .. " startup")

 --http library import
local xml2lua = require("xml2lua")
local handler = require("xmlhandler.tree")
local socket = require "socket"
local http = require "socket.http"
local LIP = require("LIP")

local wait_until_speak = 0
local speak_string

local intendedPassengerNumber
local intended_no_pax_set = false

local tls_no_pax        -- dataref_table
local MAX_PAX_NUMBER = 224

local SETTINGS_FILENAME = "/tobus/tobus_settings.ini"
local SIMBRIEF_FLIGHTPLAN_FILENAME = "simbrief.xml"
local SIMBRIEF_ACCOUNT_NAME = ""
local RANDOMIZE_SIMBRIEF_PASSENGER_NUMBER = false
local USE_SECOND_DOOR = false
local CLOSE_DOORS = true
local LEAVE_DOOR1_OPEN = true
local SIMBRIEF_FLIGHTPLAN = {}

local function openDoorsForBoarding()
    passengerDoorArray[0] = 2
    if USE_SECOND_DOOR then
        if PLANE_ICAO == "A319" or PLANE_ICAO == "A20N" then
            passengerDoorArray[2] = 2
        end
        if PLANE_ICAO == "A321" or PLANE_ICAO == "A346" then
            passengerDoorArray[6] = 2
        end
    end
    cargoDoorArray[0] = 2
    cargoDoorArray[1] = 2
end

local function closeDoorsAfterBoarding()
    if not CLOSE_DOORS then return end

    if not LEAVE_DOOR1_OPEN then
        passengerDoorArray[0] = 0
    end

    if USE_SECOND_DOOR then
        if PLANE_ICAO == "A319" or PLANE_ICAO == "A20N" then
            passengerDoorArray[2] = 0
        end

        if PLANE_ICAO == "A321" or PLANE_ICAO == "A346" then
            passengerDoorArray[6] = 0
        end
    end
    cargoDoorArray[0] = 0
    cargoDoorArray[1] = 0
end

local function setDefaultBoardingState()
    set("AirbusFBW/NoPax", 0)
    set("AirbusFBW/PaxDistrib", math.random(35, 60) / 100)
    passengersBoarded = 0
    boardingPaused = false
    boardingStopped = false
    boardingActive = true
end

local function playChimeSound(boarding)
    command_once( "AirbusFBW/CheckCabin" )
    if boarding then
        speak_string = "Boarding Completed"
    else
        speak_string = "Deboarding Completed"
    end

    wait_until_speak = os.time() + 0.5
    intended_no_pax_set = false
end

local function boardInstantly()
    set("AirbusFBW/NoPax", intendedPassengerNumber)
    passengersBoarded = intendedPassengerNumber
    boardingActive = false
    boardingCompleted = true
    playChimeSound(true)
    command_once("AirbusFBW/SetWeightAndCG")
    closeDoorsAfterBoarding()
end

local function deboardInstantly()
    set("AirbusFBW/NoPax", 0)
    deboardingActive = false
    deboardingCompleted = true
    playChimeSound(false)
    command_once("AirbusFBW/SetWeightAndCG")
    closeDoorsAfterBoarding()
end

local function setRandomNumberOfPassengers()
    local passengerDistributionGroup = math.random(0, 100)

    if passengerDistributionGroup < 2 then
        intendedPassengerNumber = math.random(math.floor(MAX_PAX_NUMBER * 0.22), math.floor(MAX_PAX_NUMBER * 0.54))
        return
    end

    if passengerDistributionGroup < 16 then
        intendedPassengerNumber = math.random(math.floor(MAX_PAX_NUMBER * 0.54), math.floor(MAX_PAX_NUMBER * 0.72))
        return
    end

    if passengerDistributionGroup < 58 then
        intendedPassengerNumber = math.random(math.floor(MAX_PAX_NUMBER * 0.72), math.floor(MAX_PAX_NUMBER * 0.87))
        return
    end

    intendedPassengerNumber = math.random(math.floor(MAX_PAX_NUMBER * 0.87), MAX_PAX_NUMBER)
end

local function startBoardingOrDeboarding()
    boardingPaused = false
    boardingActive = false
    boardingCompleted = false
    deboardingCompleted = false
    deboardingPaused = false
end

local function resetAllParameters()
    passengersBoarded = 0
    intendedPassengerNumber = math.floor(MAX_PAX_NUMBER * 0.66)
    boardingActive = false
    deboardingActive = false
    lastTimeBoardingCheck = os.time()
    boardingSpeedMode = 3
    if (USE_SECOND_DOOR) then
        secondsPerPassenger = 5
    else
        secondsPerPassenger = 9
    end
    boardingPaused = false
    deboardingPaused = false
    deboardingCompleted = false
    boardingCompleted = false
    isTobusWindowDisplayed = false
    isSettingsWindowDisplayed = false
end

-- frame loop, efficient coding please
function tobusBoarding()
    local now = os.time()

    if speak_string and now > wait_until_speak then
      XPLMSpeakString(speak_string)
      speak_string = nil
    end

    if boardingActive then
        if passengersBoarded <= intendedPassengerNumber
         and (now - lastTimeBoardingCheck) > math.random(secondsPerPassenger - 2, secondsPerPassenger + 2) then
            passengersBoarded = passengersBoarded + 1
            tls_no_pax[0] = passengersBoarded
            command_once("AirbusFBW/SetWeightAndCG")
            lastTimeBoardingCheck = os.time()
        end

        if passengersBoarded == intendedPassengerNumber and not boardingCompleted then
            boardingCompleted = true
            boardingActive = false
            closeDoorsAfterBoarding()
            if not isTobusWindowDisplayed then
                buildTobusWindow()
            end
            playChimeSound(true)
        end

    elseif deboardingActive then
        if passengersBoarded >= 0
         and (now - lastTimeBoardingCheck) > math.random(secondsPerPassenger - 2, secondsPerPassenger + 2) then
            passengersBoarded = passengersBoarded - 1
            tls_no_pax[0] = passengersBoarded
            command_once("AirbusFBW/SetWeightAndCG")
            lastTimeBoardingCheck = os.time()
        end

        if passengersBoarded == 0 and not deboardingCompleted then
            deboardingCompleted = true
            deboardingActive = false
            closeDoorsAfterBoarding()
            if isTobusWindowDisplayed == false then
                buildTobusWindow()
            end
            playChimeSound(false)
        end
    end
end

local function readSettings()
    local f = io.open(SCRIPT_DIRECTORY..SETTINGS_FILENAME)
    if f == nil then return end

    f:close()
    local settings = LIP.load(SCRIPT_DIRECTORY..SETTINGS_FILENAME)

    settings.simbrief = settings.simbrief or {}    -- for backwards compatibility
    settings.doors = settings.doors or {}

    if settings.simbrief.username ~= nil then
        SIMBRIEF_ACCOUNT_NAME = settings.simbrief.username
    end

    RANDOMIZE_SIMBRIEF_PASSENGER_NUMBER = settings.simbrief.randomizePassengerNumber or
                                                RANDOMIZE_SIMBRIEF_PASSENGER_NUMBER

    USE_SECOND_DOOR = settings.doors.useSecondDoor or USE_SECOND_DOOR
    CLOSE_DOORS = settings.doors.closeDoors or CLOSE_DOORS
    LEAVE_DOOR1_OPEN = settings.doors.leaveDoor1Open or LEAVE_DOOR1_OPEN

end

local function saveSettings()
    local newSettings = {}
    newSettings.simbrief = {}
    newSettings.simbrief.username = SIMBRIEF_ACCOUNT_NAME
    newSettings.simbrief.randomizePassengerNumber = RANDOMIZE_SIMBRIEF_PASSENGER_NUMBER

    newSettings.doors = {}
    newSettings.doors.useSecondDoor = USE_SECOND_DOOR
    newSettings.doors.closeDoors = CLOSE_DOORS
    newSettings.doors.leaveDoor1Open = LEAVE_DOOR1_OPEN
    LIP.save(SCRIPT_DIRECTORY..SETTINGS_FILENAME, newSettings);
end

local function fetchData()
    if SIMBRIEF_ACCOUNT_NAME == nil then
      logMsg("No simbrief username has been configured")
      return false
    end

    local response, statusCode = http.request("http://www.simbrief.com/api/xml.fetcher.php?username=" .. SIMBRIEF_ACCOUNT_NAME)

    if statusCode ~= 200 then
      logMsg("Simbrief API is not responding")
      return false
    end

    local f = io.open(SCRIPT_DIRECTORY..SIMBRIEF_FLIGHTPLAN_FILENAME, "w")
    f:write(response)
    f:close()

    logMsg("Simbrief XML data downloaded")
    return true
end

local function readXML()
    local xfile = xml2lua.loadFile(SCRIPT_DIRECTORY..SIMBRIEF_FLIGHTPLAN_FILENAME)
    local parser = xml2lua.parser(handler)
    parser:parse(xfile)

    SIMBRIEF_FLIGHTPLAN["Status"] = handler.root.OFP.fetch.status

    if SIMBRIEF_FLIGHTPLAN["Status"] ~= "Success" then
      logMsg("XML status is not success")
      return false
    end

    intendedPassengerNumber = tonumber(handler.root.OFP.weights.pax_count)
    if RANDOMIZE_SIMBRIEF_PASSENGER_NUMBER then
	    intendedPassengerNumber = math.random(math.floor(intendedPassengerNumber * 0.92), intendedPassengerNumber)
    end
end


-- init random and warm up
math.randomseed(os.time())
math.random()
math.random()
math.random()


if not SUPPORTS_FLOATING_WINDOWS then
    -- to make sure the script doesn't stop old FlyWithLua versions
    logMsg("imgui not supported by your FlyWithLua version")
    return
end


if PLANE_ICAO == "A319" then
    MAX_PAX_NUMBER = 145
end

if PLANE_ICAO == "A321" then
    DataRef("a321EngineType", "AirbusFBW/EngineTypeIndex")
    if (a321EngineType == 0 or a321EngineType == 1) then
        MAX_PAX_NUMBER = 220
    else
        MAX_PAX_NUMBER = 224
    end
end

if PLANE_ICAO == "A20N" then
    MAX_PAX_NUMBER = 188
end

if PLANE_ICAO == "A346" then
    MAX_PAX_NUMBER = 440
end


-- init gloabl variables
readSettings()

local function delayed_init()
    if tls_no_pax ~= nil then return end
    tls_no_pax = dataref_table("AirbusFBW/NoPax")
    passengerDoorArray = dataref_table("AirbusFBW/PaxDoorModeArray")
    cargoDoorArray = dataref_table("AirbusFBW/CargoDoorModeArray")
    resetAllParameters()
end

function tobusOnBuild(tobus_window, x, y)
    if boardingActive and not boardingCompleted then
        imgui.PushStyleColor(imgui.constant.Col.Text, 0xFF95FFF8)
        imgui.TextUnformatted(string.format("Boarding in progress %s / %s boarded", passengersBoarded, intendedPassengerNumber))
        imgui.PopStyleColor()
    end

    if deboardingActive and not deboardingCompleted then
        imgui.PushStyleColor(imgui.constant.Col.Text, 0xFF95FFF8)
        imgui.TextUnformatted(string.format("Deboarding in progress %s / %s deboarded", passengersBoarded, intendedPassengerNumber))
        imgui.PopStyleColor()
    end

    if boardingCompleted then
        imgui.PushStyleColor(imgui.constant.Col.Text, 0xFF43B54B)
        imgui.TextUnformatted("Boarding completed!!!")
        imgui.PopStyleColor()
    end

    if deboardingCompleted then
        imgui.PushStyleColor(imgui.constant.Col.Text, 0xFF43B54B)
        imgui.TextUnformatted("Deboarding completed!!!")
        imgui.PopStyleColor()
    end

    if not (boardingActive or deboardingActive) then
        local pn = tls_no_pax[0]
        if not intended_no_pax_set or passengersBoarded ~= pn  then
            intendedPassengerNumber = pn
            passengersBoarded = pn
        end

        local passengeraNumberChanged, newPassengerNumber
        = imgui.SliderInt("Passengers number", intendedPassengerNumber, 0, MAX_PAX_NUMBER, "Value: %d")

        if passengeraNumberChanged then
            intendedPassengerNumber = newPassengerNumber
            intended_no_pax_set = true
        end
        imgui.SameLine()

        if imgui.Button("Get from simbrief") then
            if fetchData() then
                readXML()
                intended_no_pax_set = true
            end
        end

        if imgui.Button("Set random passenger number") then
            setRandomNumberOfPassengers()
            intended_no_pax_set = true
        end

    end

    if not boardingActive and not deboardingActive then
        imgui.SameLine()

        if deboardingPaused == false then
            if imgui.Button("Start Boarding") then
                set("AirbusFBW/NoPax", 0)
                set("AirbusFBW/PaxDistrib", math.random(35, 60) / 100)
                passengersBoarded = 0
                startBoardingOrDeboarding()
                boardingActive = true
                lastTimeBoardingCheck = os.time()
                openDoorsForBoarding()
                if boardingSpeedMode == 1 then
                    boardInstantly()
                end
            end
        end

        imgui.SameLine()

        if not boardingPaused then
            if imgui.Button("Start Deboarding") then
                passengersBoarded = intendedPassengerNumber
                startBoardingOrDeboarding()
                deboardingActive = true
                lastTimeBoardingCheck = os.time()
                openDoorsForBoarding()
                if boardingSpeedMode == 1 then
                    deboardInstantly()
                end
            end
        end
    end

    if boardingActive then
        imgui.SameLine()
        if imgui.Button("Pause Boarding") then
            boardingActive = false
            boardingPaused = true
            boardingInformationMessage = "Boarding paused."
        end
    elseif boardingPaused then
        imgui.SameLine()
        if imgui.Button("Resume Boarding") then
            boardingActive = true
            boardingPaused = false
        end
    end

    if deboardingActive then
        imgui.SameLine()
        if imgui.Button("Pause Deboarding") then
            deboardingActive = false
            deboardingPaused = true
        end
    elseif deboardingPaused then
        imgui.SameLine()
        if imgui.Button("Resume Deboarding") then
            deboardingActive = true
            deboardingPaused = false
        end
    end

    if boardingPaused or deboardingPaused or boardingCompleted or deboardingCompleted then
        imgui.SameLine()
        if imgui.Button("Reset") then
            resetAllParameters()
            closeDoorsAfterBoarding()
        end
    end

    if not boardingActive and not deboardingActive then
        if imgui.RadioButton("Instant", boardingSpeedMode == 1) then
            boardingSpeedMode = 1
        end

        if USE_SECOND_DOOR then
            fastModeMinutes = math.floor((intendedPassengerNumber * 2) / 60)
        else
            fastModeMinutes = math.floor((intendedPassengerNumber * 3) / 60)
        end

        if fastModeMinutes ~= 0 then
            if imgui.RadioButton(
                string.format("Fast (%s minutes)", fastModeMinutes),
                boardingSpeedMode == 2) then
                boardingSpeedMode = 2
                if USE_SECOND_DOOR then
                    secondsPerPassenger = 2
                else
                    secondsPerPassenger = 3
                end
            end
        else
            if imgui.RadioButton(
                string.format("Fast (less than a minute)", fastModeMinutes),
                boardingSpeedMode == 2) then
                boardingSpeedMode = 2
                if USE_SECOND_DOOR then
                    secondsPerPassenger = 2
                else
                    secondsPerPassenger = 3
                end
            end
        end

        if USE_SECOND_DOOR then
            realModeMinutes = math.floor((intendedPassengerNumber * 5) / 60)
        else
            realModeMinutes = math.floor((intendedPassengerNumber * 9) / 60)
        end

        if realModeMinutes ~= 0 then
            if imgui.RadioButton(
                string.format("Real (%s minutes)", realModeMinutes),
                boardingSpeedMode == 3) then
                boardingSpeedMode = 3
                if USE_SECOND_DOOR then
                    secondsPerPassenger = 5
                else
                    secondsPerPassenger = 9
                end
            end
        else
            if imgui.RadioButton(
                string.format("Real (less than a minute)", realModeMinutes),
                boardingSpeedMode == 3) then
                boardingSpeedMode = 3
                if USE_SECOND_DOOR then
                    secondsPerPassenger = 5
                else
                    secondsPerPassenger = 9
                end
            end
        end
    end

    imgui.Separator()

    if imgui.TreeNode("Settings") then
        local changed, newval
        changed, newval = imgui.InputText("Simbrief Username", SIMBRIEF_ACCOUNT_NAME, 255)
        if changed then
            SIMBRIEF_ACCOUNT_NAME = newval
        end

        changed, newval = imgui.Checkbox("Simulate some passengers not showing up after simbrief import",
                                         RANDOMIZE_SIMBRIEF_PASSENGER_NUMBER)
        if changed then
            RANDOMIZE_SIMBRIEF_PASSENGER_NUMBER = newval
        end

        changed, newval = imgui.Checkbox(
            "Use front and back door for boarding and deboarding (only front door by default)", USE_SECOND_DOOR)
        if changed then
            USE_SECOND_DOOR = newval
            logMsg("USE_SECOND_DOOR set to " .. tostring(USE_SECOND_DOOR))
        end

        changed, newval = imgui.Checkbox(
            "Close doors after boarding/deboading", CLOSE_DOORS)
        if changed then
            CLOSE_DOORS = newval
            logMsg("CLOSE_DOORS set to " .. tostring(CLOSE_DOORS))
        end

        changed, newval = imgui.Checkbox(
            "Leave door1 open after boarding/deboading", LEAVE_DOOR1_OPEN)
        if changed then
            LEAVE_DOOR1_OPEN = newval
            logMsg("LEAVE_DOOR1_OPEN set to " .. tostring(LEAVE_DOOR1_OPEN))
        end

        if imgui.Button("Save Settings") then
            saveSettings()
        end
        imgui.TreePop()
    end
end

local winCloseInProgess = false

function tobusOnClose()
    isTobusWindowDisplayed = false
    winCloseInProgess = false
end

function buildTobusWindow()
    delayed_init()

    if (isTobusWindowDisplayed) then
        return
    end
	tobus_window = float_wnd_create(900, 280, 1, true)

    local leftCorner, height, width = XPLMGetScreenBoundsGlobal()

    float_wnd_set_position(tobus_window, width / 2 - 375, height / 2)
	float_wnd_set_title(tobus_window, "TOBUS - Your Toliss Boarding Companion " .. VERSION)
	float_wnd_set_imgui_builder(tobus_window, "tobusOnBuild")
    float_wnd_set_onclose(tobus_window, "tobusOnClose")

    isTobusWindowDisplayed = true
end

function showTobusWindow()
    if isTobusWindowDisplayed then
        if not winCloseInProgess then
            winCloseInProgess = true
            float_wnd_destroy(tobus_window) -- marks for destroy, destroy is async
        end
        return
    end

    buildTobusWindow()
end

add_macro("TOBUS - Your Toliss Boarding Companion", "buildTobusWindow()")
create_command("FlyWithLua/TOBUS/Toggle_tobus", "Show TOBUS window", "showTobusWindow()", "", "")
do_every_frame("tobusBoarding()")
readSettings()

end