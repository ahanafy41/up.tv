require "import"
import "android.app.*"
import "android.os.*"
import "android.widget.*"
import "android.view.*"
import "android.content.*"
import "android.net.Uri"
import "android.media.MediaPlayer"
import "android.media.AudioManager"
import "android.media.session.MediaSession"
import "android.media.session.PlaybackState"
import "android.media.MediaMetadata"
import "com.androlua.Http"
import "android.content.Context"
import "android.graphics.BitmapFactory"
import "android.graphics.Color"
import "android.graphics.Typeface"
import "android.graphics.drawable.ColorDrawable"
import "android.graphics.drawable.GradientDrawable"
import "android.graphics.drawable.StateListDrawable"
import "com.androlua.LuaBroadcastReceiver"
import "java.util.HashMap"
import "android.view.WindowManager"
import "android.content.pm.ActivityInfo"
import "android.view.SurfaceView"
import "android.view.SurfaceHolder"
import "android.widget.MediaController"
import "android.util.DisplayMetrics"

local json = require "cjson"

local PREF_NAME = "XtreamPlayer_Data"
local sharedPref = activity.getSharedPreferences(PREF_NAME, Context.MODE_PRIVATE)

function getData(key, defaultVal)
    local val = sharedPref.getString(key, nil)
    return val or defaultVal
end

function setData(key, val)
    local editor = sharedPref.edit()
    if val == nil then
        editor.remove(key)
    else
        editor.putString(key, tostring(val))
    end
    editor.apply()
end

-- Global Silence: Redefined to be empty
function speak(text)
end

local HOST = getData("xt_host")
local USER = getData("xt_user")
local PASS = getData("xt_pass")

if not HOST or HOST == "" then
    HOST = ""
    USER = ""
    PASS = ""
end

local FAVORITES_KEY = "xt_favorites_list"
local HISTORY_KEY = "xt_history_list"
local SERIES_FAVORITES_KEY = "xt_series_favorites"
local PLAYER_MODE_KEY = "xt_player_mode"
local MAX_HISTORY_ITEMS = 50

local PLAYER_MODE = getData(PLAYER_MODE_KEY) or "audio"

-- متغير التحكم لمنع التكرار (من الكود الأول)
local lastActionTime = 0

local ACTION_PREV = "com.xtream.action.PREV"
local ACTION_PLAY_PAUSE = "com.xtream.action.PLAY_PAUSE"
local ACTION_NEXT = "com.xtream.action.NEXT"
local ACTION_CLOSE = "com.xtream.action.CLOSE"

function onMyReceive(context, intent)
    local action = intent.getAction()
    if action == ACTION_PLAY_PAUSE then
        if PLAYER_MODE == "video" then
            VideoPlayer.togglePlay()
        else
            AudioPlayer.togglePlay()
        end
    elseif action == ACTION_NEXT then
        if PLAYER_MODE == "video" then
            VideoPlayer.next()
        else
            AudioPlayer.next()
        end
    elseif action == ACTION_PREV then
        if PLAYER_MODE == "video" then
            VideoPlayer.prev()
        else
            AudioPlayer.prev()
        end
    elseif action == ACTION_CLOSE then
        if PLAYER_MODE == "video" then
            VideoPlayer.stop()
        else
            AudioPlayer.stop()
        end
    end
end

local listener = nil
pcall(function() listener = luajava.createProxy("com.androlua.LuaBroadcastReceiver$OnReceiveListerer", {onReceive = onMyReceive}) end)
if not listener then pcall(function() listener = luajava.createProxy("com.androlua.LuaBroadcastReceiver$OnReceiveListener", {onReceive = onMyReceive}) end) end

if listener then GlobalPlayerReceiver = LuaBroadcastReceiver(listener) else GlobalPlayerReceiver = LuaBroadcastReceiver({onReceive = onMyReceive}) end

local filter = IntentFilter()
filter.addAction(ACTION_PREV)
filter.addAction(ACTION_PLAY_PAUSE)
filter.addAction(ACTION_NEXT)
filter.addAction(ACTION_CLOSE)
filter.setPriority(2147483647)

pcall(function()
    if Build.VERSION.SDK_INT >= 33 then activity.registerReceiver(GlobalPlayerReceiver, filter, 2) else activity.registerReceiver(GlobalPlayerReceiver, filter) end
end)

FavoritesManager = {
    favorites = {},
    seriesFavorites = {}
}

function FavoritesManager.load()
    local saved = getData(FAVORITES_KEY)
    if saved and saved ~= "" then
        local success, data = pcall(json.decode, saved)
        if success and data then
            FavoritesManager.favorites = data
        end
    end
    
    local savedSeries = getData(SERIES_FAVORITES_KEY)
    if savedSeries and savedSeries ~= "" then
        local success, data = pcall(json.decode, savedSeries)
        if success and data then
            FavoritesManager.seriesFavorites = data
        end
    end
end

function FavoritesManager.save()
    local success, encoded = pcall(json.encode, FavoritesManager.favorites)
    if success then
        setData(FAVORITES_KEY, encoded)
    end
end

function FavoritesManager.saveSeries()
    local success, encoded = pcall(json.encode, FavoritesManager.seriesFavorites)
    if success then
        setData(SERIES_FAVORITES_KEY, encoded)
    end
end

function FavoritesManager.add(item)
    if not item or not item.id then return false end
    
    for i, fav in ipairs(FavoritesManager.favorites) do
        if fav.id == item.id then
            speak("موجود بالفعل في المفضلة")
            return false
        end
    end
    
    local favItem = {
        id = item.id,
        name = item.name,
        url = item.url,
        type = item.type or "unknown",
        addedAt = os.time()
    }
    
    table.insert(FavoritesManager.favorites, 1, favItem)
    FavoritesManager.save()
    speak("تمت الإضافة للمفضلة")
    return true
end

function FavoritesManager.remove(itemId)
    for i, fav in ipairs(FavoritesManager.favorites) do
        if fav.id == itemId then
            table.remove(FavoritesManager.favorites, i)
            FavoritesManager.save()
            speak("تم الحذف من المفضلة")
            return true
        end
    end
    return false
end

function FavoritesManager.isFavorite(itemId)
    for _, fav in ipairs(FavoritesManager.favorites) do
        if fav.id == itemId then
            return true
        end
    end
    return false
end

function FavoritesManager.toggle(item)
    if FavoritesManager.isFavorite(item.id) then
        FavoritesManager.remove(item.id)
    else
        FavoritesManager.add(item)
    end
end

function FavoritesManager.addSeries(seriesId, seriesName, categoryId)
    if not seriesId then return false end
    
    local seriesKey = "series_" .. seriesId
    
    for i, fav in ipairs(FavoritesManager.seriesFavorites) do
        if fav.id == seriesKey then
            speak("المسلسل موجود بالفعل في المفضلة")
            return false
        end
    end
    
    local favItem = {
        id = seriesKey,
        series_id = seriesId,
        name = seriesName,
        category_id = categoryId,
        type = "full_series",
        addedAt = os.time()
    }
    
    table.insert(FavoritesManager.seriesFavorites, 1, favItem)
    FavoritesManager.saveSeries()
    speak("تم إضافة المسلسل كاملاً للمفضلة")
    return true
end

function FavoritesManager.removeSeries(seriesId)
    local seriesKey = "series_" .. seriesId
    for i, fav in ipairs(FavoritesManager.seriesFavorites) do
        if fav.id == seriesKey or fav.series_id == seriesId then
            table.remove(FavoritesManager.seriesFavorites, i)
            FavoritesManager.saveSeries()
            speak("تم حذف المسلسل من المفضلة")
            return true
        end
    end
    return false
end

function FavoritesManager.isSeriesFavorite(seriesId)
    local seriesKey = "series_" .. seriesId
    for _, fav in ipairs(FavoritesManager.seriesFavorites) do
        if fav.id == seriesKey or fav.series_id == seriesId then
            return true
        end
    end
    return false
end

function FavoritesManager.toggleSeries(seriesId, seriesName, categoryId)
    if FavoritesManager.isSeriesFavorite(seriesId) then
        FavoritesManager.removeSeries(seriesId)
    else
        FavoritesManager.addSeries(seriesId, seriesName, categoryId)
    end
end

function FavoritesManager.getAllSeries()
    return FavoritesManager.seriesFavorites
end

function FavoritesManager.getAll()
    return FavoritesManager.favorites
end

function FavoritesManager.clear()
    FavoritesManager.favorites = {}
    FavoritesManager.save()
    speak("تم مسح المفضلة")
end

function FavoritesManager.clearSeries()
    FavoritesManager.seriesFavorites = {}
    FavoritesManager.saveSeries()
    speak("تم مسح مفضلة المسلسلات")
end

function FavoritesManager.clearAll()
    FavoritesManager.favorites = {}
    FavoritesManager.seriesFavorites = {}
    FavoritesManager.save()
    FavoritesManager.saveSeries()
    speak("تم مسح جميع المفضلة")
end

HistoryManager = {
    history = {}
}

function HistoryManager.load()
    local saved = getData(HISTORY_KEY)
    if saved and saved ~= "" then
        local success, data = pcall(json.decode, saved)
        if success and data then
            HistoryManager.history = data
        end
    end
end

function HistoryManager.save()
    local success, encoded = pcall(json.encode, HistoryManager.history)
    if success then
        setData(HISTORY_KEY, encoded)
    end
end

function HistoryManager.add(item)
    if not item or not item.id then return end
    
    for i, hist in ipairs(HistoryManager.history) do
        if hist.id == item.id then
            table.remove(HistoryManager.history, i)
            break
        end
    end
    
    local histItem = {
        id = item.id,
        name = item.name,
        url = item.url,
        type = item.type or "unknown",
        watchedAt = os.time(),
        position = item.position or 0,
        duration = item.duration or 0,
        episode_num = item.episode_num or nil,
        series_id = item.series_id or nil,
        series_name = item.series_name or nil
    }
    
    table.insert(HistoryManager.history, 1, histItem)
    
    while #HistoryManager.history > MAX_HISTORY_ITEMS do
        table.remove(HistoryManager.history)
    end
    
    HistoryManager.save()
end

function HistoryManager.updatePosition(itemId, position, duration)
    for i, hist in ipairs(HistoryManager.history) do
        if hist.id == itemId then
            hist.position = position
            if duration then hist.duration = duration end
            hist.watchedAt = os.time()
            HistoryManager.save()
            return
        end
    end
end

function HistoryManager.getAll()
    return HistoryManager.history
end

function HistoryManager.clear()
    HistoryManager.history = {}
    HistoryManager.save()
    speak("تم مسح السجل")
end

function HistoryManager.remove(itemId)
    for i, hist in ipairs(HistoryManager.history) do
        if hist.id == itemId then
            table.remove(HistoryManager.history, i)
            HistoryManager.save()
            return true
        end
    end
    return false
end

FavoritesManager.load()
HistoryManager.load()

function getRoundedDrawable(color, radius)
  local gd = GradientDrawable()
  gd.setColor(Color.parseColor(color))
  gd.setCornerRadius(radius)
  return gd
end

function getGradientDrawable(colors, radius)
    local gd = GradientDrawable(GradientDrawable.Orientation.BL_TR, {Color.parseColor(colors[1]), Color.parseColor(colors[2])})
    gd.setCornerRadius(radius)
    return gd
end

function getClickableDrawable(normalColor, pressedColor, radius)
    local sld = StateListDrawable()
    local pressedDrawable
    if type(pressedColor) == "table" then
        pressedDrawable = getGradientDrawable(pressedColor, radius)
    else
        pressedDrawable = getRoundedDrawable(pressedColor, radius)
    end
    
    sld.addState({android.R.attr.state_pressed}, pressedDrawable)
    sld.addState({android.R.attr.state_focused}, pressedDrawable)
    sld.addState({}, getRoundedDrawable(normalColor, radius))
    return sld
end

-- Premium Colors
local COL_BG = "#080808"
local COL_SURFACE = "#161616"
local COL_SURFACE_PRESS = "#252525"
local COL_ACCENT_START = "#00E5FF"
local COL_ACCENT_END = "#00B0FF"
local COL_TEXT_PRI = "#FFFFFF"
local COL_TEXT_SEC = "#AAAAAA"
local COL_ERROR = "#CF6679"

VideoPlayer = {
    playlist = {},
    currentIndex = 1,
    timer = nil,
    retryTimer = nil,
    uiHideTimer = nil,
    dialog = nil,
    activity = nil,
    widgets = {},
    notification_id = 112244,
    audioManager = activity.getSystemService(Context.AUDIO_SERVICE),
    mediaSession = nil,
    
    retryCount = 0,
    maxRetries = 10,
    isLive = false,
    currentUrl = nil,
    isPlaying = false,
    isPrepared = false,
    isSilentRetry = false, 
    isManualStop = false, 
    currentPosition = 0,
    isFullscreen = false,
    
    videoWidth = 0,
    videoHeight = 0
}

function VideoPlayer.init()
end

function VideoPlayer.initMediaSession()
    if VideoPlayer.mediaSession then return end
    pcall(function()
        VideoPlayer.mediaSession = MediaSession(activity, "XtreamVideo")
        VideoPlayer.mediaSession.setFlags(MediaSession.FLAG_HANDLES_MEDIA_BUTTONS | MediaSession.FLAG_HANDLES_TRANSPORT_CONTROLS)
        
        VideoPlayer.mediaSession.setCallback(luajava.override(MediaSession.Callback, {
            onPlay = function() VideoPlayer.togglePlay() end,
            onPause = function() VideoPlayer.togglePlay() end,
            onSkipToNext = function() VideoPlayer.next() end,
            onSkipToPrevious = function() VideoPlayer.prev() end,
            onMediaButtonEvent = function(intent)
                VideoPlayer.togglePlay()
                return true
            end
        }))
        
        VideoPlayer.mediaSession.setActive(true)
    end)
end

function VideoPlayer.updatePlaybackState(state)
    if not VideoPlayer.mediaSession then return end
    pcall(function()
        local actions = PlaybackState.ACTION_PLAY | PlaybackState.ACTION_PAUSE | 
                      PlaybackState.ACTION_PLAY_PAUSE | PlaybackState.ACTION_SKIP_TO_NEXT |
                      PlaybackState.ACTION_SKIP_TO_PREVIOUS | PlaybackState.ACTION_STOP
                      
        local pos = 0
        if VideoPlayer.widgets.videoView then pos = VideoPlayer.widgets.videoView.getCurrentPosition() end
        
        local pbState = PlaybackState.Builder()
            .setActions(actions)
            .setState(state, pos, 1.0)
            .build()
        VideoPlayer.mediaSession.setPlaybackState(pbState)
    end)
end

function VideoPlayer.updateMetadata()
    if not VideoPlayer.mediaSession then return end
    local item = VideoPlayer.playlist[VideoPlayer.currentIndex]
    if not item then return end
    pcall(function()
        local meta = MediaMetadata.Builder()
            .putString(MediaMetadata.METADATA_KEY_TITLE, item.name)
            .putString(MediaMetadata.METADATA_KEY_ARTIST, "Xtream Player")
            .build()
        VideoPlayer.mediaSession.setMetadata(meta)
    end)
