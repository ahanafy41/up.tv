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
import "com.androlua.Http"
import "android.content.Context"
import "android.graphics.BitmapFactory"
import "android.graphics.Color"
import "com.androlua.LuaBroadcastReceiver"
import "java.util.HashMap"
import "android.view.WindowManager"
import "android.content.pm.ActivityInfo"
import "android.view.SurfaceView"
import "android.view.SurfaceHolder"
import "android.widget.VideoView"
import "android.media.MediaPlayer"
import "android.widget.MediaController"

-- محاولة استيراد ExoPlayer
local hasExoPlayer = false
local ExoPlayer, DefaultDataSourceFactory, ProgressiveMediaSource, HlsMediaSource, MediaItem
pcall(function()
    import "com.google.android.exoplayer2.SimpleExoPlayer"
    import "com.google.android.exoplayer2.ExoPlayer"
    import "com.google.android.exoplayer2.MediaItem"
    import "com.google.android.exoplayer2.source.hls.HlsMediaSource"
    import "com.google.android.exoplayer2.source.ProgressiveMediaSource"
    import "com.google.android.exoplayer2.upstream.DefaultDataSourceFactory"
    import "com.google.android.exoplayer2.upstream.DefaultHttpDataSource"
    import "com.google.android.exoplayer2.ui.PlayerView"
    import "com.google.android.exoplayer2.Player"
    import "com.google.android.exoplayer2.C"
    hasExoPlayer = true
end)

local json = require "cjson"

-- ==================================================
-- إعدادات السيرفر
-- ==================================================
local HOST = service.getSharedData("xt_host")
local USER = service.getSharedData("xt_user")
local PASS = service.getSharedData("xt_pass")

-- ==================================================
-- ثوابت المفاتيح للتخزين
-- ==================================================
local FAVORITES_KEY = "xt_favorites_list"
local HISTORY_KEY = "xt_history_list"
local SERIES_FAVORITES_KEY = "xt_series_favorites"
local PLAYER_MODE_KEY = "xt_player_mode"
local MAX_HISTORY_ITEMS = 50

-- ==================================================
-- وضع التشغيل الافتراضي (audio أو video)
-- ==================================================
local PLAYER_MODE = service.getSharedData(PLAYER_MODE_KEY) or "audio"

-- ==================================================
-- نظام استقبال الأوامر (سماعات الرأس والبلوتوث)
-- ==================================================
local ACTION_PREV = "com.xtream.action.PREV"
local ACTION_PLAY_PAUSE = "com.xtream.action.PLAY_PAUSE"
local ACTION_NEXT = "com.xtream.action.NEXT"
local ACTION_CLOSE = "com.xtream.action.CLOSE"
local ACTION_MEDIA_BUTTON = "android.intent.action.MEDIA_BUTTON"

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
    elseif action == ACTION_MEDIA_BUTTON then
        local event = intent.getParcelableExtra(Intent.EXTRA_KEY_EVENT)
        if event and event.getAction() == 0 then
            local code = event.getKeyCode()
            if code == 85 or code == 126 or code == 127 then
                if PLAYER_MODE == "video" then VideoPlayer.togglePlay() else AudioPlayer.togglePlay() end
            elseif code == 87 then
                if PLAYER_MODE == "video" then VideoPlayer.next() else AudioPlayer.next() end
            elseif code == 88 then
                if PLAYER_MODE == "video" then VideoPlayer.prev() else AudioPlayer.prev() end
            end
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
filter.addAction(ACTION_MEDIA_BUTTON)
filter.setPriority(2147483647)

pcall(function()
    if Build.VERSION.SDK_INT >= 33 then service.registerReceiver(GlobalPlayerReceiver, filter, 2) else service.registerReceiver(GlobalPlayerReceiver, filter) end
end)

-- ==================================================
-- مدير المفضلة (Favorites Manager)
-- ==================================================
FavoritesManager = {
    favorites = {},
    seriesFavorites = {}
}

function FavoritesManager.load()
    local saved = service.getSharedData(FAVORITES_KEY)
    if saved and saved ~= "" then
        local success, data = pcall(json.decode, saved)
        if success and data then
            FavoritesManager.favorites = data
        end
    end
    
    local savedSeries = service.getSharedData(SERIES_FAVORITES_KEY)
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
        service.setSharedData(FAVORITES_KEY, encoded)
    end
end

function FavoritesManager.saveSeries()
    local success, encoded = pcall(json.encode, FavoritesManager.seriesFavorites)
    if success then
        service.setSharedData(SERIES_FAVORITES_KEY, encoded)
    end
end

function FavoritesManager.add(item)
    if not item or not item.id then return false end
    
    for i, fav in ipairs(FavoritesManager.favorites) do
        if fav.id == item.id then
            service.speak("موجود بالفعل في المفضلة")
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
    service.speak("تمت الإضافة للمفضلة")
    return true
end

function FavoritesManager.remove(itemId)
    for i, fav in ipairs(FavoritesManager.favorites) do
        if fav.id == itemId then
            table.remove(FavoritesManager.favorites, i)
            FavoritesManager.save()
            service.speak("تم الحذف من المفضلة")
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
            service.speak("المسلسل موجود بالفعل في المفضلة")
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
    service.speak("تم إضافة المسلسل كاملاً للمفضلة")
    return true
end

function FavoritesManager.removeSeries(seriesId)
    local seriesKey = "series_" .. seriesId
    for i, fav in ipairs(FavoritesManager.seriesFavorites) do
        if fav.id == seriesKey or fav.series_id == seriesId then
            table.remove(FavoritesManager.seriesFavorites, i)
            FavoritesManager.saveSeries()
            service.speak("تم حذف المسلسل من المفضلة")
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
    service.speak("تم مسح المفضلة")
end

function FavoritesManager.clearSeries()
    FavoritesManager.seriesFavorites = {}
    FavoritesManager.saveSeries()
    service.speak("تم مسح مفضلة المسلسلات")
end

function FavoritesManager.clearAll()
    FavoritesManager.favorites = {}
    FavoritesManager.seriesFavorites = {}
    FavoritesManager.save()
    FavoritesManager.saveSeries()
    service.speak("تم مسح جميع المفضلة")
end

-- ==================================================
-- مدير السجل (History Manager)
-- ==================================================
HistoryManager = {
    history = {}
}

function HistoryManager.load()
    local saved = service.getSharedData(HISTORY_KEY)
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
        service.setSharedData(HISTORY_KEY, encoded)
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
        position = item.position or 0
    }
    
    table.insert(HistoryManager.history, 1, histItem)
    
    while #HistoryManager.history > MAX_HISTORY_ITEMS do
        table.remove(HistoryManager.history)
    end
    
    HistoryManager.save()
end

function HistoryManager.updatePosition(itemId, position)
    for i, hist in ipairs(HistoryManager.history) do
        if hist.id == itemId then
            hist.position = position
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
    service.speak("تم مسح السجل")
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

-- تحميل البيانات
FavoritesManager.load()
HistoryManager.load()

-- ==================================================
-- مشغل الفيديو (Video Player) - ExoPlayer/VideoView
-- ==================================================
VideoPlayer = {
    player = nil,
    exoPlayer = nil,
    videoView = nil,
    surfaceView = nil,
    playlist = {},
    currentIndex = 1,
    timer = nil,
    retryTimer = nil,
    dialog = nil,
    activity = nil,
    widgets = {},
    notification_id = 112244,
    audioManager = service.getSystemService(Context.AUDIO_SERVICE),
    
    retryCount = 0,
    maxRetries = 10,
    isLive = false,
    currentUrl = nil,
    isPlaying = false,
    isPrepared = false,
    currentPosition = 0,
    isFullscreen = false
}

function VideoPlayer.init()
    -- تهيئة مشغل الفيديو
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
    VideoPlayer.currentIndex = index
    
    local item = VideoPlayer.playlist[index]
    VideoPlayer.currentUrl = item.url 
    VideoPlayer.isLive = item.id and item.id:find("live")
    
    -- إضافة للسجل
    HistoryManager.add(item)
    
    service.speak("جاري تحميل الفيديو: " .. item.name)
    
    -- عرض واجهة الفيديو
    VideoPlayer.showVideoUI()
