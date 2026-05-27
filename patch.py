import re

with open("main.lua", "r") as f:
    code = f.read()

# Part 1: formatSpeed
code = re.sub(
    r'function formatSpeed\(bytes\).*?end\s+local PREF_NAME = "XtreamPlayer_Data"',
    r'local PREF_NAME = "XtreamPlayer_Data"',
    code,
    flags=re.DOTALL
)

# Part 2: VideoPlayer UI
code = re.sub(
    r'\{\s+TextView,\s+id = "vBufferText".*?\{\s+Space,\s+layout_weight = "1"\s+\},\s+\{\s+TextView,\s+id = "vSpeedText".*?\{\s+Space,\s+layout_weight = "1"\s+\},\s+\{\s+Button,\s+id = "vRepairBtn"',
    r'{\n                    Button,\n                    id = "vRepairBtn"',
    code,
    flags=re.DOTALL
)

code = re.sub(
    r'VideoPlayer\.widgets\.controlLayer = vControlLayer\s+VideoPlayer\.widgets\.speedText = vSpeedText\s+VideoPlayer\.widgets\.bufferText = vBufferText\s+pcall\(function\(\)\s+if Build\.VERSION\.SDK_INT >= 22 then\s+vPlayBtn\.setAccessibilityTraversalAfter\(vTitle\.getId\(\)\)\s+vSpeedText\.setAccessibilityTraversalAfter\(vPlayBtn\.getId\(\)\)\s+vRepairBtn\.setAccessibilityTraversalAfter\(vSpeedText\.getId\(\)\)\s+vExtBtn\.setAccessibilityTraversalAfter\(vRepairBtn\.getId\(\)\)',
    r'VideoPlayer.widgets.controlLayer = vControlLayer\n    \n    pcall(function()\n        if Build.VERSION.SDK_INT >= 22 then\n            vPlayBtn.setAccessibilityTraversalAfter(vTitle.getId())\n            vRepairBtn.setAccessibilityTraversalAfter(vPlayBtn.getId())\n            vExtBtn.setAccessibilityTraversalAfter(vRepairBtn.getId())',
    code,
    flags=re.DOTALL
)

# Part 3: VideoPlayer properties & repair
code = re.sub(
    r'videoWidth = 0,\n    videoHeight = 0,\n    lastPosition = -1,\n    lastPositionTime = 0,\n    lastRxBytes = 0,\n    speedHistory = \{\},\n    accumulatedCacheBytes = 0\n\}\n\nfunction VideoPlayer\.repair\(\)\n    local videoView = VideoPlayer\.widgets\.videoView\n    if not videoView then return end\n\n    local pos = videoView\.getCurrentPosition\(\)\n    speak\("جاري إصلاح الاتصال وإعادة بناء البث\.\.\."\)\n\n    VideoPlayer\.isSilentRetry = true\n    if not VideoPlayer\.isLive then\n        VideoPlayer\.savePosition\(pos\)\n    end\n    VideoPlayer\.setupVideoView\(\)\nend',
    r'videoWidth = 0,\n    videoHeight = 0,\n    lastPosition = -1,\n    lastPositionTime = 0\n}\n\nfunction VideoPlayer.repair()\n    local videoView = VideoPlayer.widgets.videoView\n    if not videoView then return end\n\n    local pos = videoView.getCurrentPosition()\n    speak("جاري إصلاح الاتصال وإعادة بناء البث...")\n\n    VideoPlayer.isSilentRetry = true\n    if not VideoPlayer.isLive then\n        VideoPlayer.savePosition(pos)\n    end\n    pcall(function()\n        videoView.stopPlayback()\n    end)\n    VideoPlayer.setupVideoView()\nend',
    code,
    flags=re.DOTALL
)

# Part 4: VideoPlayer setupVideoView state reset
code = re.sub(
    r'VideoPlayer\.isManualStop = false -- Fix: State Reset\n    VideoPlayer\.lastPosition = -1\n    VideoPlayer\.lastPositionTime = 0\n    VideoPlayer\.accumulatedCacheBytes = 0\n    \n    if VideoPlayer\.widgets\.loading then',
    r'VideoPlayer.isManualStop = false -- Fix: State Reset\n    VideoPlayer.lastPosition = -1\n    VideoPlayer.lastPositionTime = 0\n    \n    if VideoPlayer.widgets.loading then',
    code,
    flags=re.DOTALL
)