end

function VideoPlayer.sendNotification(title, isPlaying)
    local ns = Context.NOTIFICATION_SERVICE
    local nm = activity.getSystemService(ns)
    local channelId = "xtream_final_ch"
    
    if Build.VERSION.SDK_INT >= 26 then
        local channel = NotificationChannel(channelId, "Xtream Player", 3)
        nm.createNotificationChannel(channel)
    end
    
    local builder = Notification.Builder(activity)
    if Build.VERSION.SDK_INT >= 26 then builder.setChannelId(channelId) end
    
    builder.setContentTitle("Xtream Video")
    builder.setContentText(title)
    builder.setSmallIcon(android.R.drawable.ic_media_play)
    builder.setLargeIcon(BitmapFactory.decodeResource(activity.getResources(), android.R.drawable.ic_media_play))
    builder.setOngoing(isPlaying)
    builder.setShowWhen(false)
    builder.setVisibility(1) 
    
    local pFlag = 0
    if Build.VERSION.SDK_INT >= 31 then pFlag = 67108864 end 
    
    local intent = Intent(activity, activity.getClass())
    local pendingIntent = PendingIntent.getActivity(activity, 0, intent, pFlag)
    builder.setContentIntent(pendingIntent)
    
    local iPrev = Intent(ACTION_PREV); local pPrev = PendingIntent.getBroadcast(activity, 1, iPrev, pFlag)
    builder.addAction(android.R.drawable.ic_media_previous, "السابق", pPrev)
    
    local iPlay = Intent(ACTION_PLAY_PAUSE); local pPlay = PendingIntent.getBroadcast(activity, 2, iPlay, pFlag)
    local playIcon = isPlaying and android.R.drawable.ic_media_pause or android.R.drawable.ic_media_play
    builder.addAction(playIcon, "Play", pPlay)
    
    local iNext = Intent(ACTION_NEXT); local pNext = PendingIntent.getBroadcast(activity, 3, iNext, pFlag)
    builder.addAction(android.R.drawable.ic_media_next, "التالي", pNext)
    
    local iClose = Intent(ACTION_CLOSE); local pClose = PendingIntent.getBroadcast(activity, 4, iClose, pFlag)
    builder.addAction(android.R.drawable.ic_menu_close_clear_cancel, "إغلاق", pClose)
    
    pcall(function()
        local style = Notification.MediaStyle()
        if VideoPlayer.mediaSession then style.setMediaSession(VideoPlayer.mediaSession.getSessionToken()) end
        style.setShowActionsInCompactView(0, 1, 2)
        builder.setStyle(style)
    end)
    
    nm.notify(VideoPlayer.notification_id, builder.build())
end

function VideoPlayer.cancelNotification()
    local ns = Context.NOTIFICATION_SERVICE
    local nm = activity.getSystemService(ns)
    nm.cancel(VideoPlayer.notification_id)
end

function VideoPlayer.showUI()
    if VideoPlayer.widgets.controlLayer then
        VideoPlayer.widgets.controlLayer.animate().alpha(1).setDuration(300).start()
        VideoPlayer.resetUiTimer()
    end
end

function VideoPlayer.hideUI()
    if VideoPlayer.widgets.controlLayer then
        VideoPlayer.widgets.controlLayer.animate().alpha(0).setDuration(300).start()
    end
end

function VideoPlayer.toggleUI()
    if VideoPlayer.widgets.controlLayer and VideoPlayer.widgets.controlLayer.getAlpha() > 0.5 then
        VideoPlayer.hideUI()
    else
        VideoPlayer.showUI()
    end
end

function VideoPlayer.resetUiTimer()
    if VideoPlayer.uiHideTimer then VideoPlayer.uiHideTimer.stop() end
    VideoPlayer.uiHideTimer = Ticker()
    VideoPlayer.uiHideTimer.Period = 3000
    VideoPlayer.uiHideTimer.onTick = function()
        VideoPlayer.uiHideTimer.stop()
        VideoPlayer.hideUI()
    end
    VideoPlayer.uiHideTimer.start()
end

function VideoPlayer.requestAudioFocus()
    VideoPlayer.audioManager.requestAudioFocus(nil, AudioManager.STREAM_MUSIC, AudioManager.AUDIOFOCUS_GAIN)
end

function VideoPlayer.abandonAudioFocus()
    VideoPlayer.audioManager.abandonAudioFocus(nil)
end

function VideoPlayer.getCurrentItem()
    return VideoPlayer.playlist[VideoPlayer.currentIndex]
end

function VideoPlayer.play(index)
    if not VideoPlayer.playlist[index] then return end
    
    VideoPlayer.requestAudioFocus()
    VideoPlayer.initMediaSession()
    
    if VideoPlayer.mediaSession then
        VideoPlayer.mediaSession.setActive(true)
    end
    
    VideoPlayer.currentIndex = index
    VideoPlayer.isSilentRetry = false
    VideoPlayer.isManualStop = false
    
    local item = VideoPlayer.playlist[index]
    VideoPlayer.currentUrl = item.url 
    VideoPlayer.isLive = item.id and item.id:find("live")
    
    HistoryManager.add(item)
    
    speak("جاري تحميل الفيديو: " .. item.name)

    VideoPlayer.updateMetadata()
    VideoPlayer.updatePlaybackState(PlaybackState.STATE_PLAYING)
    
    pcall(VideoPlayer.sendNotification, item.name, true)
    VideoPlayer.showVideoUI()
end

function VideoPlayer.setDialogOrientation(orientation)
    pcall(function()
        activity.setRequestedOrientation(orientation)
    end)
end

function VideoPlayer.toggleFullscreen()
    if not VideoPlayer.dialog then return end
    local win = VideoPlayer.dialog.getWindow()
    local videoView = VideoPlayer.widgets.videoView
    local controlLayer = VideoPlayer.widgets.controlLayer
    
    if not VideoPlayer.isFullscreen then
        VideoPlayer.isFullscreen = true
        VideoPlayer.setDialogOrientation(0)
        
        local params = win.getAttributes()
        params.flags = params.flags | WindowManager.LayoutParams.FLAG_FULLSCREEN | WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS
        params.width = WindowManager.LayoutParams.MATCH_PARENT
        params.height = WindowManager.LayoutParams.MATCH_PARENT
        if Build.VERSION.SDK_INT >= 28 then
            params.layoutInDisplayCutoutMode = WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES
        end
        win.setAttributes(params)
        
        if Build.VERSION.SDK_INT >= 19 then
             win.getDecorView().setSystemUiVisibility(
                View.SYSTEM_UI_FLAG_LAYOUT_STABLE |
                View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION |
                View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN |
                View.SYSTEM_UI_FLAG_HIDE_NAVIGATION |
                View.SYSTEM_UI_FLAG_FULLSCREEN |
                View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY
            )
        end
        
        if controlLayer then 
            controlLayer.setAlpha(0) 
            controlLayer.setVisibility(View.VISIBLE)
        end
        
        if videoView and VideoPlayer.videoWidth > 0 and VideoPlayer.videoHeight > 0 then
            local metrics = DisplayMetrics()
            activity.getWindowManager().getDefaultDisplay().getRealMetrics(metrics)
            local screenWidth = math.max(metrics.widthPixels, metrics.heightPixels)
            local screenHeight = math.min(metrics.widthPixels, metrics.heightPixels)
            
            local scale = math.max(screenWidth / VideoPlayer.videoWidth, screenHeight / VideoPlayer.videoHeight)
            
            local targetWidth = math.floor(VideoPlayer.videoWidth * scale)
            local targetHeight = math.floor(VideoPlayer.videoHeight * scale)
            
            local lp = RelativeLayout.LayoutParams(targetWidth, targetHeight)
            lp.addRule(13)
            videoView.setLayoutParams(lp)
            videoView.requestLayout()
        end
    else
        VideoPlayer.isFullscreen = false
        VideoPlayer.setDialogOrientation(1)
        
        local params = win.getAttributes()
        params.flags = params.flags & (~WindowManager.LayoutParams.FLAG_FULLSCREEN) & (~WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS)
        win.setAttributes(params)
        
        if Build.VERSION.SDK_INT >= 19 then
             win.getDecorView().setSystemUiVisibility(0)
        end

        if controlLayer then 
            controlLayer.setAlpha(0)
            controlLayer.setVisibility(View.VISIBLE)
        end
        
        local lp = RelativeLayout.LayoutParams(-1, -1)
        lp.addRule(13)
        videoView.setLayoutParams(lp)
    end
end

function VideoPlayer.showVideoUI()
    local currentItem = VideoPlayer.playlist[VideoPlayer.currentIndex]
    if not currentItem then return end
    
    VideoPlayer.isFullscreen = false
    
    local layout = {
        RelativeLayout,
        layout_width = "fill",
        layout_height = "fill",
        backgroundColor = "#000000",
        
        {
            VideoView,
            id = "vVideoView",
            layout_width = "fill",
            layout_height = "fill",
            layout_centerInParent = true
        },
        
        {
            ProgressBar,
            id = "vLoading",
            layout_width = "wrap",
            layout_height = "wrap",
            layout_centerInParent = true,
            importantForAccessibility=2
        },
        
        {
            LinearLayout,
            id = "vControlLayer",
            orientation = "vertical",
            layout_width = "fill",
            layout_height = "fill",
            backgroundColor = "#CC000000", 
            importantForAccessibility = 2,
            
            {
                LinearLayout,
                layout_width = "fill",
                orientation = "horizontal",
                padding = "16dp",
                gravity = "center_vertical",
                importantForAccessibility = 2,
                {
                    TextView,
                    id = "vTitle",
                    text = currentItem.name,
                    textSize = "20sp",
                    Typeface = Typeface.DEFAULT_BOLD,
                    textColor = COL_TEXT_PRI,
                    layout_weight = "1",
                    paddingLeft = "8dp",
                    focusable=true,
                },
                {
                    Button,
                    id = "vFsBtn",
                    text = "📺",
                    contentDescription = "تبديل وضع ملء الشاشة",
                    textSize = "18sp",
                    backgroundColor = "#00000000",
                    textColor = COL_TEXT_PRI,
                    focusable=true,
                    layout_height="48dp", 
                    layout_width="48dp",
                    onClick = function() VideoPlayer.toggleFullscreen() end
                }
            },
            
            {
                View,
                layout_width = "fill",
                layout_height = "0dp",
                layout_weight = "1",
                focusable=true,
                contentDescription="إظهار/إخفاء عناصر التحكم",
                onClick = function()
                    VideoPlayer.toggleUI()
                end
            },
            
            {
                LinearLayout,
                orientation = "vertical",
                layout_width = "fill",
                padding = "20dp",
                importantForAccessibility = 2,
                {
                    SeekBar,
                    id = "vSeek",
                    layout_width = "fill",
                    layout_marginBottom = "15dp",
                    focusable=true,
                    layout_height="30dp"
                },
                {
                    LinearLayout,
                    layout_width = "fill",
                    orientation = "horizontal",
                    gravity = "center_vertical",
                    importantForAccessibility = 2,
                    {
                        TextView,
                        id = "vTime",
                        text = "00:00 / 00:00",
                        textColor = COL_TEXT_SEC,
                        textSize = "14sp",
                        focusable=true,
                        padding="5dp"
                    },
                    { Space, layout_weight = "1" },
                    {
                        Button, id = "vPrevBtn", text = "⏮️", contentDescription = "المقطع السابق", textSize = "22sp", 
                        layout_width = "56dp", layout_height="56dp",
                        focusable=true,
                        backgroundColor = "#00000000", onClick = function() VideoPlayer.prev() end
                    },
                    {
                        Button, id = "vRewBtn", text = "⏩", contentDescription = "تأخير 10 ثواني", textSize = "22sp", 
                        layout_width = "56dp", layout_height="56dp",
                        focusable=true,
                        backgroundColor = "#00000000", onClick = function() VideoPlayer.seekRewind() end
                    },
                    {
                        Button, id = "vPlayBtn", text = "⏸️", contentDescription = "إيقاف مؤقت", textSize = "32sp", 
                        layout_width = "72dp", layout_height="72dp",
                        focusable=true,
                        backgroundColor = "#00000000", onClick = function() VideoPlayer.togglePlay() end
                    },
                    {
                        Button, id = "vFwdBtn", text = "⏪", contentDescription = "تقديم 10 ثواني", textSize = "22sp", 
                        layout_width = "56dp", layout_height="56dp",
                        focusable=true,
                        backgroundColor = "#00000000", onClick = function() VideoPlayer.seekForward() end
                    },
                    {
                        Button, id = "vNextBtn", text = "⏭️", contentDescription = "المقطع التالي", textSize = "22sp", 
                        layout_width = "56dp", layout_height="56dp",
                        focusable=true,
                        backgroundColor = "#00000000", onClick = function() VideoPlayer.next() end
                    },
                    { Space, layout_weight = "1" },
                    {
                        Button, id = "vPlaylistBtn", text = "📑", contentDescription = "عرض قائمة التشغيل", textSize = "18sp", 
                        layout_width = "56dp", layout_height="56dp",
                        focusable=true,
                        backgroundColor = "#00000000", onClick = function() VideoPlayer.showPlaylistDialog() end
                    },
                    {
                        Button, id = "vFavBtn", text = "❤️", contentDescription = "إضافة أو إزالة من المفضلة", textSize = "18sp", 
                        layout_width = "56dp", layout_height="56dp",
                        focusable=true,
                        backgroundColor = "#00000000", onClick = function() VideoPlayer.toggleFavorite() end
                    },
                    {
                        Button, id = "vCloseBtn", text = "✖️", contentDescription = "إغلاق المشغل", textSize = "18sp", 
                        layout_width = "56dp", layout_height="56dp",
                        focusable=true,
                        backgroundColor = "#00000000", onClick = function() VideoPlayer.stop() end
                    }
                }
            }
        }
    }
    
    VideoPlayer.dialog = LuaDialog(activity)
    VideoPlayer.dialog.requestWindowFeature(Window.FEATURE_NO_TITLE) 
    VideoPlayer.dialog.setView(loadlayout(layout))
    
    local win = VideoPlayer.dialog.getWindow()
    win.setFlags(WindowManager.LayoutParams.FLAG_FULLSCREEN, WindowManager.LayoutParams.FLAG_FULLSCREEN)
    win.setLayout(WindowManager.LayoutParams.MATCH_PARENT, WindowManager.LayoutParams.MATCH_PARENT)
    win.setBackgroundDrawable(ColorDrawable(0))
    if Build.VERSION.SDK_INT >= 19 then
        win.getDecorView().setSystemUiVisibility(
            View.SYSTEM_UI_FLAG_LAYOUT_STABLE |
            View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION |
            View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN |
            View.SYSTEM_UI_FLAG_HIDE_NAVIGATION |
            View.SYSTEM_UI_FLAG_FULLSCREEN |
            View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY
        )
    end
    
    VideoPlayer.setDialogOrientation(0)
    
    VideoPlayer.widgets.title = vTitle
    VideoPlayer.widgets.videoView = vVideoView
    VideoPlayer.widgets.loading = vLoading
    VideoPlayer.widgets.seek = vSeek
    VideoPlayer.widgets.time = vTime
    VideoPlayer.widgets.playBtn = vPlayBtn
    VideoPlayer.widgets.favBtn = vFavBtn
    VideoPlayer.widgets.fsBtn = vFsBtn
    VideoPlayer.widgets.controlLayer = vControlLayer
    
    pcall(function()
        if Build.VERSION.SDK_INT >= 22 then
            vPlayBtn.setAccessibilityTraversalAfter(vTitle.getId())
            vSeek.setAccessibilityTraversalAfter(vPlayBtn.getId())
            vTime.setAccessibilityTraversalAfter(vSeek.getId())
            vPrevBtn.setAccessibilityTraversalAfter(vTime.getId())
            vRewBtn.setAccessibilityTraversalAfter(vPrevBtn.getId())
            vFwdBtn.setAccessibilityTraversalAfter(vRewBtn.getId())
            vNextBtn.setAccessibilityTraversalAfter(vFwdBtn.getId())
            vPlaylistBtn.setAccessibilityTraversalAfter(vNextBtn.getId())
            vFavBtn.setAccessibilityTraversalAfter(vPlaylistBtn.getId())
            vCloseBtn.setAccessibilityTraversalAfter(vFavBtn.getId())
            vFsBtn.setAccessibilityTraversalAfter(vCloseBtn.getId())
        end
    end)
    
    VideoPlayer.setupVideoView()
    VideoPlayer.updateFavoriteButton()
    
    if vControlLayer then
        vControlLayer.setAlpha(0)
        vControlLayer.setVisibility(View.VISIBLE)
    end
    
    VideoPlayer.dialog.show()
    
    VideoPlayer.dialog.setOnDismissListener(DialogInterface.OnDismissListener{
        onDismiss = function(d)
            VideoPlayer.stop()
        end
    })
