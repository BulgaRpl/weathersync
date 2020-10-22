local CurrentWeather = ''
local CurrentWindDirection = 0.0

RegisterNetEvent('weatherSync:changeWeather')
RegisterNetEvent('weatherSync:changeTime')
RegisterNetEvent('weatherSync:changeWind')
RegisterNetEvent('weatherSync:toggleForecast')
RegisterNetEvent('weatherSync:updateForecast')
RegisterNetEvent('weatherSync:openAdminUi')
RegisterNetEvent('weatherSync:updateAdminUi')

function IsInSnowyRegion(x, y, z)
	return GetDistanceBetweenCoords(x, y, z, -1361.63, 2393.23, 306.62, false) <= 1400
end

function IsInDesertRegion(x, y, z)
	return x <= -2050 and y <= -2200
end

function TranslateWeatherForRegion(weather)
	local x, y, z = table.unpack(GetEntityCoords(PlayerPedId()))

	if weather == 'rain' then
		if IsInSnowyRegion(x, y, z) then
			return 'snow'
		elseif IsInDesertRegion(x, y, z) then
			return 'thunder'
		end
	elseif weather == 'thunderstorm' then
		if IsInSnowyRegion(x, y, z) then
			return 'blizzard'
		elseif IsInDesertRegion(x, y, z) then
			return 'rain'
		end
	elseif weather == 'hurricane' then
		if IsInSnowyRegion(x, y, z) then
			return 'whiteout'
		elseif IsInDesertRegion(x, y, z) then
			return 'sandstorm'
		end
	elseif weather == 'drizzle' then
		if IsInSnowyRegion(x, y, z) then
			return 'snowlight'
		elseif IsInDesertRegion(x, y, z) then
			return 'sunny'
		end
	elseif weather == 'shower' then
		if IsInSnowyRegion(x, y, z) then
			return 'groundblizzard'
		elseif IsInDesertRegion(x, y, z) then
			return 'sunny'
		end
	elseif weather == 'fog' then
		if IsInSnowyRegion(x, y, z) then
			return 'snowlight'
		end
	elseif weather == 'misty' then
		if IsInSnowyRegion(x, y, z) then
			return 'snowlight'
		end
	end

	return weather
end

function SetWeatherType(weatherHash, p1, p2, overrideNetwork, transitionTime, p5)
	Citizen.InvokeNative(0x59174F1AFE095B5A, weatherHash, true, false, true, transitionTime, false)
end

AddEventHandler('weatherSync:changeWeather', function(weather, transitionTime)
	local translatedWeather = TranslateWeatherForRegion(weather)

	if translatedWeather ~= CurrentWeather then
		SetWeatherType(GetHashKey(translatedWeather), true, false, true, transitionTime, false)
		CurrentWeather = translatedWeather
	end
end)

function NetworkOverrideClockTime(hour, minute, second, transitionTime, freezeTime)
	Citizen.InvokeNative(0x669E223E64B1903C, hour, minute, second, transitionTime, freezeTime)
end

AddEventHandler('weatherSync:changeTime', function(hour, minute, second, transitionTime, freezeTime)
	NetworkOverrideClockTime(hour, minute, second, transitionTime, freezeTime)
end)

AddEventHandler('weatherSync:changeWind', function(direction, speed)
	SetWindDirection(direction)
	CurrentWindDirection = direction
	SetWindSpeed(speed)
end)

local ForecastIsDisplayed = false

function UpdateForecast(forecast)
	local h24 = ShouldUse_24HourClock()

	for i = 1, #forecast do
		if h24 then
			forecast[i].time = string.format(
				'%.2d:%.2d',
				forecast[i].hour,
				forecast[i].min)
		else
			local h = forecast[i].hour % 12
			forecast[i].time = string.format(
				'%d:%.2d %s',
				h == 0 and 12 or h,
				forecast[i].min,
				forecast[i].hour > 12 and 'PM' or 'AM')
		end

		forecast[i].weather = Config.WeatherIcons[TranslateWeatherForRegion(forecast[i].weather)]
		forecast[i].wind = GetCardinalDirection(forecast[i].wind)
	end

	-- Get local temperature
	local x, y, z = table.unpack(GetEntityCoords(PlayerPedId()))
	local metric = ShouldUseMetricTemperature();
	local temperature
	local temperatureUnit
	local windSpeed
	local windSpeedUnit
	if metric then
		temperature = math.floor(GetTemperatureAtCoords(x, y, z))
		temperatureUnit = 'C'

		windSpeed = math.floor(GetWindSpeed())
		windSpeedUnit = 'kph'
	else
		temperature = math.floor(GetTemperatureAtCoords(x, y, z) * 9/5 + 32)
		temperatureUnit = 'F'

		windSpeed = math.floor(GetWindSpeed() * 0.621371)
		windSpeedUnit = 'mph'
	end
	local tempStr = string.format('%d °%s', temperature, temperatureUnit)
	local windStr = string.format('🌬️ %d %s %s', windSpeed, windSpeedUnit, GetCardinalDirection(CurrentWindDirection))

	SendNUIMessage({
		action = 'updateForecast',
		forecast = json.encode(forecast),
		temperature = tempStr,
		wind = windStr
	})