# Part 5: VideoPlayer onInfo and onBufferingUpdate
code = re.sub(
    r'videoView\.setOnInfoListener\(MediaPlayer\.OnInfoListener\{\s+onInfo = function\(mp, what, extra\).*?return true\s+end\s+\}\)\s+videoView\.setOnPreparedListener\(MediaPlayer\.OnPreparedListener\{\s+onPrepared = function\(mp\)\s+-- Handle explicit buffering percentage\s+mp\.setOnBufferingUpdateListener\(MediaPlayer\.OnBufferingUpdateListener\{\s+onBufferingUpdate = function\(m_mp, percent\)\s+if VideoPlayer\.widgets\.seek then\s+VideoPlayer\.widgets\.seek\.setSecondaryProgress\(math\.floor\(\(percent / 100\) \* VideoPlayer\.widgets\.seek\.getMax\(\)\)\)\s+end.*?end\s+\}\)\s+VideoPlayer\.isPrepared',
    r'''videoView.setOnInfoListener(MediaPlayer.OnInfoListener{
            onInfo = function(mp, what, extra)
                if what == 701 then -- MEDIA_INFO_BUFFERING_START
                    if VideoPlayer.widgets.loading then VideoPlayer.widgets.loading.setVisibility(View.VISIBLE) end
                elseif what == 702 or what == 3 then -- MEDIA_INFO_BUFFERING_END or MEDIA_INFO_VIDEO_RENDERING_START
                    if VideoPlayer.widgets.loading then VideoPlayer.widgets.loading.setVisibility(View.GONE) end
                end
                return true
            end
        })

        videoView.setOnPreparedListener(MediaPlayer.OnPreparedListener{
            onPrepared = function(mp)
                mp.setOnBufferingUpdateListener(MediaPlayer.OnBufferingUpdateListener{
                    onBufferingUpdate = function(m_mp, percent)
                        if VideoPlayer.widgets.seek then
                            VideoPlayer.widgets.seek.setSecondaryProgress(math.floor((percent / 100) * VideoPlayer.widgets.seek.getMax()))
                        end
                    end
                })

                VideoPlayer.isPrepared''',
    code,
    flags=re.DOTALL
)

code = re.sub(
    r'if VideoPlayer\.widgets\.bufferText then\s+VideoPlayer\.widgets\.bufferText\.setText\("⚠️ خطأ في التشغيل"\)\s+end\s+if VideoPlayer\.widgets\.loading then VideoPlayer\.widgets\.loading\.setVisibility\(View\.GONE\) end',
    r'if VideoPlayer.widgets.loading then VideoPlayer.widgets.loading.setVisibility(View.GONE) end',
    code,
    flags=re.DOTALL
)

code = re.sub(
    r'if VideoPlayer\.widgets\.bufferText then\s+VideoPlayer\.widgets\.bufferText\.setText\("⚠️ انقطع الاتصال"\)\s+end\s+if VideoPlayer\.widgets\.loading then VideoPlayer\.widgets\.loading\.setVisibility\(View\.GONE\) end',
    r'if VideoPlayer.widgets.loading then VideoPlayer.widgets.loading.setVisibility(View.GONE) end',
    code,
    flags=re.DOTALL
)

# Part 6: VideoPlayer Stop & Timer
code = re.sub(
    r'VideoPlayer\.stopTimer\(\)\n    if VideoPlayer\.retryTimer then VideoPlayer\.retryTimer\.stop\(\) end\n    if VideoPlayer\.bufferTimer then VideoPlayer\.bufferTimer\.stop\(\) end\n    VideoPlayer\.lastRxBytes = 0\n    VideoPlayer\.speedHistory = \{\}\n    VideoPlayer\.accumulatedCacheBytes = 0\n    if VideoPlayer\.uiHideTimer then VideoPlayer\.uiHideTimer\.stop\(\); VideoPlayer\.uiHideTimer = nil end',
    r'VideoPlayer.stopTimer()\n    if VideoPlayer.retryTimer then VideoPlayer.retryTimer.stop() end\n    if VideoPlayer.uiHideTimer then VideoPlayer.uiHideTimer.stop(); VideoPlayer.uiHideTimer = nil end',
    code,
    flags=re.DOTALL
)

