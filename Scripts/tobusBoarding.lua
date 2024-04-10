 --http library import
 xml2lua = require("xml2lua")
 handler = require("xmlhandler.tree")
 socket = require "socket"
 http = require "socket.http"
 LIP = require("LIP")

function openDoorsForBoarding()
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

function closeDoorsAfterBoarding()
    passengerDoorArray[0] = 0
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

function setDefaultBoardingState()
    set("AirbusFBW/NoPax", 0)
    set("AirbusFBW/PaxDistrib", math.random(35, 60) / 100)
    passengersBoarded = 0
    boardingPaused = false
    boardingStopped = false
    boardingActive = true
end

function playChimeSound() 
    command_once( "AirbusFBW/CheckCabin" )
end

function boardInstantly() 
    set("AirbusFBW/NoPax", intendedPassengerNumber)
    passengersBoarded = intendedPassengerNumber
    boardingActive = false
    boardingCompleted = true
    playChimeSound()
    command_once("AirbusFBW/SetWeightAndCG")
    closeDoorsAfterBoarding()
end

function deboardInstantly() 
    set("AirbusFBW/NoPax", 0)
    deboardingActive = false
    deboardingCompleted = true
    playChimeSound()
    command_once("AirbusFBW/SetWeightAndCG")
    closeDoorsAfterBoarding()
end

function setRandomNumberOfPassengers()
    passengerDistributionGroup = math.random(0, 100)

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

function startBoardingOrDeboarding() 
    boardingPaused = false
    boardingActive = false
    boardingCompleted = false
    deboardingCompleted = false
    deboardingPaused = false
end

function resetAllParameters()
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

function boardPassengers()
    if boardingActive == false then
        return
    end

    if passengersBoarded <= intendedPassengerNumber 
     and (os.time() - lastTimeBoardingCheck) > math.random(secondsPerPassenger - 2, secondsPerPassenger + 3) then
        passengersBoarded = passengersBoarded + 1
        set("AirbusFBW/NoPax", passengersBoarded)
        command_once("AirbusFBW/SetWeightAndCG")
        lastTimeBoardingCheck = os.time()
    end

    if passengersBoarded == intendedPassengerNumber and boardingCompleted == false then
        boardingCompleted = true
        boardingActive = false
        closeDoorsAfterBoarding()
        if isTobusWindowDisplayed == false then
            buildTobusWindow()
        end
        playChimeSound()
    end
end

function deboardPassengers()
    if deboardingActive == false then
        return
    end

    if passengersBoarded >= 0 
     and (os.time() - lastTimeBoardingCheck) > math.random((secondsPerPassenger - 2) * 0.6, (secondsPerPassenger + 3) * 0.6) then
        passengersBoarded = passengersBoarded - 1
        set("AirbusFBW/NoPax", passengersBoarded)
        command_once("AirbusFBW/SetWeightAndCG")
        lastTimeBoardingCheck = os.time()
    end

    if passengersBoarded == 0 and deboardingCompleted == false then
        deboardingCompleted = true
        deboardingActive = false
        closeDoorsAfterBoarding()
        if isTobusWindowDisplayed == false then
            buildTobusWindow()
        end
        playChimeSound()
    end
end

function readSettings()
    settings = LIP.load(SCRIPT_DIRECTORY..SETTINGS_FILENAME);
    if settings.simbrief.username ~= nil then
        SIMBRIEF_ACCOUNT_NAME = settings.simbrief.username
        
        if settings.simbrief.randomizePassengerNumber then
            RANDOMIZE_SIMBRIEF_PASSENGER_NUMBER = true
        end
    end
    if settings.simbrief.useSecondDoor then
        USE_SECOND_DOOR = true
    end
end

function saveSettings()
    newSettings = LIP.load(SCRIPT_DIRECTORY..SETTINGS_FILENAME);
    newSettings.simbrief.username = SIMBRIEF_ACCOUNT_NAME
    newSettings.simbrief.randomizePassengerNumber = RANDOMIZE_SIMBRIEF_PASSENGER_NUMBER
    newSettings.simbrief.useSecondDoor = USE_SECOND_DOOR
    LIP.save(SCRIPT_DIRECTORY..SETTINGS_FILENAME, newSettings);
end

function fetchData()
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

function readXML()
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