end

-- دالة ملء الشاشة
function VideoPlayer.toggleFullscreen()
    if not VideoPlayer.dialog then return end
    local win = VideoPlayer.dialog.getWindow()
    
    if not VideoPlayer.isFullscreen then
        -- تفعيل ملء الشاشة
        VideoPlayer.isFullscreen = true
        
        -- إعدادات النافذة لإخفاء شريط الحالة والتنقل
        win.setFlags(WindowManager.LayoutParams.FLAG_FULLSCREEN, WindowManager.LayoutParams.FLAG_FULLSCREEN)
        if Build.VERSION.SDK_INT >= 19 then
             win.getDecorView().setSystemUiVisibility(
                View.SYSTEM_UI_FLAG_HIDE_NAVIGATION |
                View.SYSTEM_UI_FLAG_FULLSCREEN |
                View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY
            )
        end
        win.setLayout(WindowManager.LayoutParams.MATCH_PARENT, WindowManager.LayoutParams.MATCH_PARENT)
        
        -- إخفاء العناوين والأزرار الإضافية للتركيز على الفيديو
        if VideoPlayer.widgets.titleLayout then VideoPlayer.widgets.titleLayout.setVisibility(View.GONE) end
        if VideoPlayer.widgets.extraLayout then VideoPlayer.widgets.extraLayout.setVisibility(View.GONE) end
        
        -- تغيير أيقونة الزر
        if VideoPlayer.widgets.fsBtn then VideoPlayer.widgets.fsBtn.setText("🗗 تصغير") end
        service.speak("وضع ملء الشاشة")
    else
        -- إلغاء ملء الشاشة
        VideoPlayer.isFullscreen = false
        
        win.clearFlags(WindowManager.LayoutParams.FLAG_FULLSCREEN)
        if Build.VERSION.SDK_INT >= 19 then
             win.getDecorView().setSystemUiVisibility(0)
        end
        win.setLayout(WindowManager.LayoutParams.WRAP_CONTENT, WindowManager.LayoutParams.WRAP_CONTENT)
        
        -- إظهار العناصر المخفية
        if VideoPlayer.widgets.titleLayout then VideoPlayer.widgets.titleLayout.setVisibility(View.VISIBLE) end
        if VideoPlayer.widgets.extraLayout then VideoPlayer.widgets.extraLayout.setVisibility(View.VISIBLE) end
        
        if VideoPlayer.widgets.fsBtn then VideoPlayer.widgets.fsBtn.setText("⛶ ملء الشاشة") end
        service.speak("خروج من ملء الشاشة")
    end
end

function VideoPlayer.showVideoUI()
    local currentItem = VideoPlayer.playlist[VideoPlayer.currentIndex]
    if not currentItem then return end
    
    VideoPlayer.isFullscreen = false
    
    -- إنشاء Activity للفيديو
    local layout = {
        LinearLayout,
        orientation = "vertical",
        layout_width = "fill",
        layout_height = "fill",
        backgroundColor = "#000000",
        {
            -- حاوية العنوان (لإخفائها في ملء الشاشة)
            LinearLayout,
            id = "vTitleLayout",
            layout_width = "fill",
            orientation = "vertical",
            {
                TextView,
                id = "vTitle",
                text = currentItem.name,
                textSize = "16sp",
                textColor = "#FFFFFF",
                gravity = "center",
                padding = "10dp",
                backgroundColor = "#80000000"
            },
        },
        {
            -- حاوية الفيديو
            FrameLayout,
            id = "videoContainer",
            layout_width = "fill",
            layout_height = "0dp",
            layout_weight = "1",
            backgroundColor = "#000000",
            {
                VideoView,
                id = "vVideoView",
                layout_width = "fill",
                layout_height = "fill",
                layout_gravity = "center"
            },
            {
                -- مؤشر التحميل
                ProgressBar,
                id = "vLoading",
                layout_width = "wrap",
                layout_height = "wrap",
                layout_gravity = "center"
            }
        },
        {
            -- شريط التقدم والتحكم
            LinearLayout,
            orientation = "vertical",
            layout_width = "fill",
            backgroundColor = "#80000000",
            {
                -- شريط الوقت
                LinearLayout,
                orientation = "vertical",
                layout_width = "fill",
                padding = "10dp",
                {
                    SeekBar,
                    id = "vSeek",
                    layout_width = "fill",
                    layout_marginBottom = "5dp"
                },
                {
                    TextView,
                    id = "vTime",
                    text = "00:00 / 00:00",
                    textColor = "#FFFFFF",
                    gravity = "center",
                    textSize = "14sp"
                }
            },
            {
                -- أزرار التحكم
                LinearLayout,
                orientation = "horizontal",
                gravity = "center",
                layout_width = "fill",
                padding = "5dp",
                {
                    Button,
                    text = "⏪",
                    textSize = "20sp",
                    contentDescription = "تأخير 10 ثواني",
                    onClick = function() VideoPlayer.seekRewind() end
                },
                {
                    Button,
                    text = "⏮️",
                    textSize = "20sp",
                    contentDescription = "السابق",
                    onClick = function() VideoPlayer.prev() end
                },
                {
                    Button,
                    id = "vPlayBtn",
                    text = "⏸️",
                    textSize = "24sp",
                    contentDescription = "إيقاف مؤقت",
                    onClick = function() VideoPlayer.togglePlay() end
                },
                {
                    Button,
                    text = "⏭️",
                    textSize = "20sp",
                    contentDescription = "التالي",
                    onClick = function() VideoPlayer.next() end
                },
                {
                    Button,
                    text = "⏩",
                    textSize = "20sp",
                    contentDescription = "تقديم 10 ثواني",
                    onClick = function() VideoPlayer.seekForward() end
                },
                -- زر ملء الشاشة الجديد
                {
                    Button,
                    id = "vFsBtn",
                    text = "⛶ ملء الشاشة",
                    textSize = "14sp",
                    onClick = function() VideoPlayer.toggleFullscreen() end
                }
            }
        },
        {
            -- أزرار إضافية (لإخفائها في ملء الشاشة)
            LinearLayout,
            id = "vExtraLayout",
            orientation = "horizontal",
            gravity = "center",
            layout_width = "fill",
            padding = "5dp",
            backgroundColor = "#80000000",
            {
                Button,
                id = "vFavBtn",
                text = "🤍 مفضلة",
                textSize = "14sp",
                onClick = function() VideoPlayer.toggleFavorite() end
            },
            {
                Button,
                text = "📜 القائمة",
                textSize = "14sp",
                onClick = function() VideoPlayer.showPlaylistDialog() end
            },
            {
                Button,
                text = "🔊 صوت فقط",
                textSize = "14sp",
                onClick = function() 
                    VideoPlayer.stop()
                    PLAYER_MODE = "audio"
                    service.setSharedData(PLAYER_MODE_KEY, "audio")
                    AudioPlayer.loadList(VideoPlayer.playlist, VideoPlayer.currentIndex)
                end
            },
            {
                Button,
                text = "✖️ إغلاق",
                textSize = "14sp",
                onClick = function() VideoPlayer.stop() end
            }
        }
    }
    
    VideoPlayer.dialog = LuaDialog(service)
    VideoPlayer.dialog.setView(loadlayout(layout))
    
    VideoPlayer.widgets.title = vTitle
    VideoPlayer.widgets.titleLayout = vTitleLayout
    VideoPlayer.widgets.videoView = vVideoView
    VideoPlayer.widgets.loading = vLoading
    VideoPlayer.widgets.seek = vSeek
    VideoPlayer.widgets.time = vTime
    VideoPlayer.widgets.playBtn = vPlayBtn
    VideoPlayer.widgets.favBtn = vFavBtn
    VideoPlayer.widgets.extraLayout = vExtraLayout
    VideoPlayer.widgets.fsBtn = vFsBtn
    
    -- إعداد VideoView
    VideoPlayer.setupVideoView()
    
    -- تحديث زر المفضلة
    VideoPlayer.updateFavoriteButton()
    
    VideoPlayer.dialog.show()
end