end

AddEventHandler('weatherSync:toggleForecast', function()
	ForecastIsDisplayed = not ForecastIsDisplayed

	CreateThread(function()
		while ForecastIsDisplayed do
			TriggerServerEvent('weatherSync:requestUpdatedForecast')
			Wait(1000)
		end
	end)

	SendNUIMessage({
		action = 'toggleForecast'
	})
end)

AddEventHandler('weatherSync:updateForecast', function(forecast)
	UpdateForecast(forecast)
end)

AddEventHandler('weatherSync:openAdminUi', function()
	AdminUiIsOpen = true
	ForecastIsDisplayed = true

	CreateThread(function()
		while AdminUiIsOpen do
			TriggerServerEvent('weatherSync:requestUpdatedAdminUi')
			TriggerServerEvent('weatherSync:requestUpdatedForecast')
			Wait(1000)
		end
	end)

	SetNuiFocus(true, true)

	SendNUIMessage({
		action = 'openAdminUi'
	})
end)

AddEventHandler('weatherSync:updateAdminUi', function(weather, time, timescale, windDirection, windSpeed, syncDelay)
	local h, m, s = TimeToHMS(time)

	SendNUIMessage({
		action = 'updateAdminUi',
		weatherTypes = json.encode(WeatherTypes),
		weather = weather,
		hour = h,
		min = m,
		sec = s,
		timescale = timescale,
		windSpeed = windSpeed,
		windDirection = windDirection,
		syncDelay = syncDelay
	})
end)

RegisterNUICallback('setTime', function(data, cb)
	TriggerServerEvent('weatherSync:setTime', data.hour, data.min, data.sec, data.transition, data.freeze)
	cb({})
end)

RegisterNUICallback('setTimescale', function(data, cb)
	TriggerServerEvent('weatherSync:setTimescale', data.timescale * 1.0)
	cb({})
end)

RegisterNUICallback('setWeather', function(data, cb)
	TriggerServerEvent('weatherSync:setWeather', data.weather, data.transition * 1.0, data.freeze)
	cb({})
end)

RegisterNUICallback('setWind', function(data, cb)
	TriggerServerEvent('weatherSync:setWind', data.windDirection * 1.0, data.windSpeed * 1.0, data.freeze)
	cb({})
end)

RegisterNUICallback('setSyncDelay', function(data, cb)
	TriggerServerEvent('weatherSync:setSyncDelay', data.syncDelay)
	cb({})
end)

RegisterNUICallback('closeAdminUi', function(data, cb)
	SetNuiFocus(false, false)
	AdminUiIsOpen = false
	ForecastIsDisplayed = false
	cb({})
end)

CreateThread(function()
	Wait(0)

	SetNuiFocus(false, false)

	TriggerEvent('chat:addSuggestion', '/forecast', 'Toggle display of weather forecast', {})

	TriggerEvent('chat:addSuggestion', '/syncdelay', 'Change how often time/weather are synced.', {
		{name = 'delay', help = 'The time in milliseconds between syncs'}
	})

	TriggerEvent('chat:addSuggestion', '/time', 'Change the time of day', {
		{name = 'h', help = 'Hour, 0-23'},
		{name = 'm', help = 'Minute, 0-59'},
		{name = 's', help = 'Second, 0-59'},
		{name = 'transition', help = 'Transition time in milliseconds'},
		{name = 'freeze', help = '0 = don\'t freeze time, 1 = freeze time'}
	})

	TriggerEvent('chat:addSuggestion', '/timescale', 'Change the rate at which time passes', {
		{name = 'scale', help = 'Number of in-game seconds per real-time second'}
	})

	TriggerEvent('chat:addSuggestion', '/weather', 'Change the weather', {
		{name = 'type', help = 'The type of weather to change to'},
		{name = 'transition', help = 'Transition time in seconds'},
		{name = 'freeze', help = '0 = don\'t freeze weather, 1 = freeze weather'}
	})

	TriggerEvent('chat:addSuggestion', '/weatherui', 'Open weather admin UI', {})

	TriggerEvent('chat:addSuggestion', '/wind', 'Change wind direction and speed', {
		{name = 'direction', help = 'Direction of the wind in degrees'},
		{name = 'speed', help = 'Minimum wind speed'},
		{name = 'freeze', help = '0 don\'t freeze wind, 1 = freeze wind'}
	})
end)