end

function VideoPlayer.setupVideoView()
    local videoView = VideoPlayer.widgets.videoView
    local url = VideoPlayer.currentUrl
    
    if not videoView or not url then return end
    
    VideoPlayer.isManualStop = false -- Fix: State Reset
    
    if VideoPlayer.widgets.loading then
        VideoPlayer.widgets.loading.setVisibility(View.VISIBLE)
    end
    
    pcall(function()
        local uri = Uri.parse(url)
        local headers = HashMap()
        headers.put("User-Agent", "VLC/3.0.13 LibVLC/3.0.13")
        
        if Build.VERSION.SDK_INT >= 21 then
            videoView.setVideoURI(uri, headers)
        else
            videoView.setVideoURI(uri)
        end
        
        videoView.setOnPreparedListener(MediaPlayer.OnPreparedListener{
            onPrepared = function(mp)
                VideoPlayer.isPrepared = true
                VideoPlayer.isSilentRetry = false 
                
                VideoPlayer.videoWidth = mp.getVideoWidth()
                VideoPlayer.videoHeight = mp.getVideoHeight()
                
                if VideoPlayer.widgets.loading then
                    VideoPlayer.widgets.loading.setVisibility(View.GONE)
                end
                
                mp.start()
                VideoPlayer.isPlaying = true
                VideoPlayer.startTimer()
                VideoPlayer.updateUIState(true)

                local saved = VideoPlayer.getSavedPosition()
                if saved > 0 and not VideoPlayer.isLive then
                    mp.seekTo(saved)
                    local item = VideoPlayer.getCurrentItem()
                    if item and item.id then
                        HistoryManager.updatePosition(item.id, saved, mp.getDuration())
                    end
                end
            end
        })
        
        videoView.setOnErrorListener(MediaPlayer.OnErrorListener{
            onError = function(mp, what, extra)
                if not VideoPlayer.isManualStop then
                    VideoPlayer.attemptRetry() -- Clean: No speak
                end
                return true
            end
        })
        
        videoView.setOnCompletionListener(MediaPlayer.OnCompletionListener{
            onCompletion = function(mp)
                if VideoPlayer.isLive then
                    if not VideoPlayer.isManualStop then -- Fix: Completion Listener Update
                         VideoPlayer.attemptRetry()
                    end
                else
                    local item = VideoPlayer.getCurrentItem()
                    VideoPlayer.savePosition(0)
                    
                    if item.type == "movie" then
                        HistoryManager.remove(item.id)
                        VideoPlayer.stop()
                    elseif VideoPlayer.currentIndex < #VideoPlayer.playlist then
                        speak("بدء الحلقة التالية")
                        VideoPlayer.next()
                    else
                        speak("انتهى الموسم")
                        VideoPlayer.stop()
                    end
                end
            end
        })
        
        if VideoPlayer.widgets.seek then
            VideoPlayer.widgets.seek.setOnSeekBarChangeListener{
                onStopTrackingTouch = function(seekBar)
                    if videoView then
                        videoView.seekTo(seekBar.getProgress())
                    end
                end
            }
        end
    end)
end

function VideoPlayer.attemptRetry()
    if VideoPlayer.retryCount < VideoPlayer.maxRetries then
        VideoPlayer.retryCount = VideoPlayer.retryCount + 1
        -- Clean: No speak
        if VideoPlayer.retryTimer then VideoPlayer.retryTimer.stop() end
        VideoPlayer.retryTimer = Ticker()
        VideoPlayer.retryTimer.Period = 800
        VideoPlayer.retryTimer.onTick = function()
            VideoPlayer.retryTimer.stop()
            VideoPlayer.setupVideoView()
        end
        VideoPlayer.retryTimer.start()
    else
        -- Clean: No speak
        VideoPlayer.retryCount = 0
        VideoPlayer.isSilentRetry = false
        if VideoPlayer.widgets.loading then VideoPlayer.widgets.loading.setVisibility(View.GONE) end
    end
end

function VideoPlayer.togglePlay()
    local now = System.currentTimeMillis()
    if now - lastActionTime < 600 then return end 
    lastActionTime = now

    local videoView = VideoPlayer.widgets.videoView
    if not videoView then return end
    
    local isPlaying = videoView.isPlaying()
    
    if isPlaying then
        if VideoPlayer.isLive then
            VideoPlayer.isManualStop = true -- Fix: Pause Logic
            videoView.stopPlayback()
            VideoPlayer.isPlaying = false
            VideoPlayer.updateUIState(false)
        else
            videoView.pause()
            VideoPlayer.isPlaying = false
            VideoPlayer.savePosition(videoView.getCurrentPosition())
            VideoPlayer.updateUIState(false)
        end
    else
        VideoPlayer.isManualStop = false -- Fix: Resume Logic
        if VideoPlayer.isLive then
            VideoPlayer.isSilentRetry = true
            if VideoPlayer.widgets.loading then
                VideoPlayer.widgets.loading.setVisibility(View.VISIBLE)
            end
            VideoPlayer.setupVideoView()
        else
            videoView.start()
            VideoPlayer.isPlaying = true
            VideoPlayer.updateUIState(true)
        end
    end
end

function VideoPlayer.stop()
    VideoPlayer.setDialogOrientation(1)
    
    if VideoPlayer.widgets.videoView then
        pcall(function()
            if VideoPlayer.widgets.videoView.isPlaying() then
                VideoPlayer.savePosition(VideoPlayer.widgets.videoView.getCurrentPosition())
            end
            VideoPlayer.widgets.videoView.stopPlayback()
        end)
    end
    
    VideoPlayer.stopTimer()
    if VideoPlayer.retryTimer then VideoPlayer.retryTimer.stop() end
    if VideoPlayer.uiHideTimer then VideoPlayer.uiHideTimer.stop(); VideoPlayer.uiHideTimer = nil end
    VideoPlayer.abandonAudioFocus()
    VideoPlayer.cancelNotification()
    
    if VideoPlayer.mediaSession then
        pcall(function()
            VideoPlayer.mediaSession.setActive(false)
            VideoPlayer.mediaSession.release()
        end)
        VideoPlayer.mediaSession = nil
    end
    VideoPlayer.retryCount = 0
    VideoPlayer.isPlaying = false
    VideoPlayer.isPrepared = false
    VideoPlayer.isSilentRetry = false
    VideoPlayer.isManualStop = false
    
    if VideoPlayer.dialog then 
        VideoPlayer.dialog.dismiss() 
        VideoPlayer.dialog = nil
    end
end

function VideoPlayer.next()
    VideoPlayer.retryCount = 0
    VideoPlayer.isSilentRetry = false
    VideoPlayer.isManualStop = false
    if VideoPlayer.currentIndex < #VideoPlayer.playlist then
        VideoPlayer.currentIndex = VideoPlayer.currentIndex + 1
        local item = VideoPlayer.playlist[VideoPlayer.currentIndex]
        VideoPlayer.currentUrl = item.url
        VideoPlayer.isLive = item.id and item.id:find("live")
        HistoryManager.add(item)
        HistoryManager.updatePosition(item.id, 0)
        
        if VideoPlayer.widgets.title then
            VideoPlayer.widgets.title.setText(item.name)
        end
        VideoPlayer.updateFavoriteButton()
        pcall(VideoPlayer.sendNotification, item.name, true)
        VideoPlayer.setupVideoView()
    else
        speak("النهاية")
    end
end

function VideoPlayer.prev()
    VideoPlayer.retryCount = 0
    VideoPlayer.isSilentRetry = false
    VideoPlayer.isManualStop = false
    if VideoPlayer.currentIndex > 1 then
        VideoPlayer.currentIndex = VideoPlayer.currentIndex - 1
        local item = VideoPlayer.playlist[VideoPlayer.currentIndex]
        VideoPlayer.currentUrl = item.url
        VideoPlayer.isLive = item.id and item.id:find("live")
        HistoryManager.add(item)
        
        if VideoPlayer.widgets.title then
            VideoPlayer.widgets.title.setText(item.name)
        end
        VideoPlayer.updateFavoriteButton()
        pcall(VideoPlayer.sendNotification, item.name, true)
        VideoPlayer.setupVideoView()
    else
        speak("البداية")
    end
end

function VideoPlayer.seekForward()
    local videoView = VideoPlayer.widgets.videoView
    if videoView and VideoPlayer.isPlaying then
        local curr = videoView.getCurrentPosition()
        videoView.seekTo(curr + 10000)
    end
end

function VideoPlayer.seekRewind()
    local videoView = VideoPlayer.widgets.videoView
    if videoView and VideoPlayer.isPlaying then
        local curr = videoView.getCurrentPosition()
        videoView.seekTo(math.max(0, curr - 10000))
    end
end

function VideoPlayer.savePosition(pos)
    local item = VideoPlayer.playlist[VideoPlayer.currentIndex]
    local videoView = VideoPlayer.widgets.videoView
    if item and item.id and (not VideoPlayer.isLive) then 
        local dur = 0
        if videoView then dur = videoView.getDuration() end
        
        if pos == 0 then 
            setData("resume_"..item.id, nil)
        elseif pos > 5000 then 
            setData("resume_"..item.id, tostring(pos))
            HistoryManager.updatePosition(item.id, pos, dur)
        end
    end
end

function VideoPlayer.getSavedPosition()
    local item = VideoPlayer.playlist[VideoPlayer.currentIndex]
    if item and item.id then
        local pos = getData("resume_"..item.id)
        return tonumber(pos) or 0
    end
    return 0
end

function VideoPlayer.startTimer()
    VideoPlayer.stopTimer()
    VideoPlayer.timer = Ticker()
    VideoPlayer.timer.Period = 1000
    local tickCount = 0
    VideoPlayer.timer.onTick = function()
        local videoView = VideoPlayer.widgets.videoView
        if videoView and VideoPlayer.isPlaying and VideoPlayer.widgets.seek then
            pcall(function()
                local current = videoView.getCurrentPosition()
                local total = videoView.getDuration()
                if VideoPlayer.isLive or total <= 0 then total = 100 end 
                
                VideoPlayer.widgets.seek.setMax(total)
                VideoPlayer.widgets.seek.setProgress(current)
                
                local cMins = math.floor(current/60000)
                local cSecs = math.floor((current%60000)/1000)
                local tMins = math.floor(total/60000)
                local tSecs = math.floor((total%60000)/1000)
                
                local t_str = VideoPlayer.isLive and "Live" or string.format("%02d:%02d", tMins, tSecs)
                VideoPlayer.widgets.time.setText(string.format("%02d:%02d / %s", cMins, cSecs, t_str))
                
                local readableDesc = string.format("تم تشغيل %d دقيقة و %d ثانية من أصل %d دقيقة", cMins, cSecs, tMins)
                VideoPlayer.widgets.seek.setContentDescription(readableDesc)
                
                tickCount = tickCount + 1
                if tickCount >= 10 then
                    tickCount = 0
                    local item = VideoPlayer.getCurrentItem()
                    if item and item.id and not VideoPlayer.isLive then
                        HistoryManager.updatePosition(item.id, current, total)
                        if current > 5000 then
                            setData("resume_"..item.id, tostring(current))
                        end
                    end
                end
            end)
        end
    end
    VideoPlayer.timer.start()
end

function VideoPlayer.stopTimer()
    if VideoPlayer.timer then VideoPlayer.timer.stop(); VideoPlayer.timer = nil end
end

function VideoPlayer.updateUIState(isPlaying)
    if VideoPlayer.playlist[VideoPlayer.currentIndex] then
        pcall(VideoPlayer.sendNotification, VideoPlayer.playlist[VideoPlayer.currentIndex].name, isPlaying)
    end

    if VideoPlayer.widgets.playBtn then
        local btnText = isPlaying and "⏸️" or "▶️"
        local descText = isPlaying and "إيقاف مؤقت" or "تشغيل"
        VideoPlayer.widgets.playBtn.setText(btnText)
        VideoPlayer.widgets.playBtn.setContentDescription(descText)
        
        -- Clean: No announceForAccessibility
    end
    
    pcall(function()
        if VideoPlayer.mediaSession then
             local state = isPlaying and PlaybackState.STATE_PLAYING or PlaybackState.STATE_PAUSED
             VideoPlayer.updatePlaybackState(state)
             VideoPlayer.updateMetadata()
        end
    end)
end

function VideoPlayer.updateFavoriteButton()
    if VideoPlayer.widgets.favBtn then
        local item = VideoPlayer.getCurrentItem()
        local isFav = FavoritesManager.isFavorite(item.id)
        VideoPlayer.widgets.favBtn.setText(isFav and "❤️" or "🤍")
        VideoPlayer.widgets.favBtn.setContentDescription(isFav and "إزالة من المفضلة" or "إضافة للمفضلة")
    end
end

function VideoPlayer.toggleFavorite()
    local item = VideoPlayer.getCurrentItem()
    if item then
        FavoritesManager.toggle(item)
        VideoPlayer.updateFavoriteButton()
    end