function VideoPlayer.setupVideoView()
    local videoView = VideoPlayer.widgets.videoView
    local url = VideoPlayer.currentUrl
    
    if not videoView or not url then return end
    
    -- إظهار مؤشر التحميل
    if VideoPlayer.widgets.loading then
        VideoPlayer.widgets.loading.setVisibility(View.VISIBLE)
    end
    
    -- إعداد الفيديو
    pcall(function()
        local uri = Uri.parse(url)
        videoView.setVideoURI(uri)
        
        videoView.setOnPreparedListener(MediaPlayer.OnPreparedListener{
            onPrepared = function(mp)
                VideoPlayer.isPrepared = true
                
                -- إخفاء مؤشر التحميل
                if VideoPlayer.widgets.loading then
                    VideoPlayer.widgets.loading.setVisibility(View.GONE)
                end
                
                -- استرجاع الموضع المحفوظ
                local saved = VideoPlayer.getSavedPosition()
                if saved > 0 and not VideoPlayer.isLive then
                    mp.seekTo(saved)
                    service.speak("استكمال من الموضع المحفوظ")
                end
                
                -- بدء التشغيل
                mp.start()
                VideoPlayer.isPlaying = true
                VideoPlayer.startTimer()
                VideoPlayer.updateUIState(true)
                
                service.speak("بدء العرض")
            end
        })
        
        videoView.setOnErrorListener(MediaPlayer.OnErrorListener{
            onError = function(mp, what, extra)
                service.speak("خطأ في تشغيل الفيديو")
                VideoPlayer.attemptRetry()
                return true
            end
        })
        
        videoView.setOnCompletionListener(MediaPlayer.OnCompletionListener{
            onCompletion = function(mp)
                if VideoPlayer.isLive then
                    service.speak("انقطع البث، إعادة اتصال")
                    VideoPlayer.attemptRetry()
                else
                    VideoPlayer.savePosition(0)
                    VideoPlayer.next()
                end
            end
        })
        
        -- إعداد SeekBar
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
        service.speak("محاولة " .. VideoPlayer.retryCount)
        if VideoPlayer.retryTimer then VideoPlayer.retryTimer.stop() end
        VideoPlayer.retryTimer = Ticker()
        VideoPlayer.retryTimer.Period = 3000
        VideoPlayer.retryTimer.onTick = function()
            VideoPlayer.retryTimer.stop()
            VideoPlayer.setupVideoView()
        end
        VideoPlayer.retryTimer.start()
    else
        service.speak("فشل التشغيل")
        VideoPlayer.retryCount = 0
    end
end

function VideoPlayer.togglePlay()
    local videoView = VideoPlayer.widgets.videoView
    if not videoView then return end
    
    if videoView.isPlaying() then
        videoView.pause()
        VideoPlayer.isPlaying = false
        VideoPlayer.savePosition(videoView.getCurrentPosition())
        VideoPlayer.updateUIState(false)
        service.speak("إيقاف مؤقت")
    else
        videoView.start()
        VideoPlayer.isPlaying = true
        VideoPlayer.updateUIState(true)
        service.speak("تشغيل")
    end
end

function VideoPlayer.stop()
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
    VideoPlayer.abandonAudioFocus()
    VideoPlayer.retryCount = 0
    VideoPlayer.isPlaying = false
    VideoPlayer.isPrepared = false
    
    if VideoPlayer.dialog then 
        VideoPlayer.dialog.dismiss() 
        VideoPlayer.dialog = nil
    end
end

function VideoPlayer.next()
    VideoPlayer.retryCount = 0
    if VideoPlayer.currentIndex < #VideoPlayer.playlist then
        service.speak("التالي")
        VideoPlayer.currentIndex = VideoPlayer.currentIndex + 1
        local item = VideoPlayer.playlist[VideoPlayer.currentIndex]
        VideoPlayer.currentUrl = item.url
        VideoPlayer.isLive = item.id and item.id:find("live")
        HistoryManager.add(item)
        
        if VideoPlayer.widgets.title then
            VideoPlayer.widgets.title.setText(item.name)
        end
        VideoPlayer.updateFavoriteButton()
        VideoPlayer.setupVideoView()
    else
        service.speak("نهاية القائمة")
    end
end

function VideoPlayer.prev()
    VideoPlayer.retryCount = 0
    if VideoPlayer.currentIndex > 1 then
        service.speak("السابق")
        VideoPlayer.currentIndex = VideoPlayer.currentIndex - 1
        local item = VideoPlayer.playlist[VideoPlayer.currentIndex]
        VideoPlayer.currentUrl = item.url
        VideoPlayer.isLive = item.id and item.id:find("live")
        HistoryManager.add(item)
        
        if VideoPlayer.widgets.title then
            VideoPlayer.widgets.title.setText(item.name)
        end
        VideoPlayer.updateFavoriteButton()
        VideoPlayer.setupVideoView()
    else
        service.speak("بداية القائمة")
    end
end

function VideoPlayer.seekForward()
    local videoView = VideoPlayer.widgets.videoView
    if videoView and VideoPlayer.isPlaying then
        local curr = videoView.getCurrentPosition()
        videoView.seekTo(curr + 10000)
        service.speak("تقديم")
    end
end

function VideoPlayer.seekRewind()
    local videoView = VideoPlayer.widgets.videoView
    if videoView and VideoPlayer.isPlaying then
        local curr = videoView.getCurrentPosition()
        videoView.seekTo(math.max(0, curr - 10000))
        service.speak("تأخير")
    end
end

function VideoPlayer.savePosition(pos)
    local item = VideoPlayer.playlist[VideoPlayer.currentIndex]
    if item and item.id and (not VideoPlayer.isLive) then 
        if pos == 0 then 
            service.setSharedData("resume_"..item.id, nil)
        elseif pos > 5000 then 
            service.setSharedData("resume_"..item.id, tostring(pos))
            HistoryManager.updatePosition(item.id, pos)
        end
    end
end

function VideoPlayer.getSavedPosition()
    local item = VideoPlayer.playlist[VideoPlayer.currentIndex]
    if item and item.id then
        local pos = service.getSharedData("resume_"..item.id)
        return tonumber(pos) or 0
    end
    return 0
end

function VideoPlayer.startTimer()
    VideoPlayer.stopTimer()
    VideoPlayer.timer = Ticker()
    VideoPlayer.timer.Period = 1000
    VideoPlayer.timer.onTick = function()
        local videoView = VideoPlayer.widgets.videoView
        if videoView and VideoPlayer.isPlaying and VideoPlayer.widgets.seek then
            pcall(function()
                local current = videoView.getCurrentPosition()
                local total = videoView.getDuration()
                if VideoPlayer.isLive or total <= 0 then total = 100 end 
                
                VideoPlayer.widgets.seek.setMax(total)
                VideoPlayer.widgets.seek.setProgress(current)
                
                local t_str = VideoPlayer.isLive and "Live" or string.format("%02d:%02d", math.floor(total/60000), math.floor((total%60000)/1000))
                VideoPlayer.widgets.time.setText(string.format("%02d:%02d / %s", math.floor(current/60000), math.floor((current%60000)/1000), t_str))
            end)
        end
    end
    VideoPlayer.timer.start()
end

function VideoPlayer.stopTimer()
    if VideoPlayer.timer then VideoPlayer.timer.stop(); VideoPlayer.timer = nil end
end

function VideoPlayer.updateUIState(isPlaying)
    if VideoPlayer.widgets.playBtn then
        if isPlaying then
            VideoPlayer.widgets.playBtn.setText("⏸️")
            VideoPlayer.widgets.playBtn.setContentDescription("إيقاف مؤقت") 
        else
            VideoPlayer.widgets.playBtn.setText("▶️")
            VideoPlayer.widgets.playBtn.setContentDescription("تشغيل")
        end
    end
end

function VideoPlayer.updateFavoriteButton()
    if VideoPlayer.widgets.favBtn then
        local item = VideoPlayer.getCurrentItem()
        if item and FavoritesManager.isFavorite(item.id) then
            VideoPlayer.widgets.favBtn.setText("❤️ في المفضلة")
        else
            VideoPlayer.widgets.favBtn.setText("🤍 مفضلة")
        end
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
        local prefix = (i == VideoPlayer.currentIndex) and "🔰 " or ""
        local favIcon = FavoritesManager.isFavorite(v.id) and " ❤️" or ""
        table.insert(names, prefix .. v.name .. favIcon)
    end
    local dlg = LuaDialog(service)
    dlg.setTitle("قائمة التشغيل")
    dlg.setItems(names)
    dlg.setOnItemClickListener(function(l,v,p,i)
        VideoPlayer.currentIndex = i
        local item = VideoPlayer.playlist[i]
        VideoPlayer.currentUrl = item.url
        VideoPlayer.isLive = item.id and item.id:find("live")
        HistoryManager.add(item)
        
        if VideoPlayer.widgets.title then
            VideoPlayer.widgets.title.setText(item.name)
        end
        VideoPlayer.updateFavoriteButton()
        VideoPlayer.setupVideoView()
    end)
    -- زر الرجوع للقائمة
    dlg.setNegativeButton("🔙 رجوع", nil)
    dlg.show()
end

function VideoPlayer.loadList(list, startIndex)
    VideoPlayer.playlist = list
    VideoPlayer.play(startIndex)
end

-- ==================================================
-- المحرك الصوتي (Audio Player)
-- ==================================================
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
    audioManager = service.getSystemService(Context.AUDIO_SERVICE),
    
    retryCount = 0,
    maxRetries = 10,
    isLive = false,
    currentUrl = nil
}

