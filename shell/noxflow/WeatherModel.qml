// WeatherModel — fetches weather from wttr.in, caches via FileView.
// Provides current conditions + forecast for Dashboard + Bar chip.

import QtQml
import QtQuick
import Quickshell
import Quickshell.Io
import "ModelUtils.js" as Utils
import "components" as Components

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
    // Exponential backoff. The delay used to be a flat 60 s forever, so a
    // machine with no network retried once a minute for the entire session and
    // wrote one journal line each time — the model was the loudest thing in the
    // log during an outage.
    readonly property int retryBase: 60000      // first retry: 1 min
    readonly property int retryMax: 1800000     // cap at 30 min
    property int retryAttempt: 0
    readonly property int retryDelay: Math.min(
        retryBase * Math.pow(2, retryAttempt), retryMax)
    // True once anything has failed, so recovery can be reported once.
    property bool degraded: false

    // ── Fetch weather ──
    function fetch() {
        if (loading) return;
        loading = true;
        lastError = "";
        var location = weatherLocation;
        var url = location ? "https://wttr.in/" + encodeURIComponent(location) + "?format=j1" : "https://wttr.in?format=j1";
        fetchProcess.run(["curl", "-s", "--max-time", "10", url]);
    }

    property Components.Command fetchProcess: Components.Command {
        label: "Weather fetch"
        onExited: function(code) {
            root.loading = false;
            if (code !== 0) {
                // curl 35 is an SSL connect error — usually a captive portal or
                // a network that has come up but cannot reach the internet.
                root.lastError = root.fetchProcess.failureText();
                root.status = "error";
                root.retryAttempt = Math.min(root.retryAttempt + 1, 20);
                root.reportFailure(root.lastError);
                scheduleRetry();
                return;
            }
            try {
                var json = JSON.parse(root.fetchProcess.output);
                root.parseWeather(json);
                root.status = "available";
                root.retryAttempt = 0;
                root.reportRecovery();
                // Cache
                try {
                    cacheFile.setText(JSON.stringify(json));
                } catch (e) {
                    // noop
                }
            } catch (e) {
                root.lastError = "Weather parse failed: " + e
                    + (root.fetchProcess.errorOutput.trim() ? " (" + root.fetchProcess.errorOutput.trim() + ")" : "");
                root.status = "error";
                root.retryAttempt = Math.min(root.retryAttempt + 1, 20);
                root.reportFailure(root.lastError);
                scheduleRetry();
            }
        }
    }

    // ── Schedule a retry after failure ──
    property Timer retryTimer: Timer {
        id: retryTimer
        // Starts at the current backoff level; scheduleRetry() re-reads it on
        // every failure, so it has to track retryDelay rather than a constant.
        interval: root.retryDelay
        repeat: false
        running: false
        onTriggered: root.fetch()
    }

    function scheduleRetry() {
        retryTimer.interval = root.retryDelay;
        retryTimer.restart();
    }

    /// Journal a failure without turning an outage into a log flood.
    ///
    /// Only the first two failures are reported: after that the backoff has
    /// already stretched the interval to minutes, and repeating the same line
    /// adds nothing. Recovery is always reported, so a long silence still
    /// resolves into a visible pair of lines.
    function reportFailure(message) {
        root.degraded = true;
        if (root.retryAttempt <= 1) console.warn("weather:", message);
    }

    function reportRecovery() {
        if (!root.degraded) return;
        root.degraded = false;
        console.log("weather: recovered after " + root.retryAttempt + " failed attempt(s)");
    }

    property FileView cacheFile: FileView {
        id: cacheFile
        // Empty until the cache directory exists. Setting this eagerly made the
        // first run depend on ~/.local/state/noxflow already being created by
        // some other model.
        path: ""
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

    property Components.Command ensureCacheDir: Components.Command {
        label: "Weather cache directory"
        onExited: function(code) {
            // Set the path even when mkdir failed: a missing cache is not a
            // reason to never fetch. loadFailed already routes to fetch().
            cacheFile.path = root.cachePath;
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
        // Load cache first, then the fetchTimer will periodically refresh.
        // The directory has to exist first, so this is what actually runs
        // ensureCacheDir — it was previously declared and never invoked.
        ensureCacheDir.run(["mkdir", "-p", root.cacheDir]);
    }
}