SETTINGS_FILENAME = "/tobus/tobus_settings.ini"
SIMBRIEF_FLIGHTPLAN_FILENAME = "simbrief.xml"
SIMBRIEF_ACCOUNT_NAME = ""
RANDOMIZE_SIMBRIEF_PASSENGER_NUMBER = false
USE_SECOND_DOOR = false
SIMBRIEF_FLIGHTPLAN = {}


if not SUPPORTS_FLOATING_WINDOWS then
    -- to make sure the script doesn't stop old FlyWithLua versions
    logMsg("imgui not supported by your FlyWithLua version")
    return
end

if PLANE_ICAO ~= "A319" and PLANE_ICAO ~= "A321" and PLANE_ICAO ~= "A20N" and PLANE_ICAO ~= "A346" then
    logMsg(string.format("tolissBoarding.lua: not loading as Plane is not an airbus (%s).", PLANE_ICAO))
    return
end

MAX_PAX_NUMBER = 224

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

passengerDoorArray = create_dataref_table("AirbusFBW/PaxDoorModeArray", "FloatArray")
cargoDoorArray = create_dataref_table("AirbusFBW/CargoDoorModeArray", "FloatArray")

-- init gloabl variables
readSettings()
resetAllParameters()

function tobusOnBuild(tobus_window, x, y)
    if boardingActive and boardingCompleted == false then
        imgui.PushStyleColor(imgui.constant.Col.Text, 0xFF95FFF8)
        imgui.TextUnformatted(string.format("Boarding in progress %s / %s boarded", passengersBoarded, intendedPassengerNumber))
        imgui.PopStyleColor()
    end

    if deboardingActive and deboardingCompleted == false then
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

    if boardingActive == false and deboardingActive == false  then
        local passengeraNumberChanged, newPassengerNumber 
        = imgui.SliderInt("Passengers number", intendedPassengerNumber, 0, MAX_PAX_NUMBER, "Value: %d")

        if passengeraNumberChanged then
            intendedPassengerNumber = newPassengerNumber
        end
        imgui.SameLine()

        if imgui.Button("Get from simbrief") then
            if fetchData() then
                readXML()
            end
        end
        
        if imgui.Button("Set random passenger number") then
            setRandomNumberOfPassengers()
        end

    end

    if boardingActive == false and deboardingActive == false then
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

        if boardingPaused == false then
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

    if boardingActive == false and deboardingActive == false then
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
        local simbriefUsernameChanged, newText = imgui.InputText("Simbrief Username", SIMBRIEF_ACCOUNT_NAME, 255)

        if simbriefUsernameChanged then
            SIMBRIEF_ACCOUNT_NAME = newText
        end
    
        local randomizeSimbriefPassengerChanged, newVal = imgui.Checkbox(
            "Simulate some passengers not showing up after simbrief import", RANDOMIZE_SIMBRIEF_PASSENGER_NUMBER
        )
        if randomizeSimbriefPassengerChanged then
            RANDOMIZE_SIMBRIEF_PASSENGER_NUMBER = newVal
        end

        local useSecondDoorChanged, newValue = imgui.Checkbox(
            "Use front and back door for boarding and deboarding (only front door by default)", USE_SECOND_DOOR
        )
        if useSecondDoorChanged then
            USE_SECOND_DOOR = newValue
        end
    
        if imgui.Button("Save Settings") then
            saveSettings()
        end
        imgui.TreePop()
    end
end

function tobusOnClose()
    isTobusWindowDisplayed = false
end

function buildTobusWindow()
    if (isTobusWindowDisplayed) then
        return
    end
	tobus_window = float_wnd_create(900, 240, 1, true)

    local leftCorner, height, width = XPLMGetScreenBoundsGlobal()

    float_wnd_set_position(tobus_window, width / 2 - 375, height / 2)
	float_wnd_set_title(tobus_window, "TOBUS - Your Toliss Boarding Companion")
	float_wnd_set_imgui_builder(tobus_window, "tobusOnBuild")
    float_wnd_set_onclose(tobus_window, "tobusOnClose")

    isTobusWindowDisplayed = true
end

function showTobusWindow()
    if isTobusWindowDisplayed then
        return
    end
    buildTobusWindow()
end

add_macro("TOBUS - Your Toliss Boarding Companion", "buildTobusWindow()")
create_command("FlyWithLua/TOBUS/Toggle_tobus", "Show TOBUS window", "showTobusWindow()", "", "")
do_often("boardPassengers()")
do_often("deboardPassengers()")
readSettings()