function AudioPlayer.initMediaSession()
    if AudioPlayer.mediaSession then return end
    pcall(function()
        AudioPlayer.mediaSession = MediaSession(service, "XtreamAudio")
        AudioPlayer.mediaSession.setFlags(3)
        AudioPlayer.mediaSession.setActive(true)
    end)
end

function AudioPlayer.init()
    if not AudioPlayer.player then
        AudioPlayer.player = MediaPlayer()
        AudioPlayer.player.setAudioStreamType(AudioManager.STREAM_MUSIC)
        AudioPlayer.player.setWakeMode(service, PowerManager.PARTIAL_WAKE_LOCK)
        
        AudioPlayer.player.setOnCompletionListener(MediaPlayer.OnCompletionListener{
            onCompletion=function(mp)
                if AudioPlayer.isLive then
                    service.speak("انقطع البث، إعادة اتصال...")
                    AudioPlayer.attemptRetry()
                else
                    local duration = mp.getDuration()
                    local current = mp.getCurrentPosition()
                    if duration > 0 and (duration - current) > 10000 then
                        service.speak("انقطع الاتصال، استكمال...")
                        AudioPlayer.savePosition(current) 
                        AudioPlayer.playRetry() 
                    else
                        AudioPlayer.savePosition(0)
                        AudioPlayer.next()
                    end
                end
            end
        })
        
        AudioPlayer.player.setOnErrorListener(MediaPlayer.OnErrorListener{
            onError=function(mp, what, extra)
                service.speak("خطأ في الاتصال، إعادة المحاولة")
                AudioPlayer.attemptRetry()
                return true
            end
        })
    end
end

function AudioPlayer.attemptRetry()
    if AudioPlayer.retryCount < AudioPlayer.maxRetries then
        AudioPlayer.retryCount = AudioPlayer.retryCount + 1
        service.speak("محاولة " .. AudioPlayer.retryCount)
        if AudioPlayer.retryTimer then AudioPlayer.retryTimer.stop() end
        AudioPlayer.retryTimer = Ticker()
        AudioPlayer.retryTimer.Period = 3000
        AudioPlayer.retryTimer.onTick = function()
            AudioPlayer.retryTimer.stop()
            AudioPlayer.playRetry() 
        end
        AudioPlayer.retryTimer.start()
        AudioPlayer.updateUIState(false)
    else
        service.speak("فشل التشغيل")
        AudioPlayer.retryCount = 0
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
    local nm = service.getSystemService(ns)
    local channelId = "xtream_final_ch"
    
    if Build.VERSION.SDK_INT >= 26 then
        local channel = NotificationChannel(channelId, "Xtream Player", NotificationManager.IMPORTANCE_LOW)
        nm.createNotificationChannel(channel)
    end
    
    local builder = Notification.Builder(service)
    if Build.VERSION.SDK_INT >= 26 then builder.setChannelId(channelId) end
    
    builder.setContentTitle("Xtream Player")
    builder.setContentText(title)
    builder.setSmallIcon(android.R.drawable.ic_media_play)
    builder.setOngoing(isPlaying)
    builder.setShowWhen(false)
    
    local pFlag = 0
    if Build.VERSION.SDK_INT >= 31 then pFlag = 67108864 end 
    
    local intent = Intent(service, service.getClass())
    local pendingIntent = PendingIntent.getActivity(service, 0, intent, pFlag)
    builder.setContentIntent(pendingIntent)
    
    local iPrev = Intent(ACTION_PREV); local pPrev = PendingIntent.getBroadcast(service, 1, iPrev, pFlag)
    builder.addAction(android.R.drawable.ic_media_previous, "السابق", pPrev)
    
    local iPlay = Intent(ACTION_PLAY_PAUSE); local pPlay = PendingIntent.getBroadcast(service, 2, iPlay, pFlag)
    local playIcon = isPlaying and android.R.drawable.ic_media_pause or android.R.drawable.ic_media_play
    builder.addAction(playIcon, "Play", pPlay)
    
    local iNext = Intent(ACTION_NEXT); local pNext = PendingIntent.getBroadcast(service, 3, iNext, pFlag)
    builder.addAction(android.R.drawable.ic_media_next, "التالي", pNext)
    
    local iClose = Intent(ACTION_CLOSE); local pClose = PendingIntent.getBroadcast(service, 4, iClose, pFlag)
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
    local nm = service.getSystemService(ns)
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
    
    AudioPlayer.retryCount = 0
    AudioPlayer.player.reset()
    AudioPlayer.currentIndex = index
    
    local item = AudioPlayer.playlist[index]
    AudioPlayer.currentUrl = item.url 
    AudioPlayer.isLive = item.id and item.id:find("live")
    
    HistoryManager.add(item)
    
    if AudioPlayer.dialog and AudioPlayer.widgets.title then
        AudioPlayer.widgets.title.setText(item.name)
    end
    
    AudioPlayer.updateFavoriteButton()
    
    service.speak("تحميل: " .. item.name)
    pcall(AudioPlayer.sendNotification, item.name, true)
    
    AudioPlayer.executeLoad()
end

function AudioPlayer.playRetry()
    AudioPlayer.init()
    AudioPlayer.player.reset()
    AudioPlayer.executeLoad()
end

function AudioPlayer.executeLoad()
    pcall(function()
        local uri = Uri.parse(AudioPlayer.currentUrl)
        local headers = HashMap()
        headers.put("User-Agent", "VLC/3.0.13 LibVLC/3.0.13")
        AudioPlayer.player.setDataSource(service, uri, headers)
        AudioPlayer.player.prepareAsync()
    end)
    
    AudioPlayer.player.setOnPreparedListener(MediaPlayer.OnPreparedListener{
        onPrepared=function(mp)
            AudioPlayer.retryCount = 0
            
            local saved = AudioPlayer.getSavedPosition()
            if saved > 0 and not AudioPlayer.isLive then 
                mp.seekTo(saved); service.speak("استكمال") 
            end
            
            mp.start()
            mp.pause()
            
            service.speak("جاري التخزين المؤقت، يرجى الانتظار 30 ثانية")
            
            if AudioPlayer.bufferTimer then AudioPlayer.bufferTimer.stop() end
            
            AudioPlayer.bufferTimer = Ticker()
            AudioPlayer.bufferTimer.Period = 30000
            AudioPlayer.bufferTimer.onTick = function()
                AudioPlayer.bufferTimer.stop()
                
                if AudioPlayer.player then
                    AudioPlayer.player.start()
                    service.speak("بدء العرض")
                    AudioPlayer.startTimer()
                    AudioPlayer.updateUIState(true)
                end
            end
            AudioPlayer.bufferTimer.start()
            
            AudioPlayer.updateUIState(false)
        end
    })
end

