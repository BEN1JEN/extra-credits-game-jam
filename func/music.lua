--
-- Sample from the metered energy
--
-- No need to interpolate and it makes a tiny amount of difference; we
-- take a random sample of samples, any errors are averaged out.
--
-- nrg is float array
-- offset is double
function sample(nrg, offset)
	local n = math.floor(offset);

	if nrg[n] ~= nil then
		return nrg[n]
	else
		return 0.0
	end
end


local NRG_SAMPLING_INTERVAL = 128


--
-- Test an autodifference for the given interval
--
-- nrg is float array
-- interval is interval in energy space
function autodifference(nrg, interval, midpoint)
	local beats = { -32, -16, -8, -4, -2, -1, 1, 2, 4, 8, 16, 32 }
	local nobeats = { -0.5, -0.25, 0.25, 0.5 }

	local v = sample(nrg, midpoint)

	local diff = 0.0
	local total = 0.0

	for n = 1, #beats do
		local y = sample(nrg, midpoint + beats[n] * interval)
		local w = 1.0 / math.abs(beats[n])

		diff = diff + w * math.abs(y - v)
		total = total + w
	end

	for n = 1, #nobeats do
		local y = sample(nrg, midpoint + nobeats[n] * interval);
		local w = math.abs(nobeats[n])

		diff = diff - w * math.abs(y - v)
		total = total + w
	end

	return diff / total
end


--
-- Beats-per-minute to a sampling interval in energy space
--
function bpmToInterval(bpm, sampleRate)
	local beatsPerSecond = bpm / 60;
	local samplesPerBeat = sampleRate / beatsPerSecond;
	return samplesPerBeat / NRG_SAMPLING_INTERVAL;
end


--
-- Sampling interval in enery space to beats-per-minute
--
function intervalToBpm(interval, sampleRate)
	local samplesPerBeat = interval * NRG_SAMPLING_INTERVAL;
	local beatsPerSecond = sampleRate / samplesPerBeat;
	return beatsPerSecond * 60;
end