end

function VideoPlayer.showPlaylistDialog()
    local names = {}
    for i, v in ipairs(VideoPlayer.playlist) do
        local prefix = (i == VideoPlayer.currentIndex) and "🔊 " or ""
        local favIcon = FavoritesManager.isFavorite(v.id) and " ❤️" or ""
        table.insert(names, prefix .. v.name .. favIcon)
    end
    local dlg = LuaDialog(activity)
    dlg.setTitle("قائمة التشغيل")
    dlg.setItems(names)
    dlg.setOnItemClickListener(function(l,v,p,i)
        VideoPlayer.currentIndex = i
        local item = VideoPlayer.playlist[i]
        VideoPlayer.currentUrl = item.url
        VideoPlayer.isLive = item.id and item.id:find("live")
        HistoryManager.add(item)
        if VideoPlayer.widgets.title then VideoPlayer.widgets.title.setText(item.name) end
        VideoPlayer.updateFavoriteButton()
        pcall(VideoPlayer.sendNotification, item.name, true)
        VideoPlayer.setupVideoView()
    end)
    dlg.setNegativeButton("🔙 رجوع", nil)
    dlg.show()
end

function VideoPlayer.loadList(list, startIndex)
    VideoPlayer.playlist = list
    VideoPlayer.play(startIndex)
end

AudioPlayer = {
    player = nil,
    playlist = {},
    currentIndex = 1,
    mediaSession = nil,
    timer = nil,
    retryTimer = nil,
    bufferTimer = nil,
    dialog = nil,
    widgets = {},
    notification_id = 112233,
    audioManager = activity.getSystemService(Context.AUDIO_SERVICE),
    
    retryCount = 0,
    maxRetries = 10,
    isLive = false,
    currentUrl = nil,
    isSilentRetry = false,
    isManualStop = false, -- Fix: State Management Flag
    
    sleepTargetTime = nil 
}

function AudioPlayer.initMediaSession()
    if AudioPlayer.mediaSession then return end
    pcall(function()
        AudioPlayer.mediaSession = MediaSession(activity, "XtreamAudio")
        AudioPlayer.mediaSession.setFlags(MediaSession.FLAG_HANDLES_MEDIA_BUTTONS | MediaSession.FLAG_HANDLES_TRANSPORT_CONTROLS)
        
        AudioPlayer.mediaSession.setCallback(luajava.override(MediaSession.Callback, {
            onPlay = function() AudioPlayer.togglePlay() end,
            onPause = function() AudioPlayer.togglePlay() end,
            onSkipToNext = function() AudioPlayer.next() end,
            onSkipToPrevious = function() AudioPlayer.prev() end,
            onMediaButtonEvent = function(intent)
                AudioPlayer.togglePlay()
                return true
            end
        }))
        
        AudioPlayer.mediaSession.setActive(true)
    end)
end

function AudioPlayer.updatePlaybackState(state)
    if not AudioPlayer.mediaSession then return end
    pcall(function()
        local actions = PlaybackState.ACTION_PLAY | PlaybackState.ACTION_PAUSE | 
                      PlaybackState.ACTION_PLAY_PAUSE | PlaybackState.ACTION_SKIP_TO_NEXT |
                      PlaybackState.ACTION_SKIP_TO_PREVIOUS | PlaybackState.ACTION_STOP
                      
        local pos = 0
        if AudioPlayer.player then pos = AudioPlayer.player.getCurrentPosition() end
        
        local pbState = PlaybackState.Builder()
            .setActions(actions)
            .setState(state, pos, 1.0)
            .build()
        AudioPlayer.mediaSession.setPlaybackState(pbState)
    end)
end

function AudioPlayer.updateMetadata()
    if not AudioPlayer.mediaSession then return end
    local item = AudioPlayer.playlist[AudioPlayer.currentIndex]
    if not item then return end
    pcall(function()
        local meta = MediaMetadata.Builder()
            .putString(MediaMetadata.METADATA_KEY_TITLE, item.name)
            .putString(MediaMetadata.METADATA_KEY_ARTIST, "Xtream Player")
            .build()
        AudioPlayer.mediaSession.setMetadata(meta)
    end)
end

