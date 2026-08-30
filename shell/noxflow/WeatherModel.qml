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
    property string status: "available"
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
                console.warn("weather:", root.lastError);
                return;
            }
            try {
                var json = JSON.parse(root.fetchBuffer);
                root.parseWeather(json);
                // Cache
                try {
                    cacheFile.setText(JSON.stringify(json));
                } catch (e) {
                    // noop
                }
            } catch (e) {
                root.lastError = "Weather parse failed: " + e;
                console.warn("weather:", root.lastError);
            }
        }
    }

    property FileView cacheFile: FileView {
        id: cacheFile
        path: root.cachePath
        watchChanges: false
        onLoaded: {
            try {
                var json = JSON.parse(cacheFile.text());
                root.parseWeather(json);
            } catch (e) { /* no cache yet */ }
        }
        onLoadFailed: function(error) {
            ensureCacheDir.running = true;
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

    // ── Fetch timer — declared as property because QtObject has no default child slot ──
    property Timer fetchTimer: Timer {
        id: fetchTimer
        interval: root.fetchInterval
        repeat: false
        running: false
        onTriggered: root.fetch()
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
        icon = "☀️";  // wttr.in icons are text; map later
        temperature = parseFloat(current.temp_C) || 0;
        feelsLike = parseFloat(current.FeelsLikeC) || 0;
        humidity = parseInt(current.humidity) || 0;
        windSpeed = parseFloat(current.windspeedKmph) || 0;
        windDir = current.winddir16Point || "";
        isDay = current.weatherIconUrl.indexOf("day") >= 0;

        // Forecast
        var fc = [];
        if (json.weather) {
            for (var i = 0; i < Math.min(json.weather.length, 3); i++) {
                var day = json.weather[i];
                var date = new Date(day.date);
                fc.push({
                    day: date.toLocaleDateString(Qt.locale(), Locale.ShortFormat),
                    condition: day.hourly[0].weatherDesc[0].value,
                    icon: "☀️",
                    tempHigh: parseFloat(day.maxtempC) || 0,
                    tempLow: parseFloat(day.mintempC) || 0,
                    precip: parseInt(day.hourly[0].chanceofrain) || 0,
                });
            }
        }
        root.forecast = fc;

        // Schedule next fetch
        fetchTimer.restart();
    }

    // ── Init ──
    function start() {
        // Load cache first, then fetch fresh
        cacheFile.path = root.cachePath;
    }
}