code = re.sub(
    r'local current = videoView\.getCurrentPosition\(\)\n\s+local now = System\.currentTimeMillis\(\)\n\n\s+-- Internet Speed and Cache Calculation.*?local total = videoView\.getDuration\(\)',
    r'local current = videoView.getCurrentPosition()\n\n                local total = videoView.getDuration()',
    code,
    flags=re.DOTALL
)

# Part 7: AudioPlayer properties & repair
code = re.sub(
    r'lastPositionTime = 0,\n    lastRxBytes = 0,\n    speedHistory = \{\},\n    accumulatedCacheBytes = 0,\n    \n    sleepTargetTime = nil \n\}\n\nfunction AudioPlayer\.repair\(\)\n    if not AudioPlayer\.player then return end\n\n    local pos = AudioPlayer\.player\.getCurrentPosition\(\)\n    speak\("جاري إصلاح الاتصال وإعادة بناء البث الصوتي\.\.\."\)\n\n    AudioPlayer\.isSilentRetry = true\n    if not AudioPlayer\.isLive then\n        AudioPlayer\.savePosition\(pos\)\n    end\n    AudioPlayer\.playRetry\(\)\nend',
    r'lastPositionTime = 0,\n    sleepTargetTime = nil \n}\n\nfunction AudioPlayer.repair()\n    if not AudioPlayer.player then return end\n\n    local pos = AudioPlayer.player.getCurrentPosition()\n    speak("جاري إصلاح الاتصال وإعادة بناء البث الصوتي...")\n\n    AudioPlayer.isSilentRetry = true\n    if not AudioPlayer.isLive then\n        AudioPlayer.savePosition(pos)\n    end\n    pcall(function()\n        AudioPlayer.player.stop()\n    end)\n    AudioPlayer.playRetry()\nend',
    code,
    flags=re.DOTALL
)

# Part 8: AudioPlayer onInfo and onBufferingUpdate
code = re.sub(
    r'AudioPlayer\.player\.setOnCompletionListener\(MediaPlayer\.OnCompletionListener\{\s+onCompletion=function\(mp\).*?AudioPlayer\.player\.setOnErrorListener\(MediaPlayer\.OnErrorListener\{',
    r'''AudioPlayer.player.setOnCompletionListener(MediaPlayer.OnCompletionListener{
            onCompletion=function(mp)
                if AudioPlayer.isLive then
                    if not AudioPlayer.isManualStop then -- Fix: Completion Listener Update
                        AudioPlayer.attemptRetry()
                    end
                else
                    local duration = mp.getDuration()
                    local current = mp.getCurrentPosition()
                    if duration > 0 and (duration - current) > 10000 then
                        -- Prevent endless retry loops on VOD. Just halt on error/completion stall
                        AudioPlayer.updateUIState(false)
                    else
                        AudioPlayer.savePosition(0)
                        local item = AudioPlayer.getCurrentItem()
                        if item and item.type == "movie" then
                            HistoryManager.remove(item.id)
                            AudioPlayer.stop()
                        else
                            AudioPlayer.next()
                        end
                    end
                end
            end
        })

        AudioPlayer.player.setOnBufferingUpdateListener(MediaPlayer.OnBufferingUpdateListener{
            onBufferingUpdate = function(m_mp, percent)
                if AudioPlayer.widgets.seek then
                    AudioPlayer.widgets.seek.setSecondaryProgress(math.floor((percent / 100) * AudioPlayer.widgets.seek.getMax()))
                end
            end
        })

        AudioPlayer.player.setOnErrorListener(MediaPlayer.OnErrorListener{''',
    code,
    flags=re.DOTALL
)

code = re.sub(
    r'if AudioPlayer\.widgets\.bufferText then\s+AudioPlayer\.widgets\.bufferText\.setText\("⚠️ خطأ في التشغيل"\)\s+end\s+AudioPlayer\.updateUIState\(false\)',
    r'AudioPlayer.updateUIState(false)',
    code,
    flags=re.DOTALL
)