function AudioPlayer.togglePlay()
    if AudioPlayer.player.isPlaying() then
        AudioPlayer.player.pause()
        AudioPlayer.savePosition(AudioPlayer.player.getCurrentPosition())
        AudioPlayer.updateUIState(false)
        service.speak("إيقاف مؤقت")
        if AudioPlayer.bufferTimer then AudioPlayer.bufferTimer.stop() end
    else
        AudioPlayer.requestAudioFocus()
        AudioPlayer.player.start()
        AudioPlayer.updateUIState(true)
        service.speak("تشغيل")
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
    
    if AudioPlayer.mediaSession then
        pcall(function() AudioPlayer.mediaSession.setActive(false); AudioPlayer.mediaSession.release() end)
        AudioPlayer.mediaSession = nil
    end
    
    if AudioPlayer.dialog then AudioPlayer.dialog.dismiss() end
end

function AudioPlayer.next()
    AudioPlayer.retryCount = 0
    if AudioPlayer.currentIndex < #AudioPlayer.playlist then
        service.speak("التالي")
        AudioPlayer.play(AudioPlayer.currentIndex + 1)
    else
        service.speak("النهاية")
    end
end

function AudioPlayer.prev()
    AudioPlayer.retryCount = 0
    if AudioPlayer.currentIndex > 1 then
        service.speak("السابق")
        AudioPlayer.play(AudioPlayer.currentIndex - 1)
    else
        service.speak("البداية")
    end
end

function AudioPlayer.seekForward()
    if AudioPlayer.player and AudioPlayer.player.isPlaying() then
        local curr = AudioPlayer.player.getCurrentPosition()
        AudioPlayer.player.seekTo(curr + 10000)
        service.speak("تقديم")
    end
end

function AudioPlayer.seekRewind()
    if AudioPlayer.player and AudioPlayer.player.isPlaying() then
        local curr = AudioPlayer.player.getCurrentPosition()
        AudioPlayer.player.seekTo(curr - 10000)
        service.speak("تأخير")
    end
end

function AudioPlayer.savePosition(pos)
    local item = AudioPlayer.playlist[AudioPlayer.currentIndex]
    if item and item.id and (not AudioPlayer.isLive) then 
        if pos == 0 then 
            service.setSharedData("resume_"..item.id, nil)
        elseif pos > 5000 then 
            service.setSharedData("resume_"..item.id, tostring(pos))
            HistoryManager.updatePosition(item.id, pos)
        end
    end
end

function AudioPlayer.getSavedPosition()
    local item = AudioPlayer.playlist[AudioPlayer.currentIndex]
    if item and item.id then
        local pos = service.getSharedData("resume_"..item.id)
        return tonumber(pos) or 0
    end
    return 0
end

function AudioPlayer.startTimer()
    AudioPlayer.stopTimer()
    AudioPlayer.timer = Ticker()
    AudioPlayer.timer.Period = 1000
    AudioPlayer.timer.onTick = function()
        if AudioPlayer.player and AudioPlayer.player.isPlaying() and AudioPlayer.widgets.seek then
            local current = AudioPlayer.player.getCurrentPosition()
            local total = AudioPlayer.player.getDuration()
            if AudioPlayer.isLive or total <= 0 then total = 100 end 
            
            AudioPlayer.widgets.seek.setMax(total)
            AudioPlayer.widgets.seek.setProgress(current)
            
            local t_str = AudioPlayer.isLive and "Live Stream" or string.format("%02d:%02d", math.floor(total/60000), math.floor((total%60000)/1000))
            AudioPlayer.widgets.time.setText(string.format("%02d:%02d / %s", math.floor(current/60000), math.floor((current%60000)/1000), t_str))
        end
    end
    AudioPlayer.timer.start()
end

function AudioPlayer.stopTimer()
    if AudioPlayer.timer then AudioPlayer.timer.stop(); AudioPlayer.timer = nil end
end

function AudioPlayer.updateUIState(isPlaying)
    if AudioPlayer.playlist[AudioPlayer.currentIndex] then
        AudioPlayer.sendNotification(AudioPlayer.playlist[AudioPlayer.currentIndex].name, isPlaying)
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

function AudioPlayer.showPlaylistDialog()
    local names = {}
    for i, v in ipairs(AudioPlayer.playlist) do
        local prefix = (i == AudioPlayer.currentIndex) and "🔰 " or ""
        local favIcon = FavoritesManager.isFavorite(v.id) and " ❤️" or ""
        table.insert(names, prefix .. v.name .. favIcon)
    end
    local dlg = LuaDialog(service)
    dlg.setTitle("قائمة التشغيل")
    dlg.setItems(names)
    dlg.setOnItemClickListener(function(l,v,p,i)
        AudioPlayer.play(i) 
        if AudioPlayer.dialog then AudioPlayer.dialog.dismiss() end
        AudioPlayer.showUI()
    end)
    -- زر الرجوع
    dlg.setNegativeButton("🔙 رجوع", nil)
    dlg.show()
end

function AudioPlayer.showUI()
    if #AudioPlayer.playlist == 0 then service.speak("القائمة فارغة"); return end
    local currentItem = AudioPlayer.playlist[AudioPlayer.currentIndex]
    
    local layout = {
        LinearLayout, orientation="vertical", layout_width="fill", padding="15dp", backgroundColor="#222222",
        { TextView, id="pTitle", text=currentItem.name, textSize="18sp", textColor="#FFFFFF", gravity="center", layout_marginBottom="20dp" },
        { SeekBar, id="pSeek", layout_width="fill", layout_marginBottom="10dp" },
        { TextView, id="pTime", text="00:00", textColor="#AAAAAA", gravity="center", layout_marginBottom="20dp" },
        
        { LinearLayout, orientation="horizontal", gravity="center", layout_width="fill", layout_marginBottom="10dp",
             { Button, text="⏪ 10s", contentDescription="تأخير 10 ثواني", onClick=function() AudioPlayer.seekRewind() end },
             { Space, layout_width="20dp" },
             { Button, text="10s ⏩", contentDescription="تقديم 10 ثواني", onClick=function() AudioPlayer.seekForward() end }
        },
        
        { LinearLayout, orientation="horizontal", gravity="center", layout_width="fill",
            { Button, text="⏮️", contentDescription="السابق", onClick=function() AudioPlayer.prev() end },
            { Button, id="pPlay", text="⏸️", contentDescription="إيقاف مؤقت", textSize="20sp", onClick=function() AudioPlayer.togglePlay() end },
            { Button, text="⏭️", contentDescription="التالي", onClick=function() AudioPlayer.next() end }
        },
        
        { Button, id="pFav", text="🤍 إضافة للمفضلة", contentDescription="إضافة للمفضلة", layout_width="fill", layout_marginTop="15dp", backgroundColor="#E91E63", onClick=function() AudioPlayer.toggleFavorite() end },
        
        -- زر التبديل لمشغل الفيديو
        { Button, text="🎬 تشغيل كفيديو", contentDescription="التبديل لمشغل الفيديو", layout_width="fill", layout_marginTop="10dp", backgroundColor="#673AB7", onClick=function() 
            AudioPlayer.stop()
            PLAYER_MODE = "video"
            service.setSharedData(PLAYER_MODE_KEY, "video")
            VideoPlayer.loadList(AudioPlayer.playlist, AudioPlayer.currentIndex)
        end },
        
        { Button, text="📜 القائمة", contentDescription="عرض قائمة التشغيل", layout_width="fill", layout_marginTop="10dp", onClick=function() AudioPlayer.showPlaylistDialog() end },
        { Button, text="🔻 إخفاء", contentDescription="إخفاء المشغل", layout_width="fill", layout_marginTop="5dp", onClick=function() AudioPlayer.dialog.dismiss() end }
    }
    
    AudioPlayer.dialog = LuaDialog(service)
    AudioPlayer.dialog.setView(loadlayout(layout))
    AudioPlayer.widgets.title = pTitle
    AudioPlayer.widgets.seek = pSeek
    AudioPlayer.widgets.time = pTime
    AudioPlayer.widgets.playBtn = pPlay
    AudioPlayer.widgets.favBtn = pFav
    
    pSeek.setOnSeekBarChangeListener{
        onStopTrackingTouch=function(seekBar) if AudioPlayer.player then AudioPlayer.player.seekTo(seekBar.getProgress()) end end
    }
    
    AudioPlayer.updateFavoriteButton()
    
    if AudioPlayer.player and AudioPlayer.player.isPlaying() then
        AudioPlayer.startTimer()
        AudioPlayer.updateUIState(true)
    else
        AudioPlayer.updateUIState(false)
    end
    -- زر الرجوع
    AudioPlayer.dialog.setNegativeButton("🔙 رجوع", nil)
    AudioPlayer.dialog.show()
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