function AudioPlayer.init()
    if not AudioPlayer.player then
        AudioPlayer.player = MediaPlayer()
        AudioPlayer.player.setAudioStreamType(AudioManager.STREAM_MUSIC)
        AudioPlayer.player.setWakeMode(activity, PowerManager.PARTIAL_WAKE_LOCK)
        
        AudioPlayer.player.setOnCompletionListener(MediaPlayer.OnCompletionListener{
            onCompletion=function(mp)
                if AudioPlayer.isLive then
                    if not AudioPlayer.isManualStop then -- Fix: Completion Listener Update
                        AudioPlayer.attemptRetry()
                    end
                else
                    local duration = mp.getDuration()
                    local current = mp.getCurrentPosition()
                    if duration > 0 and (duration - current) > 10000 then
                        speak("انقطع الاتصال، استكمال...")
                        AudioPlayer.savePosition(current) 
                        AudioPlayer.playRetry() 
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
        
        AudioPlayer.player.setOnErrorListener(MediaPlayer.OnErrorListener{
            onError=function(mp, what, extra)
                if not AudioPlayer.isManualStop then
                     AudioPlayer.attemptRetry() -- Clean: No speak
                end
                return true
            end
        })
    end
end

function AudioPlayer.attemptRetry()
    if AudioPlayer.retryCount < AudioPlayer.maxRetries then
        AudioPlayer.retryCount = AudioPlayer.retryCount + 1
        -- Clean: No speak
        if AudioPlayer.retryTimer then AudioPlayer.retryTimer.stop() end
        AudioPlayer.retryTimer = Ticker()
        AudioPlayer.retryTimer.Period = 800
        AudioPlayer.retryTimer.onTick = function()
            AudioPlayer.retryTimer.stop()
            AudioPlayer.playRetry() 
        end
        AudioPlayer.retryTimer.start()
        AudioPlayer.updateUIState(false)
    else
        -- Clean: No speak
        AudioPlayer.retryCount = 0
        AudioPlayer.isSilentRetry = false
        AudioPlayer.updateUIState(false)
    end
end

function AudioPlayer.requestAudioFocus()
    AudioPlayer.audioManager.requestAudioFocus(nil, AudioManager.STREAM_MUSIC, AudioManager.AUDIOFOCUS_GAIN)
end

function AudioPlayer.abandonAudioFocus()
    AudioPlayer.audioManager.abandonAudioFocus(nil)
end

function AudioPlayer.sendNotification(title, isPlaying)
    local ns = Context.NOTIFICATION_SERVICE
    local nm = activity.getSystemService(ns)
    local channelId = "xtream_final_ch"
    
    if Build.VERSION.SDK_INT >= 26 then
        local channel = NotificationChannel(channelId, "Xtream Player", 3)
        nm.createNotificationChannel(channel)
    end
    
    local builder = Notification.Builder(activity)
    if Build.VERSION.SDK_INT >= 26 then builder.setChannelId(channelId) end
    
    builder.setContentTitle("Xtream Audio")
    builder.setContentText(title)
    builder.setSmallIcon(android.R.drawable.ic_media_play)
    builder.setLargeIcon(BitmapFactory.decodeResource(activity.getResources(), android.R.drawable.ic_media_play))
    builder.setOngoing(isPlaying)
    builder.setShowWhen(false)
    builder.setVisibility(1)
    
    local pFlag = 0
    if Build.VERSION.SDK_INT >= 31 then pFlag = 67108864 end 
    
    local intent = Intent(activity, activity.getClass())
    local pendingIntent = PendingIntent.getActivity(activity, 0, intent, pFlag)
    builder.setContentIntent(pendingIntent)
    
    local iPrev = Intent(ACTION_PREV); local pPrev = PendingIntent.getBroadcast(activity, 1, iPrev, pFlag)
    builder.addAction(android.R.drawable.ic_media_previous, "السابق", pPrev)
    
    local iPlay = Intent(ACTION_PLAY_PAUSE); local pPlay = PendingIntent.getBroadcast(activity, 2, iPlay, pFlag)
    local playIcon = isPlaying and android.R.drawable.ic_media_pause or android.R.drawable.ic_media_play
    builder.addAction(playIcon, "Play", pPlay)
    
    local iNext = Intent(ACTION_NEXT); local pNext = PendingIntent.getBroadcast(activity, 3, iNext, pFlag)
    builder.addAction(android.R.drawable.ic_media_next, "التالي", pNext)
    
    local iClose = Intent(ACTION_CLOSE); local pClose = PendingIntent.getBroadcast(activity, 4, iClose, pFlag)
    builder.addAction(android.R.drawable.ic_menu_close_clear_cancel, "إغلاق", pClose)
    
    pcall(function()
        local style = Notification.MediaStyle()
        if AudioPlayer.mediaSession then style.setMediaSession(AudioPlayer.mediaSession.getSessionToken()) end
        style.setShowActionsInCompactView(0, 1, 2)
        builder.setStyle(style)
    end)
    
    nm.notify(AudioPlayer.notification_id, builder.build())
end

function AudioPlayer.cancelNotification()
    local ns = Context.NOTIFICATION_SERVICE
    local nm = activity.getSystemService(ns)
    nm.cancel(AudioPlayer.notification_id)
end

function AudioPlayer.getCurrentItem()
    return AudioPlayer.playlist[AudioPlayer.currentIndex]
end

function AudioPlayer.play(index)
    if not AudioPlayer.playlist[index] then return end
    
    AudioPlayer.init()
    AudioPlayer.initMediaSession()
    AudioPlayer.requestAudioFocus()
    
    if AudioPlayer.player.isPlaying() then
        AudioPlayer.savePosition(AudioPlayer.player.getCurrentPosition())
    end
    
    if AudioPlayer.mediaSession then
        AudioPlayer.mediaSession.setActive(true)
    end
    
    AudioPlayer.retryCount = 0
    AudioPlayer.player.reset()
    AudioPlayer.currentIndex = index
    AudioPlayer.isSilentRetry = false
    AudioPlayer.isManualStop = false -- Fix: Reset
    
    local item = AudioPlayer.playlist[index]
    AudioPlayer.currentUrl = item.url 
    AudioPlayer.isLive = item.id and item.id:find("live")
    
    HistoryManager.add(item)
    
    if AudioPlayer.dialog and AudioPlayer.widgets.title then
        AudioPlayer.widgets.title.setText(item.name)
    end
    
    AudioPlayer.updateFavoriteButton()
    
    speak("تحميل: " .. item.name)

    AudioPlayer.updateMetadata()
    AudioPlayer.updatePlaybackState(PlaybackState.STATE_PLAYING)
    
    pcall(AudioPlayer.sendNotification, item.name, true)
    
    AudioPlayer.executeLoad()
end

function AudioPlayer.playRetry()
    AudioPlayer.init()
    AudioPlayer.player.reset()
    AudioPlayer.executeLoad()
end

function AudioPlayer.executeLoad()
    AudioPlayer.isManualStop = false -- Fix: State Reset
    pcall(function()
        local uri = Uri.parse(AudioPlayer.currentUrl)
        local headers = HashMap()
        headers.put("User-Agent", "VLC/3.0.13 LibVLC/3.0.13")
        AudioPlayer.player.setDataSource(activity, uri, headers)
        AudioPlayer.player.prepareAsync()
    end)
    
    AudioPlayer.player.setOnPreparedListener(MediaPlayer.OnPreparedListener{
        onPrepared=function(mp)
            AudioPlayer.retryCount = 0
            AudioPlayer.isSilentRetry = false
            
            mp.start()
            AudioPlayer.startTimer()
            AudioPlayer.updateUIState(true)

            local saved = AudioPlayer.getSavedPosition()
            if saved > 0 and not AudioPlayer.isLive then 
                mp.seekTo(saved); speak("استكمال") 
            end
        end
    })
end

function AudioPlayer.togglePlay()
    local now = System.currentTimeMillis()
    if now - lastActionTime < 600 then return end 
    lastActionTime = now

    if AudioPlayer.player.isPlaying() then
        if AudioPlayer.isLive then
             AudioPlayer.isManualStop = true -- Fix: Pause Logic
             AudioPlayer.player.reset() 
             AudioPlayer.updateUIState(false)
             speak("إيقاف (مباشر)")
        else
             AudioPlayer.player.pause()
             AudioPlayer.savePosition(AudioPlayer.player.getCurrentPosition())
             AudioPlayer.updateUIState(false)
             speak("إيقاف مؤقت")
        end
        if AudioPlayer.bufferTimer then AudioPlayer.bufferTimer.stop() end
    else
        AudioPlayer.requestAudioFocus()
        AudioPlayer.isManualStop = false -- Fix: Resume Logic
        if AudioPlayer.isLive then
             AudioPlayer.isSilentRetry = true
             AudioPlayer.executeLoad()
        else
            AudioPlayer.player.start()
            AudioPlayer.updateUIState(true)
            speak("تشغيل")
        end
    end
end

function AudioPlayer.stop()
    if AudioPlayer.player then
        if AudioPlayer.player.isPlaying() then
            local item = AudioPlayer.getCurrentItem()
            local pos = AudioPlayer.player.getCurrentPosition()
            AudioPlayer.savePosition(pos)
            if item and item.id then
                HistoryManager.updatePosition(item.id, pos)
            end
        end
        AudioPlayer.player.stop()
        AudioPlayer.stopTimer()
        if AudioPlayer.retryTimer then AudioPlayer.retryTimer.stop() end
        if AudioPlayer.bufferTimer then AudioPlayer.bufferTimer.stop() end
    end
    AudioPlayer.abandonAudioFocus()
    AudioPlayer.cancelNotification()
    AudioPlayer.retryCount = 0
    AudioPlayer.isSilentRetry = false
    AudioPlayer.isManualStop = false
    
    AudioPlayer.sleepTargetTime = nil
    
    if AudioPlayer.mediaSession then
        pcall(function() AudioPlayer.mediaSession.setActive(false); AudioPlayer.mediaSession.release() end)
        AudioPlayer.mediaSession = nil
    end
    
    if AudioPlayer.dialog then AudioPlayer.dialog.dismiss() end
end

function AudioPlayer.next()
    AudioPlayer.retryCount = 0
    AudioPlayer.isSilentRetry = false
    AudioPlayer.isManualStop = false
    if AudioPlayer.currentIndex < #AudioPlayer.playlist then
        speak("التالي")
        AudioPlayer.play(AudioPlayer.currentIndex + 1)
    else
        speak("النهاية")
    end
end

function AudioPlayer.prev()
    AudioPlayer.retryCount = 0
    AudioPlayer.isSilentRetry = false
    AudioPlayer.isManualStop = false
    if AudioPlayer.currentIndex > 1 then
        speak("السابق")
        AudioPlayer.play(AudioPlayer.currentIndex - 1)
    else
        speak("البداية")
    end
end

function AudioPlayer.seekForward()
    if AudioPlayer.player and AudioPlayer.player.isPlaying() then
        local curr = AudioPlayer.player.getCurrentPosition()
        AudioPlayer.player.seekTo(curr + 10000)
        speak("تقديم")
    end
end

function AudioPlayer.seekRewind()
    if AudioPlayer.player and AudioPlayer.player.isPlaying() then
        local curr = AudioPlayer.player.getCurrentPosition()
        AudioPlayer.player.seekTo(curr - 10000)
        speak("تأخير")
    end
end

function AudioPlayer.savePosition(pos)
    local item = AudioPlayer.playlist[AudioPlayer.currentIndex]
    if item and item.id and (not AudioPlayer.isLive) then 
        local dur = 0
        if AudioPlayer.player then dur = AudioPlayer.player.getDuration() end
        
        if pos == 0 then 
            setData("resume_"..item.id, nil)
        elseif pos > 5000 then 
            setData("resume_"..item.id, tostring(pos))
            HistoryManager.updatePosition(item.id, pos, dur)
        end
    end
end

function AudioPlayer.getSavedPosition()
    local item = AudioPlayer.playlist[AudioPlayer.currentIndex]
    if item and item.id then
        local pos = getData("resume_"..item.id)
        return tonumber(pos) or 0
    end
    return 0
end

function AudioPlayer.startTimer()
    AudioPlayer.stopTimer()
    AudioPlayer.timer = Ticker()
    AudioPlayer.timer.Period = 1000
    local tickCount = 0
    AudioPlayer.timer.onTick = function()
        if AudioPlayer.sleepTargetTime and os.time() >= AudioPlayer.sleepTargetTime then
            AudioPlayer.sleepTargetTime = nil
            speak("انتهى وقت المؤقت، جاري إيقاف التشغيل...")
            AudioPlayer.stop()
            return
        end

        if AudioPlayer.player and AudioPlayer.player.isPlaying() and AudioPlayer.widgets.seek then
            local current = AudioPlayer.player.getCurrentPosition()
            local total = AudioPlayer.player.getDuration()
            if AudioPlayer.isLive or total <= 0 then total = 100 end 
            
            AudioPlayer.widgets.seek.setMax(total)
            AudioPlayer.widgets.seek.setProgress(current)
            
            local t_str = AudioPlayer.isLive and "Live Stream" or string.format("%02d:%02d", math.floor(total/60000), math.floor((total%60000)/1000))
            AudioPlayer.widgets.time.setText(string.format("%02d:%02d / %s", math.floor(current/60000), math.floor((current%60000)/1000), t_str))
            
            tickCount = tickCount + 1
            if tickCount >= 10 then
                tickCount = 0
                local item = AudioPlayer.getCurrentItem()
                if item and item.id and not AudioPlayer.isLive then
                    HistoryManager.updatePosition(item.id, current, total)
                    if current > 5000 then
                        setData("resume_"..item.id, tostring(current))
                    end
                end
            end
        end
    end
    AudioPlayer.timer.start()
end

function AudioPlayer.stopTimer()
    if AudioPlayer.timer then AudioPlayer.timer.stop(); AudioPlayer.timer = nil end
end

function AudioPlayer.updateUIState(isPlaying)
    if AudioPlayer.playlist[AudioPlayer.currentIndex] then
        pcall(AudioPlayer.sendNotification, AudioPlayer.playlist[AudioPlayer.currentIndex].name, isPlaying)
    end
    if AudioPlayer.widgets.playBtn then
        if isPlaying then
            AudioPlayer.widgets.playBtn.setText("⏸️")
            AudioPlayer.widgets.playBtn.setContentDescription("إيقاف مؤقت") 
        else
            AudioPlayer.widgets.playBtn.setText("▶️")
            AudioPlayer.widgets.playBtn.setContentDescription("تشغيل")
        end
    end
    
    pcall(function()
        if AudioPlayer.mediaSession then
             local state = isPlaying and PlaybackState.STATE_PLAYING or PlaybackState.STATE_PAUSED
             AudioPlayer.updatePlaybackState(state)
             AudioPlayer.updateMetadata()
        end
    end)
end

function AudioPlayer.updateFavoriteButton()
    if AudioPlayer.widgets.favBtn then
        local item = AudioPlayer.getCurrentItem()
        if item and FavoritesManager.isFavorite(item.id) then
            AudioPlayer.widgets.favBtn.setText("❤️ في المفضلة")
            AudioPlayer.widgets.favBtn.setContentDescription("إزالة من المفضلة")
        else
            AudioPlayer.widgets.favBtn.setText("🤍 إضافة للمفضلة")
            AudioPlayer.widgets.favBtn.setContentDescription("إضافة للمفضلة")
        end
    end
end

function AudioPlayer.toggleFavorite()
    local item = AudioPlayer.getCurrentItem()
    if item then
        FavoritesManager.toggle(item)
        AudioPlayer.updateFavoriteButton()
    end
end

function AudioPlayer.openSleepTimerMenu()
    local options = {
        "⏰ 5 دقائق",
        "⏰ 10 دقائق",
        "⏰ 15 دقيقة",
        "⏰ 30 دقيقة",
        "⏰ 60 دقيقة",
        "❌ إلغاء المؤقت"
    }
    local values = {5, 10, 15, 30, 60, 0}
    
    local dlg = LuaDialog(activity)
    dlg.setTitle("ضبط مؤقت النوم")
    dlg.setItems(options)
    dlg.setOnItemClickListener(function(l,v,p,i)
        local val = values[i]
        if val == 0 then
            AudioPlayer.sleepTargetTime = nil
            speak("تم إلغاء مؤقت النوم")
        else
            AudioPlayer.sleepTargetTime = os.time() + (val * 60)
            speak("تم ضبط المؤقت على " .. val .. " دقيقة")
        end
    end)
    dlg.setNegativeButton("إغلاق", nil)
    dlg.show()
end

function AudioPlayer.showPlaylistDialog()
    local names = {}
    for i, v in ipairs(AudioPlayer.playlist) do
        local prefix = (i == AudioPlayer.currentIndex) and "🔊 " or ""
        local favIcon = FavoritesManager.isFavorite(v.id) and " ❤️" or ""
        table.insert(names, prefix .. v.name .. favIcon)
    end
    local dlg = LuaDialog(activity)
    dlg.setTitle("قائمة التشغيل")
    dlg.setItems(names)
    dlg.setOnItemClickListener(function(l,v,p,i)
        AudioPlayer.play(i) 
        if AudioPlayer.dialog then AudioPlayer.dialog.dismiss() end
        AudioPlayer.showUI()
    end)
    dlg.setNegativeButton("🔙 رجوع", nil)
    dlg.show()
end

function AudioPlayer.showUI()
    if #AudioPlayer.playlist == 0 then speak("القائمة فارغة"); return end
    local currentItem = AudioPlayer.playlist[AudioPlayer.currentIndex]
    
    local layout = {
        LinearLayout, orientation="vertical", layout_width="fill", padding="32dp", 
        backgroundColor=COL_BG, gravity="center",
        
        { TextView, id="pTitle", text=currentItem.name, textSize="22sp", 
          textColor=COL_TEXT_PRI, gravity="center", Typeface=Typeface.DEFAULT_BOLD, 
          layout_marginBottom="40dp", layout_marginTop="20dp", focusable=true
        },
        
        { SeekBar, id="pSeek", layout_width="fill", layout_marginBottom="16dp", focusable=true },
        
        { TextView, id="pTime", text="00:00", textColor=COL_TEXT_SEC, textSize="14sp", 
          gravity="center", layout_marginBottom="40dp", focusable=true
        },
        
        { LinearLayout, orientation="horizontal", gravity="center", layout_width="fill", layout_marginBottom="40dp",
             { Button, id="btn_rew", text="⏪", textSize="20sp", textColor=COL_TEXT_PRI,
               layout_width="64dp", layout_height="64dp", layout_margin="8dp",
               contentDescription="تأخير 10 ثواني", 
               onClick=function() AudioPlayer.seekRewind() end 
             },
             { Button, id="btn_prev", text="⏮️", textSize="24sp", textColor=COL_TEXT_PRI,
               layout_width="64dp", layout_height="64dp", layout_margin="8dp",
               contentDescription="السابق", 
               onClick=function() AudioPlayer.prev() end 
             },
             { Button, id="pPlay", text="⏸️", textSize="32sp", textColor=COL_TEXT_PRI,
               layout_width="80dp", layout_height="80dp", layout_margin="12dp",
               contentDescription="إيقاف مؤقت", 
               onClick=function() AudioPlayer.togglePlay() end 
             },
             { Button, id="btn_next", text="⏭️", textSize="24sp", textColor=COL_TEXT_PRI,
               layout_width="64dp", layout_height="64dp", layout_margin="8dp",
               contentDescription="التالي", 
               onClick=function() AudioPlayer.next() end 
             },
             { Button, id="btn_fwd", text="⏩", textSize="20sp", textColor=COL_TEXT_PRI,
               layout_width="64dp", layout_height="64dp", layout_margin="8dp",
               contentDescription="تقديم 10 ثواني", 
               onClick=function() AudioPlayer.seekForward() end 
             }
        },
        
        { Button, id="pFav", text="Loading...", textColor=COL_TEXT_PRI, 
          layout_width="fill", layout_height="60dp", layout_marginBottom="12dp",
          contentDescription="المفضلة", 
          onClick=function() AudioPlayer.toggleFavorite() end 
        },
        
        { Button, id="btn_sleep", text="⏰ مؤقت النوم", textColor=COL_TEXT_PRI, 
          layout_width="fill", layout_height="60dp", layout_marginBottom="12dp",
          contentDescription="ضبط مؤقت النوم", 
          onClick=function() AudioPlayer.openSleepTimerMenu() end 
        },
        
        { Button, id="btn_vidmode", text="📺 تفتح كمشغل فيديو", textColor=COL_TEXT_PRI, 
          layout_width="fill", layout_height="60dp", layout_marginBottom="12dp",
          contentDescription="التحويل للفيديو", 
          onClick=function() 
                AudioPlayer.stop()
                PLAYER_MODE = "video"
                setData(PLAYER_MODE_KEY, "video")
                VideoPlayer.loadList(AudioPlayer.playlist, AudioPlayer.currentIndex)
          end 
        },
        
        { Button, id="btn_list", text="📑 القائمة", textColor=COL_TEXT_PRI, 
          layout_width="fill", layout_height="60dp", layout_marginBottom="12dp",
          contentDescription="عرض القائمة", 
          onClick=function() AudioPlayer.showPlaylistDialog() end 
        },
        
        { Button, id="btn_hide", text="✖️ إخفاء", textColor=COL_TEXT_PRI, 
          layout_width="fill", layout_height="60dp",
          contentDescription="إغلاق الواجهة", 
          onClick=function() AudioPlayer.dialog.dismiss() end 
        }
    }
    
    AudioPlayer.dialog = LuaDialog(activity)
    AudioPlayer.dialog.getWindow().setBackgroundDrawable(ColorDrawable(0))
    AudioPlayer.dialog.requestWindowFeature(Window.FEATURE_NO_TITLE)
    AudioPlayer.dialog.setView(loadlayout(layout))
    
    local btnColor = COL_SURFACE
    local btnPress = {COL_ACCENT_START, COL_ACCENT_END} 
    local radius = 32
    
    if btn_rew then btn_rew.setBackground(getClickableDrawable(btnColor, btnPress, radius)) end
    if btn_prev then btn_prev.setBackground(getClickableDrawable(btnColor, btnPress, radius)) end
    if btn_next then btn_next.setBackground(getClickableDrawable(btnColor, btnPress, radius)) end
    if btn_fwd then btn_fwd.setBackground(getClickableDrawable(btnColor, btnPress, radius)) end
    if pPlay then pPlay.setBackground(getClickableDrawable("#303030", btnPress, 40)) end
    
    if pFav then pFav.setBackground(getClickableDrawable(btnColor, btnPress, radius)) end
    if btn_sleep then btn_sleep.setBackground(getClickableDrawable(btnColor, btnPress, radius)) end
    if btn_vidmode then btn_vidmode.setBackground(getClickableDrawable(btnColor, btnPress, radius)) end
    if btn_list then btn_list.setBackground(getClickableDrawable(btnColor, btnPress, radius)) end
    if btn_hide then btn_hide.setBackground(getClickableDrawable(btnColor, btnPress, radius)) end

    AudioPlayer.widgets.title = pTitle
    AudioPlayer.widgets.seek = pSeek
    AudioPlayer.widgets.time = pTime
    AudioPlayer.widgets.playBtn = pPlay
    AudioPlayer.widgets.favBtn = pFav
    
    if pSeek then
        pSeek.setOnSeekBarChangeListener{
            onStopTrackingTouch=function(seekBar) if AudioPlayer.player then AudioPlayer.player.seekTo(seekBar.getProgress()) end end
        }
    end
    
    AudioPlayer.updateFavoriteButton()
    
    if AudioPlayer.player and AudioPlayer.player.isPlaying() then
        AudioPlayer.startTimer()
        AudioPlayer.updateUIState(true)
    else
        AudioPlayer.updateUIState(false)
    end

    AudioPlayer.dialog.show()
    local win = AudioPlayer.dialog.getWindow()
    win.setLayout(WindowManager.LayoutParams.MATCH_PARENT, WindowManager.LayoutParams.WRAP_CONTENT)
end

function AudioPlayer.loadList(list, startIndex)
    AudioPlayer.playlist = list
    AudioPlayer.play(startIndex)
    AudioPlayer.showUI()
end

function decodeRaw(str)
    local s, r = pcall(json.decode, str)
    if s then return r else return nil end
end

function preparePlaylist(data, type, seriesId, seriesName)
    local list = {}
    for k, v in pairs(data) do
        local name = v.name or v.stream_display_name or (v.title and "E"..v.episode_num.." "..v.title) or "Unknown"
        local id = v.stream_id or v.id 
        local ext = v.container_extension or "mp4"
        if type == "live" then ext = "m3u8" end
        
        local baseUrl = ""
        if type == "live" then baseUrl = "/live/"
        elseif type == "movie" then baseUrl = "/movie/"
        elseif type == "series" then baseUrl = "/series/" end
        
        local fullUrl = HOST .. baseUrl .. USER .. "/" .. PASS .. "/" .. id .. "." .. ext
        table.insert(list, {
            name=name, 
            url=fullUrl, 
            id=type.."_"..id, 
            type=type,
            episode_num = v.episode_num or nil,
            series_id = seriesId or v.series_id or nil,
            series_name = seriesName or v.series_name or nil
        })
    end
    return list
end

function playContent(playlist, startIndex)
    if PLAYER_MODE == "video" then
        VideoPlayer.loadList(playlist, startIndex)
    else
        AudioPlayer.loadList(playlist, startIndex)
    end
end

function showPlayModeSelector(playlist, startIndex)
    local options = {
        "🎧 تشغيل صوت فقط",
        "📺 تشغيل فيديو"
    }
    
    local dlg = LuaDialog(activity)
    dlg.setTitle("اختر وضع التشغيل")
    dlg.setItems(options)
    dlg.setOnItemClickListener(function(l,v,p,i)
        dlg.dismiss()
        if i == 1 then
            PLAYER_MODE = "audio"
            setData(PLAYER_MODE_KEY, "audio")
            AudioPlayer.loadList(playlist, startIndex)
        else
            PLAYER_MODE = "video"
            setData(PLAYER_MODE_KEY, "video")
            VideoPlayer.loadList(playlist, startIndex)
        end
    end)
    dlg.setNeutralButton("🏠 الرئيسية", function() main() end)
    dlg.setNegativeButton("🔙 رجوع", nil)
    dlg.show()
end

function showFavorites()
    local items = FavoritesManager.getAll()
    local series = FavoritesManager.getAllSeries()
    
    local totalCount = #items + #series
    
    if totalCount == 0 then
        speak("المفضلة فارغة")
        return
    end
    
    local names = {}
    local allItems = {}
    
    for i, fav in ipairs(series) do
        local icon = "📺 [مسلسل كامل] "
        table.insert(names, icon .. fav.name)
        table.insert(allItems, {type = "full_series", data = fav})
    end
    
    for i, fav in ipairs(items) do
        local typeIcon = ""
        if fav.type == "live" then typeIcon = "📡 [بث] "
        elseif fav.type == "movie" then typeIcon = "📺 [فيلم] "
        elseif fav.type == "series" then typeIcon = "🎞️ [حلقة] " end
        table.insert(names, typeIcon .. fav.name)
        table.insert(allItems, {type = "single", data = fav})
    end
    
    local dlg = LuaDialog(activity)
    dlg.setTitle("❤️ المفضلة (" .. totalCount .. ")")
    dlg.setItems(names)
    dlg.setOnItemClickListener(function(l,v,p,i)
        dlg.dismiss()
        local selected = allItems[i]
        if selected then
            if selected.type == "full_series" then
                getSeriesEpisodes(selected.data.series_id, selected.data.name)
            else
                showPlayModeSelector({selected.data}, 1)
            end
        end
    end)
    dlg.setPositiveButton("إدارة", function()
        showFavoritesManagement()
    end)
    dlg.setNeutralButton("🏠 الرئيسية", function() main() end)
    dlg.setNegativeButton("🔙 رجوع", nil)
    dlg.show()
end

function showFavoritesManagement()
    local options = {
        "🗑️ حذف عنصر فردي",
        "🗑️ حذف مسلسل كامل", 
        "💥 مسح جميع العناصر الفردية",
        "💥 مسح جميع المسلسلات",
        "✖️ مسح كل المفضلة"
    }
    
    local dlg = LuaDialog(activity)
    dlg.setTitle("إدارة المفضلة")
    dlg.setItems(options)
    dlg.setOnItemClickListener(function(l,v,p,i)
        if i == 1 then
            showDeleteFavoriteDialog()
        elseif i == 2 then
            showDeleteSeriesFavoriteDialog()
        elseif i == 3 then
            showConfirmDialog("مسح العناصر الفردية", "هل تريد مسح جميع العناصر الفردية؟", function()
                FavoritesManager.clear()
            end)
        elseif i == 4 then
            showConfirmDialog("مسح المسلسلات", "هل تريد مسح جميع المسلسلات؟", function()
                FavoritesManager.clearSeries()
            end)
        elseif i == 5 then
            showConfirmDialog("مسح الكل", "هل تريد مسح جميع المفضلة؟", function()
                FavoritesManager.clearAll()
            end)
        end
    end)
    dlg.setNeutralButton("🏠 الرئيسية", function() main() end)
    dlg.setNegativeButton("🔙 رجوع", nil)
    dlg.show()
end

function showConfirmDialog(title, message, onConfirm)
    local dlg = LuaDialog(activity)
    dlg.setTitle(title)
    dlg.setMessage(message)
    dlg.setButton("نعم", function()
        onConfirm()
    end)
    dlg.setButton2("لا", nil)
    dlg.show()
end

function showDeleteFavoriteDialog()
    local favorites = FavoritesManager.getAll()
    if #favorites == 0 then 
        speak("لا توجد عناصر فردية")
        return 
    end
    
    local names = {}
    for i, fav in ipairs(favorites) do
        table.insert(names, fav.name)
    end
    
    local dlg = LuaDialog(activity)
    dlg.setTitle("اختر عنصر للحذف")
    dlg.setItems(names)
    dlg.setOnItemClickListener(function(l,v,p,i)
        local item = favorites[i]
        if item then
            FavoritesManager.remove(item.id)
        end
    end)
    dlg.setNeutralButton("🏠 الرئيسية", function() main() end)
    dlg.setNegativeButton("🔙 رجوع", nil)
    dlg.show()
end

function showDeleteSeriesFavoriteDialog()
    local series = FavoritesManager.getAllSeries()
    if #series == 0 then 
        speak("لا توجد مسلسلات في المفضلة")
        return 
    end
    
    local names = {}
    for i, fav in ipairs(series) do
        table.insert(names, fav.name)
    end
    
    local dlg = LuaDialog(activity)
    dlg.setTitle("اختر مسلسل للحذف")
    dlg.setItems(names)
    dlg.setOnItemClickListener(function(l,v,p,i)
        local item = series[i]
        if item then
            FavoritesManager.removeSeries(item.series_id)
        end
    end)
    dlg.setNeutralButton("🏠 الرئيسية", function() main() end)
    dlg.setNegativeButton("🔙 رجوع", nil)
    dlg.show()
end

function showHistory()
    local history = HistoryManager.getAll()
    
    if #history == 0 then
        speak("السجل فارغ")
        return
    end
    
    local names = {}
    for i, hist in ipairs(history) do
        local typeIcon = ""
        if hist.type == "live" then typeIcon = "📡 "
        elseif hist.type == "movie" then typeIcon = "📺 "
        elseif hist.type == "series" then typeIcon = "🎞️ " end
        
        local timeAgo = getTimeAgo(hist.watchedAt)
        local posInfo = ""
        if hist.position and hist.position > 0 and hist.type ~= "live" then
            local mins = math.floor(hist.position / 60000)
            local secs = math.floor((hist.position % 60000) / 1000)
            posInfo = string.format(" [%02d:%02d]", mins, secs)
        end
        
        table.insert(names, typeIcon .. hist.name .. posInfo .. " - " .. timeAgo)
    end
    
    local dlg = LuaDialog(activity)
    dlg.setTitle("🕒 آخر ما شاهدته (" .. #history .. ")")
    dlg.setItems(names)
    dlg.setOnItemClickListener(function(l,v,p,i)
        dlg.dismiss()
        local item = history[i]
        if item then
            if item.type == "series" and item.series_id then
                resumeSeriesWithContext(item.series_id, item.id, item.series_name)
            else
                showPlayModeSelector({item}, 1)
            end
        end
    end)
    
    dlg.setButton("حذف عنصر", function()
        showDeleteHistoryDialog()
    end)
    dlg.setButton2("مسح الكل", function()
        showConfirmDialog("مسح السجل", "هل تريد مسح جميع السجل؟", function()
            HistoryManager.clear()
        end)
    end)
    dlg.setNeutralButton("🏠 الرئيسية", function() main() end)
    dlg.show()
end

function showDeleteHistoryDialog()
    local history = HistoryManager.getAll()
    if #history == 0 then return end
    
    local names = {}
    for i, hist in ipairs(history) do
        table.insert(names, hist.name)
    end
    
    local dlg = LuaDialog(activity)
    dlg.setTitle("اختر عنصر للحذف")
    dlg.setItems(names)
    dlg.setOnItemClickListener(function(l,v,p,i)
        local item = history[i]
        if item then
            HistoryManager.remove(item.id)
            showHistory()
        end
    end)
    dlg.setNeutralButton("🏠 الرئيسية", function() main() end)
    dlg.setNegativeButton("🔙 رجوع", nil)
    dlg.show()
end

function getTimeAgo(timestamp)
    if not timestamp then return "" end
    local diff = os.time() - timestamp
    
    if diff < 60 then
        return "الآن"
    elseif diff < 3600 then
        local mins = math.floor(diff / 60)
        return "منذ " .. mins .. " دقيقة"
    elseif diff < 86400 then
        local hours = math.floor(diff / 3600)
        return "منذ " .. hours .. " ساعة"
    else
        local days = math.floor(diff / 86400)
        return "منذ " .. days .. " يوم"
    end
end

function textContains(text, query)
    if not text or not query then return false end
    return string.find(string.lower(text), string.lower(query))
end

function startGlobalSearch()
    local layout = {
        LinearLayout, orientation="vertical", padding="20dp", backgroundColor=COL_BG,
        {TextView, text="🔍 بحث شامل في المحتوى", textSize="20sp", textColor=COL_ACCENT_START, gravity="center", layout_marginBottom="20dp", Typeface=Typeface.DEFAULT_BOLD},
        {EditText, id="search_input", hint="اسم القناة، الفيلم أو المسلسل", singleLine=true, textColor=COL_TEXT_PRI, hintTextColor=COL_TEXT_SEC},
    }
    
    local dlg = LuaDialog(activity)
    dlg.setView(loadlayout(layout))
    dlg.setButton("بدء البحث", function()
        local query = search_input.getText().toString()
        if #query < 2 then
            speak("يرجى كتابة حرفين على الأقل")
            return
        end
        performSearchRequests(query)
    end)
    dlg.setNeutralButton("🏠 الرئيسية", function() main() end)
    dlg.setNegativeButton("🔙 رجوع", nil)
    dlg.show()
end

function performSearchRequests(query)
    local allResults = {} 
    local progress = LuaDialog(activity)
    progress.setTitle("جاري البحث...")
    progress.setMessage("يتم البحث في القنوات المباشرة...")
    progress.show()

    Http.get(HOST.."/player_api.php?username="..USER.."&password="..PASS.."&action=get_live_streams", function(code, body)
        local data = decodeRaw(body)
        if data then
            for _, v in pairs(data) do
                if v.name and textContains(v.name, query) then
                    table.insert(allResults, {
                        type = "live",
                        name = "[📡 بث] "..v.name,
                        stream_id = v.stream_id,
                        container_extension = "m3u8"
                    })
                end
            end
        end
        
        pcall(function() progress.setMessage("يتم البحث في الأفلام...") end)
        Http.get(HOST.."/player_api.php?username="..USER.."&password="..PASS.."&action=get_vod_streams", function(code2, body2)
            local data2 = decodeRaw(body2)
            if data2 then
                for _, v in pairs(data2) do
                    if v.name and textContains(v.name, query) then
                        table.insert(allResults, {
                            type = "movie",
                            name = "[📺 فيلم] "..v.name,
                            stream_id = v.stream_id,
                            container_extension = v.container_extension or "mp4"
                        })
                    end
                end
            end

            pcall(function() progress.setMessage("يتم البحث في المسلسلات...") end)
            Http.get(HOST.."/player_api.php?username="..USER.."&password="..PASS.."&action=get_series", function(code3, body3)
                progress.dismiss()
                local data3 = decodeRaw(body3)
                if data3 then
                    for _, v in pairs(data3) do
                        if v.name and textContains(v.name, query) then
                            table.insert(allResults, {
                                type = "series",
                                name = "[🎞️ مسلسل] "..v.name,
                                series_id = v.series_id,
                                series_name = v.name
                            })
                        end
                    end
                end
                
                showSearchResults(allResults)
            end)
        end)
    end)
end

function showSearchResults(results)
    if #results == 0 then
        speak("لم يتم العثور على نتائج")
        return
    end

    local names = {}
    for _, v in ipairs(results) do
        local favIcon = ""
        if v.type == "series" and FavoritesManager.isSeriesFavorite(v.series_id) then
            favIcon = " ❤️"
        elseif v.type ~= "series" and v.stream_id and FavoritesManager.isFavorite(v.type.."_"..v.stream_id) then
            favIcon = " ❤️"
        end
        table.insert(names, v.name .. favIcon)
    end

    local dlg = LuaDialog(activity)
    dlg.setTitle("نتائج البحث ("..#results..")")
    dlg.setItems(names)
    dlg.setOnItemClickListener(function(l,v,p,i)
        dlg.dismiss()
        local item = results[i] 
        
        if item.type == "series" then
            getSeriesEpisodes(item.series_id, item.series_name)
        else
            local playListItem = {
                name = item.name,
                id = item.type.."_"..item.stream_id,
                url = "",
                type = item.type
            }
            
            local baseUrl = ""
            if item.type == "live" then baseUrl = "/live/"
            elseif item.type == "movie" then baseUrl = "/movie/" end
            
            playListItem.url = HOST .. baseUrl .. USER .. "/" .. PASS .. "/" .. item.stream_id .. "." .. item.container_extension
            
            showPlayModeSelector({playListItem}, 1)
        end
    end)
    dlg.setNeutralButton("🏠 الرئيسية", function() main() end)
    dlg.setNegativeButton("🔙 رجوع", nil)
    dlg.show()
end

function getLiveChannels(cat_id)
    speak("تحميل...")
    Http.get(HOST.."/player_api.php?username="..USER.."&password="..PASS.."&action=get_live_streams&category_id="..cat_id, function(code, body)
        local data = decodeRaw(body)
        if not data then return end
        local playlist = preparePlaylist(data, "live")
        local names = {}
        for _, v in ipairs(playlist) do 
            local favIcon = FavoritesManager.isFavorite(v.id) and " ❤️" or ""
            table.insert(names, v.name .. favIcon) 
        end
        local dlg = LuaDialog(activity)
        dlg.setTitle("القنوات")
        dlg.setItems(names)
        dlg.setOnItemClickListener(function(l,v,p,i) 
            dlg.dismiss()
            showPlayModeSelector(playlist, i) 
        end)
        dlg.setNeutralButton("🏠 الرئيسية", function() main() end)
        dlg.setNegativeButton("🔙 رجوع", nil)
        dlg.show()
    end)
end

function getLiveCategories()
    speak("تحميل الأقسام...")
    Http.get(HOST.."/player_api.php?username="..USER.."&password="..PASS.."&action=get_live_categories", function(c, b)
        local data = decodeRaw(b)
        if not data then return end
        local names, ids = {}, {}
        for k,v in pairs(data) do table.insert(names, v.category_name); table.insert(ids, v.category_id) end
        local dlg = LuaDialog(activity)
        dlg.setTitle("أقسام البث المباشر")
        dlg.setItems(names)
        dlg.setOnItemClickListener(function(l,v,p,i) getLiveChannels(ids[i] or ids[i+1]) end)
        dlg.setNeutralButton("🏠 الرئيسية", function() main() end)
        dlg.setNegativeButton("🔙 رجوع", nil)
        dlg.show()
    end)
end

function getMovies(cat_id)
    speak("تحميل...")
    Http.get(HOST.."/player_api.php?username="..USER.."&password="..PASS.."&action=get_vod_streams&category_id="..cat_id, function(code, body)
        local data = decodeRaw(body)
        if not data then return end
        local playlist = preparePlaylist(data, "movie")
        local names = {}
        for _, v in ipairs(playlist) do 
            local favIcon = FavoritesManager.isFavorite(v.id) and " ❤️" or ""
            table.insert(names, v.name .. favIcon) 
        end
        local dlg = LuaDialog(activity)
        dlg.setTitle("الأفلام")
        dlg.setItems(names)
        dlg.setOnItemClickListener(function(l,v,p,i) 
            dlg.dismiss()
            showPlayModeSelector(playlist, i) 
        end)
        dlg.setNeutralButton("🏠 الرئيسية", function() main() end)
        dlg.setNegativeButton("🔙 رجوع", nil)
        dlg.show()
    end)
end

function getMovieCategories()
    speak("تحميل الأقسام...")
    Http.get(HOST.."/player_api.php?username="..USER.."&password="..PASS.."&action=get_vod_categories", function(c, b)
        local data = decodeRaw(b)
        if not data then return end
        local names, ids = {}, {}
        for k,v in pairs(data) do table.insert(names, v.category_name); table.insert(ids, v.category_id) end
        local dlg = LuaDialog(activity)
        dlg.setTitle("أقسام الأفلام")
        dlg.setItems(names)
        dlg.setOnItemClickListener(function(l,v,p,i) getMovies(ids[i] or ids[i+1]) end)
        dlg.setNeutralButton("🏠 الرئيسية", function() main() end)
        dlg.setNegativeButton("🔙 رجوع", nil)
        dlg.show()
    end)
end

function showEpisodesList(episodes_data, seriesId, seriesName)
    local playlist = preparePlaylist(episodes_data, "series", seriesId, seriesName)
    local names = {}
    for _, v in ipairs(playlist) do 
        local favIcon = FavoritesManager.isFavorite(v.id) and " ❤️" or ""
        table.insert(names, v.name .. favIcon) 
    end
    
    local dlg = LuaDialog(activity)
    dlg.setTitle("الحلقات")
    dlg.setItems(names)
    dlg.setOnItemClickListener(function(l,v,p,i) 
        dlg.dismiss()
        showPlayModeSelector(playlist, i)
    end)
    dlg.setNeutralButton("🏠 الرئيسية", function() main() end)
    dlg.setNegativeButton("🔙 رجوع", nil)
    dlg.show()
end

function getSeriesEpisodes(series_id, series_name)
    speak("تحميل المواسم...")
    Http.get(HOST.."/player_api.php?username="..USER.."&password="..PASS.."&action=get_series_info&series_id="..series_id, function(code, body)
        local data = decodeRaw(body)
        if not data or not data["episodes"] then speak("فارغ"); return end
        
        local seasons = {}
        for k, v in pairs(data["episodes"]) do
            table.insert(seasons, tonumber(k))
        end
        table.sort(seasons)
        
        if #seasons == 0 then speak("لا توجد مواسم"); return end
        
        local totalEpisodes = 0
        for _, s in ipairs(seasons) do
            totalEpisodes = totalEpisodes + #data["episodes"][tostring(s)]
        end
        
        local names = {}
        
        table.insert(names, "▶️ تشغيل كل الحلقات (" .. totalEpisodes .. " حلقة)")
        
        for i, s in ipairs(seasons) do
            local count = #data["episodes"][tostring(s)]
            table.insert(names, "📂 الموسم " .. s .. " (" .. count .. " حلقة)")
        end
        
        local isFav = FavoritesManager.isSeriesFavorite(series_id)
        local favBtnText = isFav and "👎 إزالة من المفضلة" or "❤️ إضافة المسلسل للمفضلة"
        
        local dlg = LuaDialog(activity)
        
        local titleIcon = isFav and " ❤️" or ""
        dlg.setTitle("🎞️ " .. (series_name or "المسلسل") .. titleIcon)
        
        dlg.setItems(names)
        dlg.setOnItemClickListener(function(l,v,p,i)
            if i == 1 then
                playAllSeriesEpisodes(data["episodes"], seasons, series_id, series_name)
            else
                local idx = i - 1
                local selectedSeasonNum = seasons[idx]
                if selectedSeasonNum then
                    local selectedEpisodes = data["episodes"][tostring(selectedSeasonNum)]
                    showEpisodesList(selectedEpisodes, series_id, series_name)
                else
                    speak("خطأ في تحديد الموسم")
                end
            end
        end)
        
        dlg.setButton(favBtnText, function()
            FavoritesManager.toggleSeries(series_id, series_name or "مسلسل", nil)
            getSeriesEpisodes(series_id, series_name)
        end)
        
        dlg.setNeutralButton("🏠 الرئيسية", function() main() end)
        dlg.setButton2("إغلاق", nil)
        dlg.show()
    end)
end

function playAllSeriesEpisodes(episodesData, seasons, seriesId, seriesName)
    local allEpisodes = {}
    
    for _, seasonNum in ipairs(seasons) do
        local seasonEpisodes = episodesData[tostring(seasonNum)]
        if seasonEpisodes then
            for _, ep in pairs(seasonEpisodes) do
                local name = "S" .. seasonNum .. " E" .. (ep.episode_num or "?") .. " - " .. (ep.title or "بدون عنوان")
                local id = ep.id or ep.stream_id
                local ext = ep.container_extension or "mp4"
                local fullUrl = HOST .. "/series/" .. USER .. "/" .. PASS .. "/" .. id .. "." .. ext
                
                table.insert(allEpisodes, {
                    name = name,
                    url = fullUrl,
                    id = "series_" .. id,
                    type = "series",
                    seasonNum = seasonNum,
                    episodeNum = ep.episode_num or 0,
                    series_id = seriesId,
                    series_name = seriesName
                })
            end
        end
    end
    
    table.sort(allEpisodes, function(a, b)
        if a.seasonNum == b.seasonNum then
            return (a.episodeNum or 0) < (b.episodeNum or 0)
        end
        return a.seasonNum < b.seasonNum
    end)
    
    if #allEpisodes > 0 then
        speak("جاري تشغيل " .. #allEpisodes .. " حلقة")
        showPlayModeSelector(allEpisodes, 1)
    else
        speak("لا توجد حلقات")
    end
end

function getSeriesList(cat_id)
    speak("تحميل...");
    Http.get(HOST.."/player_api.php?username="..USER.."&password="..PASS.."&action=get_series&category_id="..cat_id, function(code, body)
        local data = decodeRaw(body)
        if not data then return end
        local names, ids, seriesNames = {}, {}, {}
        for k, v in pairs(data) do
            if v.series_id then
                local sName = v.name or v.series_name or "مسلسل"
                local favIcon = FavoritesManager.isSeriesFavorite(v.series_id) and " ❤️" or ""
                table.insert(names, sName .. favIcon)
                table.insert(ids, v.series_id)
                table.insert(seriesNames, sName)
            end
        end
        local dlg = LuaDialog(activity)
        dlg.setTitle("المسلسلات")
        dlg.setItems(names)
        dlg.setOnItemClickListener(function(l,v,p,i) 
            local idx = i
            if idx == 0 then idx = 1 end
            getSeriesEpisodes(ids[idx] or ids[1], seriesNames[idx] or seriesNames[1]) 
        end)
        dlg.setNeutralButton("🏠 الرئيسية", function() main() end)
        dlg.setNegativeButton("🔙 رجوع", nil)
        dlg.show()
    end)
end

function getSeriesCategories()
    speak("تحميل الأقسام...")
    Http.get(HOST.."/player_api.php?username="..USER.."&password="..PASS.."&action=get_series_categories", function(c, b)
        local data = decodeRaw(b)
        if not data then return end
        local names, ids = {}, {}
        for k,v in pairs(data) do table.insert(names, v.category_name); table.insert(ids, v.category_id) end
        local dlg = LuaDialog(activity)
        dlg.setTitle("أقسام المسلسلات")
        dlg.setItems(names)
        dlg.setOnItemClickListener(function(l,v,p,i) getSeriesList(ids[i] or ids[i+1]) end)
        dlg.setNeutralButton("🏠 الرئيسية", function() main() end)
        dlg.setNegativeButton("🔙 رجوع", nil)
        dlg.show()
    end)
end

function showFavoriteSeriesOnly()
    local series = FavoritesManager.getAllSeries()
    
    if #series == 0 then
        speak("لا توجد مسلسلات في المفضلة")
        return
    end
    
    local names = {}
    for i, fav in ipairs(series) do
        table.insert(names, "🎞️ " .. fav.name)
    end
    
    local dlg = LuaDialog(activity)
    dlg.setTitle("🎞️ مسلسلاتي المفضلة (" .. #series .. ")")
    dlg.setItems(names)
    dlg.setOnItemClickListener(function(l,v,p,i)
        local item = series[i]
        if item then
            getSeriesEpisodes(item.series_id, item.name)
        end
    end)
    dlg.setButton("حذف", function()
        showDeleteSeriesFavoriteDialog()
    end)
    dlg.setNeutralButton("🏠 الرئيسية", function() main() end)
    dlg.setNegativeButton("🔙 رجوع", nil)
    dlg.show()
end

function showPlayerSettings()
    local currentModeText = PLAYER_MODE == "video" and "📺 فيديو" or "🎧 صوت"
    
    local options = {
        "🎧 تعيين الوضع الافتراضي: صوت",
        "📺 تعيين الوضع الافتراضي: فيديو",
        "ℹ️ الوضع الحالي: " .. currentModeText
    }
    
    local dlg = LuaDialog(activity)
    dlg.setTitle("⚙️ إعدادات المشغل")
    dlg.setItems(options)
    dlg.setOnItemClickListener(function(l,v,p,i)
        if i == 1 then
            PLAYER_MODE = "audio"
            setData(PLAYER_MODE_KEY, "audio")
            speak("تم تعيين الوضع الافتراضي: صوت")
        elseif i == 2 then
            PLAYER_MODE = "video"
            setData(PLAYER_MODE_KEY, "video")
            speak("تم تعيين الوضع الافتراضي: فيديو")
        end
    end)
    dlg.setNeutralButton("🏠 الرئيسية", function() main() end)
    dlg.setNegativeButton("🔙 رجوع", nil)
    dlg.show()
end

function resumeSeriesWithContext(seriesId, episodeId, seriesName)
    speak("جاري استعادة سياق المسلسل...")
    Http.get(HOST.."/player_api.php?username="..USER.."&password="..PASS.."&action=get_series_info&series_id="..seriesId, function(code, body)
        local data = decodeRaw(body)
        if not data or not data["episodes"] then 
            speak("فشل استعادة القائمة")
            return 
        end
        
        local seasons = {}
        for k, v in pairs(data["episodes"]) do table.insert(seasons, tonumber(k)) end
        table.sort(seasons)
        
        local allEpisodes = {}
        local startIndex = 1
        
        for _, seasonNum in ipairs(seasons) do
            local seasonEpisodes = data["episodes"][tostring(seasonNum)]
            if seasonEpisodes then
                for _, ep in pairs(seasonEpisodes) do
                    local name = "S" .. seasonNum .. " E" .. (ep.episode_num or "?") .. " - " .. (ep.title or "بدون عنوان")
                    local id = ep.id or ep.stream_id
                    local fullId = "series_" .. id
                    
                    table.insert(allEpisodes, {
                        name = name,
                        url = HOST .. "/series/" .. USER .. "/" .. PASS .. "/" .. id .. "." .. (ep.container_extension or "mp4"),
                        id = fullId,
                        type = "series",
                        seasonNum = seasonNum,
                        episodeNum = ep.episode_num or 0,
                        series_id = seriesId,
                        series_name = seriesName
                    })
                end
            end
        end
        
        table.sort(allEpisodes, function(a, b)
            if a.seasonNum == b.seasonNum then
                return (a.episodeNum or 0) < (b.episodeNum or 0)
            end
            return a.seasonNum < b.seasonNum
        end)
        
        for i, ep in ipairs(allEpisodes) do
            if ep.id == episodeId then
                startIndex = i
                break
            end
        end

        showPlayModeSelector(allEpisodes, startIndex)
    end)
end

AccountInfo = nil

function fetchAccountInfo(callback)
    if not HOST or HOST == "" then return end
    local url = HOST .. "/player_api.php?username=" .. USER .. "&password=" .. PASS
    Http.get(url, function(code, body)
        if code == 200 then
            local data = decodeRaw(body)
            if data and data.user_info then
                AccountInfo = data.user_info
                if callback then callback() end
            end
        end
    end)
end

function getExpiryText(exp_date)
    if not exp_date or exp_date == "null" or exp_date == "" then
        return "غير محدود"
    end
    local ts = tonumber(exp_date)
    if not ts then return "غير معروف" end

    local dateStr = os.date("%Y-%m-%d", ts)
    local diff = ts - os.time()
    local days = math.floor(diff / 86400)

    if days < 0 then
        return "منتهي (" .. dateStr .. ")"
    elseif days == 0 then
        return "ينتهي اليوم (" .. dateStr .. ")"
    else
        return dateStr .. " (باقي " .. days .. " يوم)"
    end
end

function main()
    local favCount = #FavoritesManager.getAll() + #FavoritesManager.getAllSeries()
    local histCount = #HistoryManager.getAll()
    local modeIcon = PLAYER_MODE == "video" and "📺" or "🎧"
    
    local historyItems = HistoryManager.getAll()
    local continueWatchingList = {}
    for _, item in ipairs(historyItems) do
        if item.type ~= "live" and item.position and item.position > 5000 then
            table.insert(continueWatchingList, item)
        end
        if #continueWatchingList >= 3 then break end
    end

    local layout = {
        ScrollView, layout_width="fill", layout_height="fill", backgroundColor=COL_BG,
        {
            LinearLayout, orientation="vertical", layout_width="fill", padding="24dp",
            
            -- Header
            {
                LinearLayout, orientation="horizontal", layout_width="fill", gravity="center_vertical", layout_marginBottom="32dp",
                {
                    LinearLayout, orientation="vertical", layout_weight="1",
                    { TextView, text="مرحباً بعودتك", textSize="14sp", textColor=COL_TEXT_SEC, importantForAccessibility=2 },
                    { TextView, text=USER or "GUEST", textSize="24sp", Typeface=Typeface.DEFAULT_BOLD, textColor=COL_TEXT_PRI, importantForAccessibility=2 },
                },
                {
                    TextView, text="🔍", textSize="28sp", padding="12dp", 
                    contentDescription="بحث شامل", focusable=true, clickable=true,
                    onClick=function() startGlobalSearch() end
                },
                {
                    TextView, text="⚙️", textSize="28sp", padding="12dp", 
                    contentDescription="الإعدادات", focusable=true, clickable=true,
                    onClick=function() showPlayerSettings() end
                }
            },

            -- Subscription Card
            (AccountInfo and {
                LinearLayout, orientation="vertical", layout_width="fill", padding="16dp",
                layout_marginBottom="24dp", id="subs_card",
                focusable=true,
                contentDescription="معلومات الاشتراك: الحالة " .. (AccountInfo.status or "Active") ..
                                   "، الانتهاء في " .. getExpiryText(AccountInfo.exp_date) ..
                                   "، الأجهزة المتصلة " .. (AccountInfo.active_cons or "0") .. " من أصل " .. (AccountInfo.max_connections or "0"),
                {
                    LinearLayout, orientation="horizontal", gravity="center_vertical", layout_marginBottom="8dp", importantForAccessibility=2,
                    { TextView, text="💳", textSize="20sp", layout_marginRight="8dp", importantForAccessibility=2 },
                    { TextView, text="معلومات الاشتراك", textSize="16sp", Typeface=Typeface.DEFAULT_BOLD, textColor=COL_ACCENT_START, importantForAccessibility=2 },
                },
                {
                    LinearLayout, orientation="horizontal", layout_width="fill", importantForAccessibility=2,
                    {
                        LinearLayout, orientation="vertical", layout_weight="1", importantForAccessibility=2,
                        { TextView, text="الحالة: " .. (AccountInfo.status or "Active"), textColor=COL_TEXT_PRI, textSize="13sp", importantForAccessibility=2 },
                        { TextView, text="الانتهاء: " .. getExpiryText(AccountInfo.exp_date), textColor=COL_TEXT_PRI, textSize="13sp", importantForAccessibility=2 },
                    },
                    {
                        LinearLayout, orientation="vertical", gravity="right", importantForAccessibility=2,
                        { TextView, text="الأجهزة", textColor=COL_TEXT_SEC, textSize="11sp", importantForAccessibility=2 },
                        { TextView, text=(AccountInfo.active_cons or "0") .. " / " .. (AccountInfo.max_connections or "0"), textColor=COL_TEXT_PRI, textSize="15sp", Typeface=Typeface.DEFAULT_BOLD, importantForAccessibility=2 },
                    }
                }
            } or { View, layout_width="0", layout_height="0" }),

            -- Hero & Categories
            {
                LinearLayout, orientation="vertical", layout_width="fill", layout_marginBottom="32dp",
                
                -- Live TV Card (Hero)
                {
                    LinearLayout, layout_width="fill", layout_height="160dp", layout_marginBottom="16dp",
                    id="btn_live", gravity="center",
                    focusable=true, clickable=true, contentDescription="قسم البث المباشر والقنوات التلفزيونية",
                    onClick=function() getLiveCategories() end,
                    {
                        LinearLayout, orientation="horizontal", gravity="center", importantForAccessibility=2,
                        { TextView, text="📡", textSize="48sp", layout_marginRight="20dp", importantForAccessibility=2 },
                        {
                            LinearLayout, orientation="vertical", importantForAccessibility=2,
                            { TextView, text="LIVE TV", textSize="28sp", Typeface=Typeface.DEFAULT_BOLD, textColor=COL_TEXT_PRI, importantForAccessibility=2 },
                            { TextView, text="قنوات مباشرة", textSize="16sp", textColor=COL_TEXT_SEC, importantForAccessibility=2 },
                        }
                    }
                },
                
                -- Grid Row: Movies | Series
                {
                    LinearLayout, orientation="horizontal", layout_width="fill", layout_height="160dp",
                    {
                        LinearLayout, layout_width="0dp", layout_weight="1", layout_height="fill", layout_marginRight="8dp",
                        id="btn_vod", gravity="center", orientation="vertical",
                        focusable=true, clickable=true, contentDescription="قسم الأفلام ومكتبة الفيديو",
                        onClick=function() getMovieCategories() end,
                        { TextView, text="📺", textSize="44sp", layout_marginBottom="8dp", importantForAccessibility=2 },
                        { TextView, text="MOVIES", textSize="20sp", Typeface=Typeface.DEFAULT_BOLD, textColor=COL_TEXT_PRI, importantForAccessibility=2 },
                        { TextView, text="أفلام", textSize="14sp", textColor=COL_TEXT_SEC, importantForAccessibility=2 },
                    },
                    {
                        LinearLayout, layout_width="0dp", layout_weight="1", layout_height="fill", layout_marginLeft="8dp",
                        id="btn_series", gravity="center", orientation="vertical",
                        focusable=true, clickable=true, contentDescription="قسم المسلسلات والحلقات",
                        onClick=function() getSeriesCategories() end,
                        { TextView, text="🎞️", textSize="44sp", layout_marginBottom="8dp", importantForAccessibility=2 },
                        { TextView, text="SERIES", textSize="20sp", Typeface=Typeface.DEFAULT_BOLD, textColor=COL_TEXT_PRI, importantForAccessibility=2 },
                        { TextView, text="مسلسلات", textSize="14sp", textColor=COL_TEXT_SEC, importantForAccessibility=2 },
                    }
                }
            },

            -- Continue Watching Section
            { 
                TextView, text="استكمال المشاهدة", textSize="22sp", Typeface=Typeface.DEFAULT_BOLD, textColor=COL_TEXT_PRI, 
                layout_marginBottom="16dp", visibility = (#continueWatchingList > 0 and View.VISIBLE or View.GONE)
            },
            {
                LinearLayout, orientation="vertical", layout_width="fill",
                id = "continue_shelf", layout_marginBottom="32dp",
                visibility = (#continueWatchingList > 0 and View.VISIBLE or View.GONE)
            },

            -- Library Section
            { TextView, text="المكتبة والأدوات", textSize="22sp", Typeface=Typeface.DEFAULT_BOLD, textColor=COL_TEXT_PRI, layout_marginBottom="16dp" },
            {
                LinearLayout, orientation="horizontal", layout_width="fill", layout_height="100dp", layout_marginBottom="24dp",
                {
                    LinearLayout, layout_width="0dp", layout_weight="1", layout_height="fill", layout_marginRight="8dp",
                    id="btn_fav", gravity="center", orientation="vertical",
                    focusable=true, clickable=true, contentDescription="عرض قائمة المفضلة",
                    onClick=function() showFavorites() end,
                    { TextView, text="❤️", textSize="26sp", layout_marginBottom="4dp", importantForAccessibility=2 },
                    { TextView, text="المفضلة", textSize="14sp", textColor=COL_TEXT_PRI, importantForAccessibility=2 }
                },
                {
                    LinearLayout, layout_width="0dp", layout_weight="1", layout_height="fill", layout_marginLeft="4dp", layout_marginRight="4dp",
                    id="btn_hist", gravity="center", orientation="vertical",
                    focusable=true, clickable=true, contentDescription="عرض سجل المشاهدة",
                    onClick=function() showHistory() end,
                    { TextView, text="🕒", textSize="26sp", layout_marginBottom="4dp", importantForAccessibility=2 },
                    { TextView, text="السجل", textSize="14sp", textColor=COL_TEXT_PRI, importantForAccessibility=2 }
                },
                {
                    LinearLayout, layout_width="0dp", layout_weight="1", layout_height="fill", layout_marginLeft="8dp",
                    id="btn_myseries", gravity="center", orientation="vertical",
                    focusable=true, clickable=true, contentDescription="عرض مسلسلاتي المفضلة",
                    onClick=function() showFavoriteSeriesOnly() end,
                    { TextView, text="🎞️", textSize="26sp", layout_marginBottom="4dp", importantForAccessibility=2 },
                    { TextView, text="مسلسلاتي", textSize="14sp", textColor=COL_TEXT_PRI, importantForAccessibility=2 }
                }
            },

            {
                Button, text="تسجيل خروج", layout_width="fill", layout_marginTop="32dp",
                focusable=true, contentDescription="تسجيل الخروج من الحساب",
                backgroundColor=COL_ERROR, textColor=COL_TEXT_PRI, onClick=function() 
                    AudioPlayer.stop()
                    VideoPlayer.stop()
                    setData("xt_host", nil)
                    setData("xt_user", nil)
                    setData("xt_pass", nil)
                    HOST, USER, PASS = nil, nil, nil
                    AccountInfo = nil
                    showLogin()
                end
            },
            { TextView, text="تم التطوير بواسطة احمد حنفي (الفرعون الصغير)", textSize="12sp", textColor=COL_TEXT_SEC, gravity="center", layout_marginTop="24dp", focusable=true }
        }
    }
    
    local view = loadlayout(layout)

    -- Applying Premium Visuals
    local mainCardPress = {COL_ACCENT_START, COL_ACCENT_END}
    
    if btn_live then btn_live.setBackground(getClickableDrawable(COL_SURFACE, mainCardPress, 32)) end
    
    if btn_vod then btn_vod.setBackground(getClickableDrawable(COL_SURFACE, mainCardPress, 32)) end
    
    if btn_series then btn_series.setBackground(getClickableDrawable(COL_SURFACE, mainCardPress, 32)) end

    if btn_fav then btn_fav.setBackground(getClickableDrawable(COL_SURFACE, COL_SURFACE_PRESS, 24)) end
    if btn_hist then btn_hist.setBackground(getClickableDrawable(COL_SURFACE, COL_SURFACE_PRESS, 24)) end
    if btn_myseries then btn_myseries.setBackground(getClickableDrawable(COL_SURFACE, COL_SURFACE_PRESS, 24)) end

    if subs_card then
        local gd = GradientDrawable()
        gd.setColor(Color.parseColor(COL_SURFACE))
        gd.setCornerRadius(24)
        gd.setStroke(2, Color.parseColor(COL_ACCENT_START))
        subs_card.setBackground(gd)
    end

    for _, item in ipairs(continueWatchingList) do
        local mins = math.floor(item.position / 60000)
        local secs = math.floor((item.position % 60000) / 1000)
        local time_str = string.format("%02d:%02d", mins, secs)
        
        local display_title = item.name
        if (not display_title or display_title == "") and item.type == "series" then
             display_title = (item.series_name or "مسلسل") .. " : E" .. (item.episode_num or "?")
        end
        
        -- Calculate progress for visual bar
        local pct = 0
        if item.duration and item.duration > 0 then
            pct = item.position / item.duration
        else
            pct = 0.5 -- Default if unknown
        end
        
        local a11y_time = string.format("%d دقيقة و %d ثانية", mins, secs)
        
        local itemLayout = {
            LinearLayout, orientation="vertical", layout_width="fill", 
            backgroundColor=COL_SURFACE, 
            focusable=true, clickable=true,
            contentDescription="استكمال مشاهدة " .. display_title .. "، توقف عند " .. a11y_time,
            onClick = function() 
               if item.type == "series" and item.series_id then
                   resumeSeriesWithContext(item.series_id, item.id, item.series_name)
               else
                   showPlayModeSelector({item}, 1)
               end
            end,
            
            {
                LinearLayout, orientation="horizontal", layout_width="fill", padding="16dp",
                gravity="center_vertical",
                
                {
                    LinearLayout, orientation="horizontal", layout_width="0dp", layout_weight="1",
                    gravity="center_vertical", importantForAccessibility=2,
                    
                    { TextView, text="▶️", textSize="20sp", paddingRight="16dp", textColor=COL_ACCENT_START, importantForAccessibility=2 },
                    {
                        LinearLayout, orientation="vertical", layout_weight="1", importantForAccessibility=2,
                        { TextView, text=display_title, textColor=COL_TEXT_PRI, textSize="16sp", singleLine=true, Typeface=Typeface.DEFAULT_BOLD, importantForAccessibility=2 },
                        { TextView, text="توقف عند: " .. time_str, textColor=COL_TEXT_SEC, textSize="12sp", importantForAccessibility=2 }
                    }
                },
                
                {
                     TextView, text="✖️", padding="8dp", textColor=COL_TEXT_SEC, textSize="18sp",
                     focusable=true, clickable=true,
                     contentDescription="حذف " .. display_title .. " من السجل",
                     onClick = function() 
                        HistoryManager.remove(item.id)
                        main() 
                     end
                }
            },
            
            -- Progress Bar Line
            {
                LinearLayout, layout_width="fill", layout_height="3dp", orientation="horizontal",
                { View, layout_height="fill", layout_weight=tostring(pct), backgroundColor=COL_ACCENT_START },
                { View, layout_height="fill", layout_weight=tostring(1-pct), backgroundColor="#00000000" }
            }
        }
        local itemView = loadlayout(itemLayout)
        -- Custom background wrapper for item
        local gd = GradientDrawable()
        gd.setColor(Color.parseColor(COL_SURFACE))
        gd.setCornerRadius(16)
        itemView.setBackground(gd)
        
        continue_shelf.addView(itemView)
        continue_shelf.addView(loadlayout({View, layout_width="fill", layout_height="12dp"}))
    end
    
    activity.setContentView(view)
end

function showLogin()
    local layout = {
        LinearLayout, orientation="vertical", padding="32dp", backgroundColor=COL_BG,
        gravity="center", layout_width="fill", layout_height="fill",
        { TextView, text="XTREAM PLAYER", textSize="32sp", Typeface=Typeface.DEFAULT_BOLD, textColor=COL_TEXT_PRI, layout_marginBottom="48dp" },
        
        { EditText, id="e_h", hint="Host URL (http://...)", text=HOST or "", singleLine=true, textColor=COL_TEXT_PRI, hintTextColor=COL_TEXT_SEC, layout_width="fill", layout_marginBottom="16dp", focusable=true },
        { EditText, id="e_u", hint="Username", text=USER or "", singleLine=true, textColor=COL_TEXT_PRI, hintTextColor=COL_TEXT_SEC, layout_width="fill", layout_marginBottom="16dp", focusable=true },
        { EditText, id="e_p", hint="Password", text=PASS or "", singleLine=true, textColor=COL_TEXT_PRI, hintTextColor=COL_TEXT_SEC, password=true, layout_width="fill", layout_marginBottom="32dp", focusable=true },
        
        { Button, id="btn_login", text="تسجيل الدخول", layout_width="fill", textColor=COL_TEXT_PRI, backgroundColor=COL_ACCENT_START, focusable=true, contentDescription="زر تسجيل الدخول" },
        { TextView, text="تم التطوير بواسطة احمد حنفي (الفرعون الصغير)", textSize="12sp", textColor=COL_TEXT_SEC, gravity="center", layout_marginTop="24dp", focusable=true }
    }
    
    local view = loadlayout(layout)
    activity.setContentView(view)
    
    if btn_login then btn_login.setBackground(getRoundedDrawable(COL_ACCENT_START, 24)) end
    
    btn_login.setOnClickListener(View.OnClickListener{
        onClick=function()
            local h, u, p = e_h.getText().toString(), e_u.getText().toString(), e_p.getText().toString()
            if h == "" or u == "" or p == "" then
                speak("يرجى إكمال بيانات الدخول")
                return
            end
            if not h:find("http") then h = "http://"..h end
            setData("xt_host", h); HOST = h
            setData("xt_user", u); USER = u
            setData("xt_pass", p); PASS = p
            speak("تم تسجيل الدخول بنجاح")
            main()
            fetchAccountInfo(function()
                main()
            end)
        end
    })
end

if HOST and USER and HOST ~= "" then 
    main()
    fetchAccountInfo(function()
        main()
    end)
else 
    showLogin() 
end