# Part 9: AudioPlayer executeLoad
code = re.sub(
    r'AudioPlayer\.isManualStop = false -- Fix: State Reset\n    AudioPlayer\.lastPosition = -1\n    AudioPlayer\.lastPositionTime = 0\n    AudioPlayer\.accumulatedCacheBytes = 0\n    pcall\(function\(\)',
    r'AudioPlayer.isManualStop = false -- Fix: State Reset\n    AudioPlayer.lastPosition = -1\n    AudioPlayer.lastPositionTime = 0\n    pcall(function()',
    code,
    flags=re.DOTALL
)

code = re.sub(
    r'AudioPlayer\.updateUIState\(false\)\n        speak\("إيقاف مؤقت"\)\n        if AudioPlayer\.bufferTimer then AudioPlayer\.bufferTimer\.stop\(\) end\n    else',
    r'AudioPlayer.updateUIState(false)\n        speak("إيقاف مؤقت")\n    else',
    code,
    flags=re.DOTALL
)

# Part 10: AudioPlayer Stop & Timer
code = re.sub(
    r'AudioPlayer\.player\.stop\(\)\n        AudioPlayer\.stopTimer\(\)\n        if AudioPlayer\.retryTimer then AudioPlayer\.retryTimer\.stop\(\) end\n        if AudioPlayer\.bufferTimer then AudioPlayer\.bufferTimer\.stop\(\) end\n        AudioPlayer\.lastRxBytes = 0\n        AudioPlayer\.speedHistory = \{\}\n        AudioPlayer\.accumulatedCacheBytes = 0\n    end',
    r'AudioPlayer.player.stop()\n        AudioPlayer.stopTimer()\n        if AudioPlayer.retryTimer then AudioPlayer.retryTimer.stop() end\n    end',
    code,
    flags=re.DOTALL
)

code = re.sub(
    r'local current = AudioPlayer\.player\.getCurrentPosition\(\)\n\s+local now = System\.currentTimeMillis\(\)\n\n\s+-- Internet Speed and Cache Calculation.*?local total = AudioPlayer\.player\.getDuration\(\)',
    r'local current = AudioPlayer.player.getCurrentPosition()\n\n                local total = AudioPlayer.player.getDuration()',
    code,
    flags=re.DOTALL
)

# Part 11: AudioPlayer UI Layout
code = re.sub(
    r'\{\s+LinearLayout,\s+orientation="horizontal",\s+layout_width="fill",\s+layout_marginBottom="12dp",\s+gravity="center",\n\s+\{\s+TextView,\s+id="pBufferText".*?\{\s+TextView,\s+id="pSpeedText".*?\{\s+Button,\s+id="btn_repair"',
    r'{\n            LinearLayout, orientation="horizontal", layout_width="fill", layout_marginBottom="12dp", gravity="center",\n            { Button, id="btn_repair"',
    code,
    flags=re.DOTALL
)

code = re.sub(
    r'AudioPlayer\.widgets\.playBtn = pPlay\n    AudioPlayer\.widgets\.favBtn = pFav\n    AudioPlayer\.widgets\.speedText = pSpeedText\n    AudioPlayer\.widgets\.bufferText = pBufferText\n    \n    if pSeek then',
    r'AudioPlayer.widgets.playBtn = pPlay\n    AudioPlayer.widgets.favBtn = pFav\n    \n    if pSeek then',
    code,
    flags=re.DOTALL
)

code = re.sub(
    r'AudioPlayer.widgets.playBtn = pPlay\n    AudioPlayer.widgets.favBtn = pFav\n    AudioPlayer.widgets.speedText = pSpeedText\n    AudioPlayer.widgets.bufferText = pBufferText\n    \n    if pSeek then',
    r'AudioPlayer.widgets.playBtn = pPlay\n    AudioPlayer.widgets.favBtn = pFav\n    \n    if pSeek then',
    code,
    flags=re.DOTALL
)


with open("main.lua", "w") as f:
    f.write(code)

print("Patch applied.")