-- ==================================================
-- دالة تجهيز القوائم
-- ==================================================
function preparePlaylist(data, type)
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
        table.insert(list, {name=name, url=fullUrl, id=type.."_"..id, type=type})
    end
    return list
end

-- ==================================================
-- دالة التشغيل الموحدة (تختار بين صوت/فيديو)
-- ==================================================
function playContent(playlist, startIndex)
    if PLAYER_MODE == "video" then
        VideoPlayer.loadList(playlist, startIndex)
    else
        AudioPlayer.loadList(playlist, startIndex)
    end
end

-- ==================================================
-- نافذة اختيار وضع التشغيل
-- ==================================================
function showPlayModeSelector(playlist, startIndex)
    local options = {
        "🔊 تشغيل صوت فقط",
        "🎬 تشغيل فيديو"
    }
    
    local dlg = LuaDialog(service)
    dlg.setTitle("اختر وضع التشغيل")
    dlg.setItems(options)
    dlg.setOnItemClickListener(function(l,v,p,i)
        if i == 1 then
            PLAYER_MODE = "audio"
            service.setSharedData(PLAYER_MODE_KEY, "audio")
            AudioPlayer.loadList(playlist, startIndex)
        else
            PLAYER_MODE = "video"
            service.setSharedData(PLAYER_MODE_KEY, "video")
            VideoPlayer.loadList(playlist, startIndex)
        end
    end)
    -- إضافة أزرار التنقل
    dlg.setNeutralButton("🏠 الرئيسية", function() main() end)
    dlg.setNegativeButton("🔙 رجوع", nil)
    dlg.show()
end

-- ==================================================
-- عرض المفضلة
-- ==================================================
function showFavorites()
    local items = FavoritesManager.getAll()
    local series = FavoritesManager.getAllSeries()
    
    local totalCount = #items + #series
    
    if totalCount == 0 then
        service.speak("المفضلة فارغة")
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
        elseif fav.type == "movie" then typeIcon = "🎬 [فيلم] "
        elseif fav.type == "series" then typeIcon = "🎞️ [حلقة] " end
        table.insert(names, typeIcon .. fav.name)
        table.insert(allItems, {type = "single", data = fav})
    end
    
    local dlg = LuaDialog(service)
    dlg.setTitle("❤️ المفضلة (" .. totalCount .. ")")
    dlg.setItems(names)
    dlg.setOnItemClickListener(function(l,v,p,i)
        local selected = allItems[i]
        if selected then
            if selected.type == "full_series" then
                getSeriesEpisodes(selected.data.series_id, selected.data.name)
            else
                showPlayModeSelector({selected.data}, 1)
            end
        end
    end)
    -- إضافة أزرار التنقل
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
        "🧹 مسح جميع العناصر الفردية",
        "🧹 مسح جميع المسلسلات",
        "💣 مسح كل المفضلة"
    }
    
    local dlg = LuaDialog(service)
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
    -- إضافة أزرار التنقل
    dlg.setNeutralButton("🏠 الرئيسية", function() main() end)
    dlg.setNegativeButton("🔙 رجوع", nil)
    dlg.show()
end

function showConfirmDialog(title, message, onConfirm)
    local dlg = LuaDialog(service)
    dlg.setTitle(title)
    dlg.setMessage(message)
    dlg.setButton("نعم", function()
        onConfirm()
    end)
    -- إضافة أزرار التنقل
    dlg.setButton2("لا", nil)
    dlg.show()
end

function showDeleteFavoriteDialog()
    local favorites = FavoritesManager.getAll()
    if #favorites == 0 then 
        service.speak("لا توجد عناصر فردية")
        return 
    end
    
    local names = {}
    for i, fav in ipairs(favorites) do
        table.insert(names, fav.name)
    end
    
    local dlg = LuaDialog(service)
    dlg.setTitle("اختر عنصر للحذف")
    dlg.setItems(names)
    dlg.setOnItemClickListener(function(l,v,p,i)
        local item = favorites[i]
        if item then
            FavoritesManager.remove(item.id)
        end
    end)
    -- إضافة أزرار التنقل
    dlg.setNeutralButton("🏠 الرئيسية", function() main() end)
    dlg.setNegativeButton("🔙 رجوع", nil)
    dlg.show()
end

function showDeleteSeriesFavoriteDialog()
    local series = FavoritesManager.getAllSeries()
    if #series == 0 then 
        service.speak("لا توجد مسلسلات في المفضلة")
        return 
    end
    
    local names = {}
    for i, fav in ipairs(series) do
        table.insert(names, fav.name)
    end
    
    local dlg = LuaDialog(service)
    dlg.setTitle("اختر مسلسل للحذف")
    dlg.setItems(names)
    dlg.setOnItemClickListener(function(l,v,p,i)
        local item = series[i]
        if item then
            FavoritesManager.removeSeries(item.series_id)
        end
    end)
    -- إضافة أزرار التنقل
    dlg.setNeutralButton("🏠 الرئيسية", function() main() end)
    dlg.setNegativeButton("🔙 رجوع", nil)
    dlg.show()
end

