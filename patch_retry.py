import re

with open("main.lua", "r") as f:
    code = f.read()

# Make sure VideoPlayer.setupVideoView stops the timer and previous playback
code = re.sub(
    r'function VideoPlayer\.setupVideoView\(\)\n    local videoView = VideoPlayer\.widgets\.videoView\n    local url = VideoPlayer\.currentUrl\n    \n    if not videoView or not url then return end\n    \n    VideoPlayer\.isManualStop = false -- Fix: State Reset\n    VideoPlayer\.lastPosition = -1\n    VideoPlayer\.lastPositionTime = 0\n    \n    if VideoPlayer\.widgets\.loading then',
    r'function VideoPlayer.setupVideoView()\n    local videoView = VideoPlayer.widgets.videoView\n    local url = VideoPlayer.currentUrl\n    \n    if not videoView or not url then return end\n    \n    VideoPlayer.stopTimer() -- Stop UI updates immediately\n    pcall(function() videoView.stopPlayback() end) -- Ensure previous playback is fully stopped\n    \n    VideoPlayer.isManualStop = false -- Fix: State Reset\n    VideoPlayer.lastPosition = -1\n    VideoPlayer.lastPositionTime = 0\n    VideoPlayer.isPrepared = false\n    \n    if VideoPlayer.widgets.loading then',
    code,
    flags=re.DOTALL
)

# Make sure VideoPlayer timer explicitly checks if isPrepared and isPlaying before calling getCurrentPosition
code = re.sub(
    r'VideoPlayer\.timer\.onTick = function\(\)\n        local videoView = VideoPlayer\.widgets\.videoView\n        if videoView and VideoPlayer\.widgets\.seek then\n            pcall\(function\(\)\n                local current = videoView\.getCurrentPosition\(\)',
    r'VideoPlayer.timer.onTick = function()\n        local videoView = VideoPlayer.widgets.videoView\n        if videoView and VideoPlayer.widgets.seek and VideoPlayer.isPrepared and VideoPlayer.isPlaying then\n            pcall(function()\n                local current = videoView.getCurrentPosition()',
    code,
    flags=re.DOTALL
)

# AudioPlayer ensure stop and stopTimer are called when play/setup is called
code = re.sub(
    r'function AudioPlayer\.executeLoad\(\)\n    AudioPlayer\.isManualStop = false -- Fix: State Reset\n    AudioPlayer\.lastPosition = -1\n    AudioPlayer\.lastPositionTime = 0\n    pcall\(function\(\)',
    r'function AudioPlayer.executeLoad()\n    AudioPlayer.stopTimer() -- Stop UI updates immediately\n    pcall(function() AudioPlayer.player.reset() end) -- Ensure player is cleanly reset before new data source\n    AudioPlayer.isManualStop = false -- Fix: State Reset\n    AudioPlayer.lastPosition = -1\n    AudioPlayer.lastPositionTime = 0\n    pcall(function()',
    code,
    flags=re.DOTALL
)

# Make sure AudioPlayer timer explicitly checks isPlaying
code = re.sub(
    r'if AudioPlayer\.player and AudioPlayer\.widgets\.seek then\n            pcall\(function\(\)\n                local current = AudioPlayer\.player\.getCurrentPosition\(\)',
    r'if AudioPlayer.player and AudioPlayer.widgets.seek and AudioPlayer.player.isPlaying() then\n            pcall(function()\n                local current = AudioPlayer.player.getCurrentPosition()',
    code,
    flags=re.DOTALL
)

with open("main.lua", "w") as f:
    f.write(code)

print("Patch for switching/repairing stutter applied.")