--
-- Scan a range of BPM values for the one with the
-- minimum autodifference
--
-- nrg is float array
-- slowest is the lowest possible BPM
-- fastest is the highest possible BPM
-- steps is the number of BPMs to try
-- samples is the number of samples to take for each BPM
-- sampleRate is the sample rate of the song in Hz
--
-- inspired by http://www.pogo.org.uk/~mark/bpm-tools/
function scanForBpm(nrg, slowest, fastest, steps, samples, sampleRate)
	local slowestInterval = bpmToInterval(slowest, sampleRate)
	local fastestInterval = bpmToInterval(fastest, sampleRate)
	local step = (slowestInterval - fastestInterval) / steps;

	local height = math.huge
	local trough

	for interval = fastestInterval, slowestInterval, step do
		local total = 0.0

		for s = 0, samples do
			local midpoint = math.random(1, #nrg)
			local diff = autodifference(nrg, interval, midpoint)

			total = total + diff
		end

		-- Track the lowest value (best match)

		if total < height then
			trough = interval
			height = total
		end
	end

	-- print("Final interval is " .. trough)

	return intervalToBpm(trough, sampleRate)
end


--
-- Scan a range of offset values for the one with the
-- minimum (maximum?) autodifference
--
-- nrg is float array
-- beatsPerMinute is the BPM
-- sampleRate is the sample rate of the song in Hz
function scanForOffset(nrg, beatsPerMinute, sampleRate)
	local interval = bpmToInterval(beatsPerMinute, sampleRate)
	local totalIntervals = math.floor(#nrg / interval)

	local height = math.huge
	local trough

	for offsetSamples = 0, interval, 0.5 do
		local total = 0.0

		for s = 1, totalIntervals do
			local midpoint = s * interval + offsetSamples
			local diff = autodifference(nrg, interval, midpoint)

			total = total + diff
		end

		-- Track the lowest value

		if total < height then
			trough = offsetSamples
			height = total
		end
	end

	local offsetSample = trough * NRG_SAMPLING_INTERVAL
	local offsetTime = offsetSample / sampleRate
	local secondsPerBeat = 60 / beatsPerMinute
	local offset = secondsPerBeat - offsetTime

	-- print("Best offset NRG sample is " .. trough)
	-- print("Offset sample is " .. offsetSample)
	-- print("Offset time is " .. offsetTime)
	-- print("Seconds per beat is " .. secondsPerBeat)
	-- print("Offset offset is " .. offset)

	return offset
end


--
-- Convert the given audio samples to sampled energy
-- values.
--
function samplesToNrg(samples)
	local nrg = {}
	local v = 0
	local n = 0

	for i = 1, #samples do
		z = samples[i]

		-- Maintain an energy meter (similar to PPM)

		z = math.abs(z)
		if z > v then
			v = v + (z - v) / 8
		else
			v = v- (v - z) / 512
		end

		-- At regular intervals, sample the energy to give a
		-- low-resolution overview of the track

		if i % NRG_SAMPLING_INTERVAL == 0 then
			table.insert(nrg, v)
		end
	end

	return nrg
end


--
-- Perform a low pass filter on the samples.
--
function lowPassFilter(samples, sampleRate, frequency)
	-- tau is the number of seconds in one wavelength of the low pass frequency
	local tau = 1 / frequency
	-- formula for alpha from https://www.embeddedrelated.com/showarticle/779.php
	local alpha = (1 / sampleRate) / tau

	local lowPasSamples = {}
	local yk = samples[1]
	lowPasSamples[1] = yk
	for i = 2, #samples do
		yk = yk + alpha * (samples[i] - yk)
		lowPasSamples[i] = yk
	end

	return lowPasSamples
end


--
-- Compute the BPM and offset for the given audio samples.
--
function computeBpmAndOffset(samples, sampleRate)
	local SLOWEST_BPM = 84
	local FASTEST_BPM = 146
	local BPM_STEPS = 2048
	local BPM_SAMPLES = 1024

	local nrg = samplesToNrg(samples)

	local beatsPerMinute = scanForBpm(nrg, SLOWEST_BPM, FASTEST_BPM, BPM_STEPS, BPM_SAMPLES, sampleRate)
	local offset = scanForOffset(nrg, beatsPerMinute, sampleRate)

	return beatsPerMinute, offset
end


--
-- Extract the audio samples from the given SongData
-- into a floating point array (table).
--
function getSamples(songData)
	local sampleCount = songData:getSampleCount()
	local samples = {}

	for i = 1, sampleCount do
		samples[i] = songData:getSample(i - 1)
	end

	return samples
end


--
-- Extract the audio samples from the given SongData
-- into a floating point array (table).
--
function setSamples(songData, newSamples)
	local sampleCount = songData:getSampleCount()

	for i = 1, sampleCount do
		songData:setSample(i - 1, newSamples[i])
	end
end


--
-- Extract the audio samples from the given SongData
-- into a floating point array (table).
--
function getBpmAndOffset(songData)
	local samples = getSamples(songData)
	local sampleRate = songData:getSampleRate()

	local lowPasSamples = lowPassFilter(samples, sampleRate, 300)

	return computeBpmAndOffset(lowPasSamples, sampleRate)
end


local music = {}

function music.loadSong(songPath, bpmMultiplyer)
	local songObject = {}

	local songData = love.sound.newSoundData(songPath)
	local duration = songData:getDuration()
	local sampleRate = songData:getSampleRate()
	local originalBeatsPerMinute, offset = getBpmAndOffset(songData)
	local beatsPerMinute = originalBeatsPerMinute * bpmMultiplyer
	local secondsPerBeat = 60 / beatsPerMinute
	local source = love.audio.newSource(songData)

	-- print("Duration is " .. duration)
	-- print("Sample rate is " .. sampleRate)
	-- print("BPM is " .. beatsPerMinute)
	-- print("Seconds per beat is " .. secondsPerBeat)
	-- print("Offset is " .. offset)

	function songObject.play()
		source:play()
	end

	function songObject.isPlaying()
		return source:isPlaying()
	end

	function songObject.stop()
		source:stop()
	end

	local nextBeat = 1
	local lastBeatTime = offset

	function songObject.setBpmMultiplier(newBpmMultiplier)
		beatsPerMinute = originalBeatsPerMinute * newBpmMultiplier
		secondsPerBeat = 60 / beatsPerMinute
	end

	function songObject.getSongLength()
		return duration
	end

	function songObject.getSongRemaining()
		return duration - source:tell("seconds")
	end

	function songObject.getBeatsPassed()
		local beatCount = 0
		local nextBeatTime = lastBeatTime + secondsPerBeat
		local newTime = source:tell("seconds")
		local hasEnded = newTime > duration

		while nextBeatTime < newTime do
			beatCount = beatCount + 1
			nextBeat = nextBeat + 1
			lastBeatTime = nextBeatTime
			nextBeatTime = lastBeatTime + secondsPerBeat
		end

		return beatCount, not songObject.isPlaying()
	end

	function songObject.getBeat()
		return nextBeat - 1
	end

	function songObject.getBrightness()
		local fraction = 1 - ((source:tell("seconds") - lastBeatTime) / secondsPerBeat)

		if fraction > 0.5 then
			return (fraction - 0.5) * 2
		else
			return 0
		end
	end

	function songObject.drawBorder()
		local brightness = songObject.getBrightness()

		if brightness > 0 then
			local width, height = love.window.getMode()

			for i = 0, 10 do
				local lineBrightness = brightness * ((10 - i) / 10)
				love.graphics.setColor(1, 1, 1, lineBrightness)
				love.graphics.rectangle("line", i, i, width - (i * 2) - 1, height - (i * 2) - 1)
			end
			love.graphics.setColor(1, 1, 1)
		end
	end

	return songObject
end

return music
