// WeatherModel — fetches weather from wttr.in, caches via FileView.
// Provides current conditions + forecast for Dashboard + Bar chip.

import QtQml
import QtQuick
import Quickshell
import Quickshell.Io
import "ModelUtils.js" as Utils

QtObject {
    id: root

    property string providerName: "weather"
    // Status state machine:
    // "unavailable" = no data loaded yet (initial)
    // "available"   = valid data loaded
    // "error"       = last fetch/parse failed; recovery timer is active
    property string status: "unavailable"
    readonly property bool available: status === "available"

    // ── Current weather ──
    property string location: ""
    property string condition: ""
    property string icon: ""
    property real temperature: 0
    property real feelsLike: 0
    property int humidity: 0
    property real windSpeed: 0
    property string windDir: ""
    property bool isDay: true
    property bool loading: false
    property string lastError: ""

    // ── Forecast (next 3 days) ──
    property var forecast: []  // [{day, condition, icon, tempHigh, tempLow, precip}]

    // ── Cache ──
    readonly property string cacheDir: {
        var state = Quickshell.env("XDG_STATE_HOME");
        if (!state) state = Quickshell.env("HOME") + "/.local/state";
        return state + "/noxflow";
    }
    readonly property string cachePath: cacheDir + "/weather.json"

    // ── Settings (from env or config) ──
    readonly property string weatherLocation: Quickshell.env("NOXFLOW_WEATHER_LOCATION") || ""
    readonly property int fetchInterval: 600000  // 10 min
    readonly property int retryInterval: 60000   // 1 min on failure

    // ── Fetch weather ──
    function fetch() {
        if (loading) return;
        loading = true;
        lastError = "";
        var location = weatherLocation;
        var url = location ? "https://wttr.in/" + encodeURIComponent(location) + "?format=j1" : "https://wttr.in?format=j1";
        fetchProcess.command = ["curl", "-s", "--max-time", "10", url];
        fetchBuffer = "";
        fetchProcess.running = true;
    }

    property string fetchBuffer: ""

    property Process fetchProcess: Process {
        id: fetchProcess
        running: false
        stdout: SplitParser {
            splitMarker: ""
            onRead: function(data) { root.fetchBuffer += data; }
        }
        onExited: function(code, status) {
            root.loading = false;
            if (code !== 0) {
                root.lastError = "Weather fetch failed (curl exit " + code + ")";
                root.status = "error";
                console.warn("weather:", root.lastError);
                scheduleRetry();
                return;
            }
            try {
                var json = JSON.parse(root.fetchBuffer);
                root.parseWeather(json);
                root.status = "available";
                // Cache
                try {
                    cacheFile.setText(JSON.stringify(json));
                } catch (e) {
                    // noop
                }
            } catch (e) {
                root.lastError = "Weather parse failed: " + e;
                root.status = "error";
                console.warn("weather:", root.lastError);
                scheduleRetry();
            }
        }
    }

    // ── Schedule a retry after failure ──
    property Timer retryTimer: Timer {
        id: retryTimer
        interval: root.retryInterval
        repeat: false
        running: false
        onTriggered: root.fetch()
    }

    function scheduleRetry() {
        retryTimer.interval = root.retryInterval;
        retryTimer.restart();
    }

    property FileView cacheFile: FileView {
        id: cacheFile
        path: root.cachePath
        watchChanges: false
        onLoaded: {
            try {
                var json = JSON.parse(cacheFile.text());
                root.parseWeather(json);
                // Cache loaded successfully means we have data
                if (root.status !== "available") {
                    root.status = "available";
                }
            } catch (e) {
                // Cache parse failed — wait for network fetch
            }
        }
        onLoadFailed: function(error) {
            // No cache yet — trigger a fetch
            root.fetch();
        }
    }

    property Process ensureCacheDir: Process {
        id: ensureCacheDir
        running: false
        command: ["mkdir", "-p", root.cacheDir]
        onExited: function(code, status) {
            if (code === 0) cacheFile.path = root.cachePath;
        }
    }

    // ── Persistent fetch timer — always running, provides regular refresh ──
    property Timer fetchTimer: Timer {
        id: fetchTimer
        interval: root.fetchInterval
        repeat: true
        running: true
        onTriggered: root.fetch()
    }

    // ── Map wttr.in condition string to an emoji icon ──
    function mapConditionToIcon(condition, isDay) {
        if (!condition) return isDay ? "🌡️" : "🌡️";
        var c = condition.toLowerCase();
        if (c.includes("sunny") || c.includes("clear")) return isDay ? "☀️" : "🌙";
        if (c.includes("partly")) return isDay ? "⛅" : "☁️";
        if (c.includes("cloudy") || c.includes("overcast")) return "☁️";
        if (c.includes("mist") || c.includes("fog") || c.includes("haze")) return "🌫️";
        if (c.includes("rain") || c.includes("drizzle")) return "🌧️";
        if (c.includes("thunder") || c.includes("storm")) return "⛈️";
        if (c.includes("snow") || c.includes("sleet") || c.includes("blizzard")) return "❄️";
        if (c.includes("shower")) return "🌦️";
        return isDay ? "☀️" : "🌙";
    }

    // ── Parse wttr.in JSON ──
    function parseWeather(json) {
        if (!json || !json.current_condition || json.current_condition.length === 0) {
            lastError = "No weather data";
            return;
        }

        var current = json.current_condition[0];
        location = json.nearest_area && json.nearest_area[0]
                   ? json.nearest_area[0].areaName[0].value : "Unknown";
        condition = current.weatherDesc[0].value || "";

        // Detect day/night from the icon URL rather than string search
        var iconUrl = current.weatherIconUrl || "";
        isDay = iconUrl.indexOf("night") < 0 && iconUrl.indexOf("moon") < 0;

        icon = mapConditionToIcon(condition, isDay);
        temperature = parseFloat(current.temp_C) || 0;
        feelsLike = parseFloat(current.FeelsLikeC) || 0;
        humidity = parseInt(current.humidity) || 0;
        windSpeed = parseFloat(current.windspeedKmph) || 0;
        windDir = current.winddir16Point || "";

        // Forecast
        var fc = [];
        if (json.weather) {
            for (var i = 0; i < Math.min(json.weather.length, 3); i++) {
                var day = json.weather[i];
                var date = new Date(day.date);
                var dayIconUrl = day.hourly && day.hourly[0] && day.hourly[0].weatherIconUrl
                                 ? day.hourly[0].weatherIconUrl : "";
                var dayIsDay = dayIconUrl.indexOf("night") < 0 && dayIconUrl.indexOf("moon") < 0;
                var dayCondition = day.hourly && day.hourly[0] && day.hourly[0].weatherDesc
                                  ? day.hourly[0].weatherDesc[0].value : "";
                fc.push({
                    day: date.toLocaleDateString(Qt.locale(), Locale.ShortFormat),
                    condition: dayCondition,
                    icon: mapConditionToIcon(dayCondition, dayIsDay),
                    tempHigh: parseFloat(day.maxtempC) || 0,
                    tempLow: parseFloat(day.mintempC) || 0,
                    precip: parseInt(day.hourly && day.hourly[0] ? day.hourly[0].chanceofrain : 0) || 0,
                });
            }
        }
        root.forecast = fc;
    }

    // ── Init ──
    function start() {
        // Load cache first, then the fetchTimer will periodically refresh
        cacheFile.path = root.cachePath;
    }
}