-- ==================================================
-- عرض السجل
-- ==================================================
function showHistory()
    local history = HistoryManager.getAll()
    
    if #history == 0 then
        service.speak("السجل فارغ")
        return
    end
    
    local names = {}
    for i, hist in ipairs(history) do
        local typeIcon = ""
        if hist.type == "live" then typeIcon = "📡 "
        elseif hist.type == "movie" then typeIcon = "🎬 "
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
    
    local dlg = LuaDialog(service)
    dlg.setTitle("🕐 آخر ما شاهدته (" .. #history .. ")")
    dlg.setItems(names)
    dlg.setOnItemClickListener(function(l,v,p,i)
        local item = history[i]
        if item then
            showPlayModeSelector({item}, 1)
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
    -- إضافة أزرار التنقل
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
    
    local dlg = LuaDialog(service)
    dlg.setTitle("اختر عنصر للحذف")
    dlg.setItems(names)
    dlg.setOnItemClickListener(function(l,v,p,i)
        local item = history[i]
        if item then
            HistoryManager.remove(item.id)
            showHistory()
        end
    end)
    -- إضافة أزرار التنقل
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

-- ==================================================
-- دوال البحث
-- ==================================================
function textContains(text, query)
    if not text or not query then return false end
    return string.find(string.lower(text), string.lower(query))
end

function startGlobalSearch()
    local layout = {
        LinearLayout, orientation="vertical", padding="20dp",
        {TextView, text="بحث شامل في السيرفر", textSize="18sp", gravity="center", layout_marginBottom="10dp"},
        {EditText, id="search_input", hint="اكتب اسم القناة، الفيلم أو المسلسل", singleLine=true},
    }
    
    local dlg = LuaDialog(service)
    dlg.setView(loadlayout(layout))
    dlg.setButton("بحث", function()
        local query = search_input.getText().toString()
        if #query < 2 then
            service.speak("يرجى كتابة حرفين على الأقل")
            return
        end
        performSearchRequests(query)
    end)
    -- إضافة أزرار التنقل
    dlg.setNeutralButton("🏠 الرئيسية", function() main() end)
    dlg.setNegativeButton("🔙 رجوع", nil)
    dlg.show()
end

function performSearchRequests(query)
    local allResults = {} 
    local progress = LuaDialog(service)
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
                            name = "[🎬 فيلم] "..v.name,
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
                                name = "[📺 مسلسل] "..v.name,
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
        service.speak("لم يتم العثور على نتائج")
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

    local dlg = LuaDialog(service)
    dlg.setTitle("نتائج البحث ("..#results..")")
    dlg.setItems(names)
    dlg.setOnItemClickListener(function(l,v,p,i)
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
    -- إضافة أزرار التنقل
    dlg.setNeutralButton("🏠 الرئيسية", function() main() end)
    dlg.setNegativeButton("🔙 رجوع", nil)
    dlg.show()
end

-- ==================================================
-- دوال التصفح
-- ==================================================
function getLiveChannels(cat_id)
    service.speak("تحميل...")
    Http.get(HOST.."/player_api.php?username="..USER.."&password="..PASS.."&action=get_live_streams&category_id="..cat_id, function(code, body)
        local data = decodeRaw(body)
        if not data then return end
        local playlist = preparePlaylist(data, "live")
        local names = {}
        for _, v in ipairs(playlist) do 
            local favIcon = FavoritesManager.isFavorite(v.id) and " ❤️" or ""
            table.insert(names, v.name .. favIcon) 
        end
        local dlg = LuaDialog(service)
        dlg.setTitle("القنوات")
        dlg.setItems(names)
        dlg.setOnItemClickListener(function(l,v,p,i) showPlayModeSelector(playlist, i) end)
        -- إضافة أزرار التنقل
        dlg.setNeutralButton("🏠 الرئيسية", function() main() end)
        dlg.setNegativeButton("🔙 رجوع", nil)
        dlg.show()
    end)
end

function getLiveCategories()
    service.speak("تحميل الأقسام...")
    Http.get(HOST.."/player_api.php?username="..USER.."&password="..PASS.."&action=get_live_categories", function(c, b)
        local data = decodeRaw(b)
        if not data then return end
        local names, ids = {}, {}
        for k,v in pairs(data) do table.insert(names, v.category_name); table.insert(ids, v.category_id) end
        local dlg = LuaDialog(service)
        dlg.setTitle("أقسام البث المباشر")
        dlg.setItems(names)
        dlg.setOnItemClickListener(function(l,v,p,i) getLiveChannels(ids[i] or ids[i+1]) end)
        -- إضافة أزرار التنقل
        dlg.setNeutralButton("🏠 الرئيسية", function() main() end)
        dlg.setNegativeButton("🔙 رجوع", nil)
        dlg.show()
    end)
end

function getMovies(cat_id)
    service.speak("تحميل...")
    Http.get(HOST.."/player_api.php?username="..USER.."&password="..PASS.."&action=get_vod_streams&category_id="..cat_id, function(code, body)
        local data = decodeRaw(body)
        if not data then return end
        local playlist = preparePlaylist(data, "movie")
        local names = {}
        for _, v in ipairs(playlist) do 
            local favIcon = FavoritesManager.isFavorite(v.id) and " ❤️" or ""
            table.insert(names, v.name .. favIcon) 
        end
        local dlg = LuaDialog(service)
        dlg.setTitle("الأفلام")
        dlg.setItems(names)
        dlg.setOnItemClickListener(function(l,v,p,i) showPlayModeSelector(playlist, i) end)
        -- إضافة أزرار التنقل
        dlg.setNeutralButton("🏠 الرئيسية", function() main() end)
        dlg.setNegativeButton("🔙 رجوع", nil)
        dlg.show()
    end)
end

function getMovieCategories()
    service.speak("تحميل الأقسام...")
    Http.get(HOST.."/player_api.php?username="..USER.."&password="..PASS.."&action=get_vod_categories", function(c, b)
        local data = decodeRaw(b)
        if not data then return end
        local names, ids = {}, {}
        for k,v in pairs(data) do table.insert(names, v.category_name); table.insert(ids, v.category_id) end
        local dlg = LuaDialog(service)
        dlg.setTitle("أقسام الأفلام")
        dlg.setItems(names)
        dlg.setOnItemClickListener(function(l,v,p,i) getMovies(ids[i] or ids[i+1]) end)
        -- إضافة أزرار التنقل
        dlg.setNeutralButton("🏠 الرئيسية", function() main() end)
        dlg.setNegativeButton("🔙 رجوع", nil)
        dlg.show()
    end)
end

function showEpisodesList(episodes_data, seriesId, seriesName)
    local playlist = preparePlaylist(episodes_data, "series")
    local names = {}
    for _, v in ipairs(playlist) do 
        local favIcon = FavoritesManager.isFavorite(v.id) and " ❤️" or ""
        table.insert(names, v.name .. favIcon) 
    end
    
    local dlg = LuaDialog(service)
    dlg.setTitle("الحلقات")
    dlg.setItems(names)
    dlg.setOnItemClickListener(function(l,v,p,i) 
        showPlayModeSelector(playlist, i)
    end)
    -- إضافة أزرار التنقل
    dlg.setNeutralButton("🏠 الرئيسية", function() main() end)
    dlg.setNegativeButton("🔙 رجوع", nil)
    dlg.show()
end

function getSeriesEpisodes(series_id, series_name)
    service.speak("تحميل المواسم...")
    Http.get(HOST.."/player_api.php?username="..USER.."&password="..PASS.."&action=get_series_info&series_id="..series_id, function(code, body)
        local data = decodeRaw(body)
        if not data or not data["episodes"] then service.speak("فارغ"); return end
        
        local seasons = {}
        for k, v in pairs(data["episodes"]) do
            table.insert(seasons, tonumber(k))
        end
        table.sort(seasons)
        
        if #seasons == 0 then service.speak("لا توجد مواسم"); return end
        
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
        local favBtnText = isFav and "💔 إزالة من المفضلة" or "❤️ إضافة المسلسل للمفضلة"
        
        local dlg = LuaDialog(service)
        
        local titleIcon = isFav and " ❤️" or ""
        dlg.setTitle("📺 " .. (series_name or "المسلسل") .. titleIcon)
        
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
                    service.speak("خطأ في تحديد الموسم")
                end
            end
        end)
        
        dlg.setButton(favBtnText, function()
            FavoritesManager.toggleSeries(series_id, series_name or "مسلسل", nil)
            getSeriesEpisodes(series_id, series_name)
        end)
        
        -- إضافة أزرار التنقل
        dlg.setNeutralButton("🏠 الرئيسية", function() main() end)
        dlg.setButton2("إغلاق", nil) -- أو رجوع
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
                    episodeNum = ep.episode_num or 0
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
        service.speak("جاري تشغيل " .. #allEpisodes .. " حلقة")
        showPlayModeSelector(allEpisodes, 1)
    else
        service.speak("لا توجد حلقات")
    end
end

function getSeriesList(cat_id)
    service.speak("تحميل...")
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
        local dlg = LuaDialog(service)
        dlg.setTitle("المسلسلات")
        dlg.setItems(names)
        dlg.setOnItemClickListener(function(l,v,p,i) 
            local idx = i
            if idx == 0 then idx = 1 end
            getSeriesEpisodes(ids[idx] or ids[1], seriesNames[idx] or seriesNames[1]) 
        end)
        -- إضافة أزرار التنقل
        dlg.setNeutralButton("🏠 الرئيسية", function() main() end)
        dlg.setNegativeButton("🔙 رجوع", nil)
        dlg.show()
    end)
end

function getSeriesCategories()
    service.speak("تحميل الأقسام...")
    Http.get(HOST.."/player_api.php?username="..USER.."&password="..PASS.."&action=get_series_categories", function(c, b)
        local data = decodeRaw(b)
        if not data then return end
        local names, ids = {}, {}
        for k,v in pairs(data) do table.insert(names, v.category_name); table.insert(ids, v.category_id) end
        local dlg = LuaDialog(service)
        dlg.setTitle("أقسام المسلسلات")
        dlg.setItems(names)
        dlg.setOnItemClickListener(function(l,v,p,i) getSeriesList(ids[i] or ids[i+1]) end)
        -- إضافة أزرار التنقل
        dlg.setNeutralButton("🏠 الرئيسية", function() main() end)
        dlg.setNegativeButton("🔙 رجوع", nil)
        dlg.show()
    end)
end

function showFavoriteSeriesOnly()
    local series = FavoritesManager.getAllSeries()
    
    if #series == 0 then
        service.speak("لا توجد مسلسلات في المفضلة")
        return
    end
    
    local names = {}
    for i, fav in ipairs(series) do
        table.insert(names, "📺 " .. fav.name)
    end
    
    local dlg = LuaDialog(service)
    dlg.setTitle("📺 مسلسلاتي المفضلة (" .. #series .. ")")
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
    -- إضافة أزرار التنقل
    dlg.setNeutralButton("🏠 الرئيسية", function() main() end)
    dlg.setNegativeButton("🔙 رجوع", nil)
    dlg.show()
end

-- ==================================================
-- إعدادات المشغل
-- ==================================================
function showPlayerSettings()
    local currentModeText = PLAYER_MODE == "video" and "🎬 فيديو" or "🔊 صوت"
    
    local options = {
        "🔊 تعيين الوضع الافتراضي: صوت",
        "🎬 تعيين الوضع الافتراضي: فيديو",
        "📊 الوضع الحالي: " .. currentModeText
    }
    
    local dlg = LuaDialog(service)
    dlg.setTitle("⚙️ إعدادات المشغل")
    dlg.setItems(options)
    dlg.setOnItemClickListener(function(l,v,p,i)
        if i == 1 then
            PLAYER_MODE = "audio"
            service.setSharedData(PLAYER_MODE_KEY, "audio")
            service.speak("تم تعيين الوضع الافتراضي: صوت")
        elseif i == 2 then
            PLAYER_MODE = "video"
            service.setSharedData(PLAYER_MODE_KEY, "video")
            service.speak("تم تعيين الوضع الافتراضي: فيديو")
        end
    end)
    -- إضافة أزرار التنقل
    dlg.setNeutralButton("🏠 الرئيسية", function() main() end)
    dlg.setNegativeButton("🔙 رجوع", nil)
    dlg.show()
end

-- ==================================================
-- الواجهة الرئيسية
-- ==================================================
function main()
    local favCount = #FavoritesManager.getAll() + #FavoritesManager.getAllSeries()
    local histCount = #HistoryManager.getAll()
    local modeIcon = PLAYER_MODE == "video" and "🎬" or "🔊"
    
    local layout = {
        LinearLayout, orientation="vertical", layout_width="fill", padding="20dp", backgroundColor="#1a1a2e",
        { TextView, text="Xtream Player Pro", textSize="24sp", textColor="#FFFFFF", gravity="center", layout_marginBottom="5dp" },
        { TextView, text=modeIcon .. " وضع التشغيل: " .. (PLAYER_MODE == "video" and "فيديو" or "صوت"), textSize="12sp", textColor="#888888", gravity="center", layout_marginBottom="20dp" },
        
        -- بحث
        { Button, text="🔍 بحث شامل", layout_width="fill", backgroundColor="#009688", textColor="#FFFFFF", onClick=function() startGlobalSearch() end },
        { TextView, layout_height="15dp"},
        
        -- المفضلة والسجل
        { LinearLayout, orientation="horizontal", gravity="center", layout_width="fill",
            { Button, text="❤️ المفضلة (" .. favCount .. ")", layout_width="0dp", layout_weight="1", backgroundColor="#E91E63", textColor="#FFFFFF", onClick=function() showFavorites() end },
            { Space, layout_width="10dp" },
            { Button, text="🕐 السجل (" .. histCount .. ")", layout_width="0dp", layout_weight="1", backgroundColor="#FF9800", textColor="#FFFFFF", onClick=function() showHistory() end }
        },
        { TextView, layout_height="10dp"},
        
        { Button, text="📺 مسلسلاتي المفضلة", layout_width="fill", backgroundColor="#9C27B0", textColor="#FFFFFF", onClick=function() showFavoriteSeriesOnly() end },
        { TextView, layout_height="20dp"},
        
        -- التصفح
        { TextView, text="── تصفح المحتوى ──", textSize="14sp", textColor="#666666", gravity="center", layout_marginBottom="10dp" },
        
        { Button, text="📡 بث مباشر", layout_width="fill", backgroundColor="#3F51B5", textColor="#FFFFFF", onClick=function() getLiveCategories() end },
        { TextView, layout_height="10dp"},
        { Button, text="🎬 أفلام", layout_width="fill", backgroundColor="#673AB7", textColor="#FFFFFF", onClick=function() getMovieCategories() end },
        { TextView, layout_height="10dp"},
        { Button, text="📺 مسلسلات", layout_width="fill", backgroundColor="#7B1FA2", textColor="#FFFFFF", onClick=function() getSeriesCategories() end },
        { TextView, layout_height="25dp"},
        
        -- المشغلات
        { LinearLayout, orientation="horizontal", gravity="center", layout_width="fill",
            { Button, text="🔊 مشغل الصوت", layout_width="0dp", layout_weight="1", backgroundColor="#37474F", textColor="#FFFFFF", onClick=function() 
                if AudioPlayer.player then AudioPlayer.showUI() else service.speak("لا يوجد صوت") end 
            end },
            { Space, layout_width="10dp" },
            { Button, text="🎬 مشغل الفيديو", layout_width="0dp", layout_weight="1", backgroundColor="#455A64", textColor="#FFFFFF", onClick=function() 
                if VideoPlayer.dialog then service.speak("الفيديو قيد التشغيل") else service.speak("لا يوجد فيديو") end 
            end }
        },
        { TextView, layout_height="15dp"},
        
        -- الإعدادات
        { LinearLayout, orientation="horizontal", gravity="center", layout_width="fill",
            { Button, text="⚙️ إعدادات المشغل", layout_width="0dp", layout_weight="1", backgroundColor="#546E7A", textColor="#FFFFFF", onClick=function() showPlayerSettings() end },
            { Space, layout_width="10dp" },
            { Button, text="🔧 السيرفر", layout_width="0dp", layout_weight="1", backgroundColor="#455A64", textColor="#FFFFFF", onClick=function() showLogin() end }
        },
        { TextView, layout_height="10dp"},
        
        { Button, text="🚪 خروج", layout_width="fill", backgroundColor="#F44336", textColor="#FFFFFF", onClick=function() 
            AudioPlayer.stop()
            VideoPlayer.stop()
            service.setSharedData("xt_host", nil)
            service.setSharedData("xt_user", nil)
            service.setSharedData("xt_pass", nil)
            HOST, USER, PASS = nil, nil, nil
            showLogin()
        end }
    }
    local dlg = LuaDialog(service)
    dlg.setView(loadlayout(layout))
    dlg.setNegativeButton("إغلاق", nil)
    dlg.show()
end

function showLogin()
    local layout = {
        LinearLayout, orientation="vertical", padding="20dp", backgroundColor="#1a1a2e",
        { TextView, text="🔐 تسجيل الدخول", textSize="20sp", textColor="#FFFFFF", gravity="center", layout_marginBottom="20dp" },
        { TextView, text="رابط السيرفر:", textColor="#AAAAAA", layout_marginBottom="5dp" },
        { EditText, id="e_h", hint="http://url:port", text=HOST or "", singleLine=true },
        { TextView, layout_height="10dp" },
        { TextView, text="اسم المستخدم:", textColor="#AAAAAA", layout_marginBottom="5dp" },
        { EditText, id="e_u", hint="Username", text=USER or "", singleLine=true },
        { TextView, layout_height="10dp" },
        { TextView, text="كلمة المرور:", textColor="#AAAAAA", layout_marginBottom="5dp" },
        { EditText, id="e_p", hint="Password", text=PASS or "", singleLine=true }
    }
    local dlg = LuaDialog(service)
    dlg.setView(loadlayout(layout))
    dlg.setButton("حفظ ودخول", function()
        local h, u, p = e_h.getText().toString(), e_u.getText().toString(), e_p.getText().toString()
        if h == "" or u == "" or p == "" then
            service.speak("يرجى ملء جميع الحقول")
            return
        end
        if not h:find("http") then h = "http://"..h end
        service.setSharedData("xt_host", h); HOST = h
        service.setSharedData("xt_user", u); USER = u
        service.setSharedData("xt_pass", p); PASS = p
        service.speak("تم الحفظ")
        main()
    end)
    dlg.setButton2("إلغاء", nil)
    dlg.show()
end

-- ==================================================
-- نقطة البداية
-- ==================================================
if HOST and USER and HOST ~= "" then 
    main() 
else 
    showLogin() 
end