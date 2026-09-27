pragma Singleton
import QtQml
import QtQuick
import Quickshell
import Quickshell.Io
import "ThemeProfiles.js" as Profiles

QtObject {
    id: root

    // ── Current active profile name ──
    property string currentProfile: "material-expressive"

    // Wallpaper themes are generated outside the shell. FileView watches the
    // canonical JSON so the bar, borders, and every semantic surface update
    // in place instead of requiring a shell restart.
    readonly property string runtimeThemePath: {
        var cache = Quickshell.env("XDG_CACHE_HOME");
        if (!cache) cache = Quickshell.env("HOME") + "/.cache";
        return cache + "/hypr/theme-palette.json";
    }
    property string runtimeThemeHash: ""
    property string runtimeThemeError: ""
    property FileView runtimeThemeFile: FileView {
        path: root.runtimeThemePath
        watchChanges: true
        onLoaded: root.loadRuntimeTheme()
        onLoadFailed: function(error) {
            // The static profile remains the safe fallback on first boot.
            root.runtimeThemeError = "Wallpaper theme unavailable: " + error;
        }
    }

    // appearance (config-level, not per-profile)
    readonly property string appearanceMode: "dark"
    readonly property string appearanceDensity: "comfortable"
    // appearanceRadius is the canonical radius the user picked. Writable so
    // the settings panel and external hydration stay in sync — the label
    // ("14px", "20px", ...) must always reflect the radius actually applied
    // to radiusMd, radiusLg and radiusXl.
    property int appearanceRadius: 14
    readonly property string appearanceMotion: "fluid"
    readonly property string appearanceTransparency: "balanced"

    // ── Tonal (writable — switched by applyProfile) ──
    property color tonalBackground: "#151218"
    property color tonalPrimary: "#D6A083"
    property color tonalOnPrimary: "#2A1813"
    property color tonalPrimaryContainer: "#5A3931"
    property color tonalOnPrimaryContainer: "#F8DCCB"
    property color tonalSecondary: "#9DB9A6"
    property color tonalOnSecondary: "#152019"
    property color tonalSecondaryContainer: "#30483A"
    property color tonalOnSecondaryContainer: "#D1E8D4"
    property color tonalTertiary: "#B7A3C7"
    property color tonalOnTertiary: "#21172A"
    property color tonalTertiaryContainer: "#493A50"
    property color tonalOnTertiaryContainer: "#EBDCF0"
    // Neutral palette (new — from wallpaper-derived neutral hue).
    property color tonalNeutral: "#9B8FA0"
    property color tonalOnNeutral: "#2B2529"
    property color tonalNeutralContainer: "#383040"
    property color tonalOnNeutralContainer: "#EBDCF0"
    property color tonalNeutralVariant: "#8E8390"
    property color tonalOnNeutralVariant: "#2B2529"

    // ── Surface (writable) ──
    // Fine-grained surface ladder from wallpaper compiler.
    property color surfaceSurfaceCanvas: "#151218"
    property color surfaceSurfaceBase: "#1C1820"
    property color surfaceSurface1: "#201C22"
    property color surfaceSurface2: "#252029"
    property color surfaceSurface3: "#2C2630"
    property color surfaceSurfaceFloating: "#332C38"
    // Legacy aliases for existing components.
    property color surfaceSurface: "#1C1820"
    property color surfaceSurfaceContainerLow: "#17141A"
    property color surfaceSurfaceContainer: "#241F29"
    property color surfaceSurfaceContainerHigh: "#302A36"
    property color surfaceSurfaceContainerHighest: "#3D3442"
    readonly property color surfaceSurfaceHighest: surfaceSurfaceContainerHighest
    property color surfaceSurfaceVariant: "#463B49"
    property color surfaceInverseSurface: "#F0E8E0"
    property color surfaceInverseOnSurface: "#2B2529"

    // ── Text (writable) ──
    property color textPrimary: "#F5EEE9"
    property color textSecondary: "#DED4D0"
    property color textMuted: "#AFA2A1"
    property color textDisabled: "#71666C"
    property color textOnPrimary: "#2A1813"
    property color textOnSecondary: "#152019"
    property color textOnSurfaceVariant: "#CBBEC0"

    // ── Outline (writable) ──
    property color outlineDefault: "#6E5D69"
    property color outlineSubtle: "#4A3D49"
    property color outlineStrong: "#B9A4A2"
    property color outlineFocus: "#E0B39A"

    // ── State (writable) ──
    property color stateSuccess: "#A9D3A7"
    property color stateOnSuccess: "#152016"
    property color stateSuccessContainer: "#30483A"
    property color stateOnSuccessContainer: "#D1E8D4"
    property color stateWarning: "#E5C184"
    property color stateOnWarning: "#2B2111"
    property color stateWarningContainer: "#4A3820"
    property color stateOnWarningContainer: "#F8E8C0"
    property color stateDanger: "#E79A9A"
    property color stateOnDanger: "#32191D"
    property color stateDangerContainer: "#5A3038"
    property color stateOnDangerContainer: "#F8D8D8"
    property color stateInfo: "#A8C4D0"
    property color stateOnInfo: "#17242A"
    property color stateInfoContainer: "#2A3A48"
    property color stateOnInfoContainer: "#C8E4F0"
    property color stateHoverOverlay: "#FFFFFF"
    property color statePressedOverlay: "#000000"
    property color stateFocusOverlay: "#E0B39A"
    property color stateDisabledOverlay: "#FFFFFF"

    // Accent interaction states (hover, pressed, focus).
    property color accentPrimary: "#D6A083"
    property color accentSecondary: "#9DB9A6"
    property color accentTertiary: "#B7A3C7"
    property color accentHover: "#E0B090"
    property color accentPressed: "#C09070"
    property color accentFocus: "#D8B093"

    // Wallpaper-derived personality classification.
    property string personalityClass: "material-expressive"

    // spacing
    readonly property int spacingNone: 0
    readonly property int spacingXs: 4
    readonly property int spacingSm: 8
    readonly property int spacingMd: 12
    readonly property int spacingLg: 16
    readonly property int spacingXl: 24
    readonly property int spacingXxl: 32
    readonly property int spacingSection: 40

    // radius (writable — can change with profile)
    property int radiusNone: 0
    property int radiusXs: 4
    property int radiusSm: 8
    property int radiusMd: 12
    property int radiusLg: 16
    property int radiusXl: 24
    property int radiusPill: 999

    // elevation
    readonly property int elevationNone: 0
    readonly property int elevationLow: 1
    readonly property int elevationMedium: 3
    readonly property int elevationHigh: 6
    readonly property int elevationOverlay: 12

    // typography
    readonly property string typographyFontFamily: "Inter"
    readonly property int typographyDisplayLarge: 36
    readonly property int typographyDisplayMedium: 28
    readonly property int typographyHeadlineLarge: 24
    readonly property int typographyHeadlineMedium: 20
    readonly property int typographyTitleLarge: 18
    readonly property int typographyTitleMedium: 16
    readonly property int typographyBodyLarge: 16
    readonly property int typographyBodyMedium: 14
    readonly property int typographyBodySmall: 12
    readonly property int typographyLabelLarge: 14
    readonly property int typographyLabelMedium: 12
    readonly property int typographyLabelSmall: 11

    // icon
    readonly property int iconXs: 16
    readonly property int iconSm: 20
    readonly property int iconMd: 24
    readonly property int iconLg: 32
    readonly property int iconXl: 48

    // duration
    readonly property int durationInstant: 0
    readonly property int durationShort: 100
    readonly property int durationMedium: 200
    readonly property int durationLong: 350
    readonly property int durationEmphasized: 500

    // Island geometry and interaction timings are shared by the host,
    // controller, and extracted island presentation components.
    readonly property int islandIdleWidth: 150
    readonly property int islandIdleHeight: 38
    readonly property int islandCompactMinWidth: 180
    readonly property int islandCompactMaxWidth: 280
    readonly property int islandActivityMinWidth: 360
    readonly property int islandActivityMaxWidth: 450
    readonly property int islandDashboardMaxWidth: 460
    readonly property int islandLauncherWidth: 620
    readonly property int islandLauncherHeight: 520
    readonly property int islandCalendarWidth: 520
    readonly property int islandHoverDwell: 140
    readonly property int islandTransitGrace: 450
    readonly property int islandExpandDuration: 205
    readonly property int islandSwitchDuration: 175
    readonly property int islandCollapseDuration: 145

    // easing
    readonly property string easingStandard: "cubic-bezier(0.2, 0.0, 0.0, 1.0)"
    readonly property string easingEmphasized: "cubic-bezier(0.2, 0.0, 0.0, 1.0)"
    readonly property string easingDecelerated: "cubic-bezier(0.0, 0.0, 0.2, 1.0)"
    readonly property string easingAccelerated: "cubic-bezier(0.3, 0.0, 1.0, 1.0)"

    // opacity
    readonly property real opacityDisabled: 0.38
    readonly property real opacityScrim: 0.6
    readonly property real opacityMedium: 0.72
    readonly property real opacitySubtle: 0.8
    readonly property real opacityFull: 1.0

    // Moderate glass: surfaces remain legible while the wallpaper contributes
    // atmosphere. Keep these centralized so every surface can be tuned together.
    // Keep the chrome calm and legible over busy wallpapers. The old values
    // let terminal text and wallpaper compete with controls, which made the
    // sheet feel like a translucent debug overlay instead of a system panel.
    property real glassPanelAlpha: 0.92
    property real glassCardAlpha: 0.76
    property real glassOverlayAlpha: 0.60
    property real glassBorderAlpha: 0.64
    property real glassScrimAlpha: 0.32

    // blur
    readonly property int blurNone: 0
    readonly property int blurSubtle: 8
    readonly property int blurMedium: 16
    readonly property int blurStrong: 28

    readonly property int glassBlur: 16

    // height
    readonly property int heightIconButton: 40
    readonly property int heightButton: 40
    readonly property int heightControl: 44
    readonly property int heightField: 48
    readonly property int heightChip: 32
    // Keep the persistent bar thin; panels use their own control metrics.
    readonly property int heightToolbar: 44

    // reduced_motion
    readonly property bool reducedMotionEnabled: false
    readonly property real reducedMotionDurationScale: 0.0
    readonly property bool reducedMotionDisableBlur: true
    readonly property bool reducedMotionDisableScale: true

    property string activeDensity: appearanceDensity
    property bool reducedMotion: reducedMotionEnabled

    // ── Public API ──
    function scale(value, density) { return value * (density === "compact" ? 0.9 : density === "spacious" ? 1.1 : 1.0); }
    function scaled(value) { return scale(value, activeDensity); }
    function duration(value) { return reducedMotion ? reducedMotionDurationScale * value : value; }
    function withAlpha(value, alpha) {
        if (value === undefined || value === null) return Qt.rgba(0, 0, 0, alpha);
        return Qt.rgba(value.r || 0, value.g || 0, value.b || 0, alpha);
    }
    function glass(value, alpha) { return withAlpha(value, alpha === undefined ? glassPanelAlpha : alpha); }

    function runtimeColor(colors, name, fallback) {
        var value = colors && colors[name] ? colors[name] : fallback;
        return value || fallback;
    }

    function loadRuntimeTheme() {
        try {
            var data = JSON.parse(runtimeThemeFile.text());
            if (data.schema !== "nox-theme-schema-v1" || !data.validation || data.validation.passed !== true) {
                runtimeThemeError = "Rejected invalid wallpaper theme";
                return;
            }
            var colors = data.colors || {};

            // Tonal palette
            tonalBackground = runtimeColor(colors, "background", tonalBackground);
            tonalPrimary = runtimeColor(colors, "primary", tonalPrimary);
            tonalOnPrimary = runtimeColor(colors, "onPrimary", tonalOnPrimary);
            tonalPrimaryContainer = runtimeColor(colors, "primaryContainer", tonalPrimaryContainer);
            tonalOnPrimaryContainer = runtimeColor(colors, "onPrimaryContainer", tonalOnPrimaryContainer);
            tonalSecondary = runtimeColor(colors, "secondary", tonalSecondary);
            tonalOnSecondary = runtimeColor(colors, "onSecondary", tonalOnSecondary);
            tonalSecondaryContainer = runtimeColor(colors, "secondaryContainer", tonalSecondaryContainer);
            tonalOnSecondaryContainer = runtimeColor(colors, "onSecondaryContainer", tonalOnSecondaryContainer);
            tonalTertiary = runtimeColor(colors, "tertiary", tonalTertiary);
            tonalOnTertiary = runtimeColor(colors, "onTertiary", tonalOnTertiary);
            tonalTertiaryContainer = runtimeColor(colors, "tertiaryContainer", tonalTertiaryContainer);
            tonalOnTertiaryContainer = runtimeColor(colors, "onTertiaryContainer", tonalOnTertiaryContainer);
            tonalNeutral = runtimeColor(colors, "neutral", tonalNeutral);
            tonalOnNeutral = runtimeColor(colors, "onNeutral", tonalOnNeutral);
            tonalNeutralContainer = runtimeColor(colors, "neutralContainer", tonalNeutralContainer);
            tonalOnNeutralContainer = runtimeColor(colors, "onNeutralContainer", tonalOnNeutralContainer);
            tonalNeutralVariant = runtimeColor(colors, "neutralVariant", tonalNeutralVariant);
            tonalOnNeutralVariant = runtimeColor(colors, "onNeutralVariant", tonalOnNeutralVariant);

            // Surface ladder
            surfaceSurfaceCanvas = runtimeColor(colors, "surfaceCanvas", surfaceSurfaceCanvas);
            surfaceSurfaceBase = runtimeColor(colors, "surfaceBase", surfaceSurfaceBase);
            surfaceSurface1 = runtimeColor(colors, "surface1", surfaceSurface1);
            surfaceSurface2 = runtimeColor(colors, "surface2", surfaceSurface2);
            surfaceSurface3 = runtimeColor(colors, "surface3", surfaceSurface3);
            surfaceSurfaceFloating = runtimeColor(colors, "surfaceFloating", surfaceSurfaceFloating);
            // Legacy surface aliases
            surfaceSurface = runtimeColor(colors, "surfaceBase", surfaceSurface);
            surfaceSurfaceContainerLow = runtimeColor(colors, "surfaceCanvas", surfaceSurfaceContainerLow);
            surfaceSurfaceContainer = runtimeColor(colors, "surface1", surfaceSurfaceContainer);
            surfaceSurfaceContainerHigh = runtimeColor(colors, "surface2", surfaceSurfaceContainerHigh);
            surfaceSurfaceContainerHighest = runtimeColor(colors, "surface3", surfaceSurfaceContainerHighest);
            surfaceSurfaceVariant = runtimeColor(colors, "surface1", surfaceSurfaceVariant);

            // Text
            textPrimary = runtimeColor(colors, "onBackground", textPrimary);
            textSecondary = runtimeColor(colors, "onSurface", textSecondary);
            textMuted = runtimeColor(colors, "onSurfaceVariant", textMuted);
            textOnPrimary = runtimeColor(colors, "onPrimary", textOnPrimary);
            textOnSurfaceVariant = runtimeColor(colors, "onSurfaceVariant", textOnSurfaceVariant);

            // Outline / border
            outlineDefault = runtimeColor(colors, "outline", outlineDefault);
            outlineSubtle = runtimeColor(colors, "outlineSubtle", outlineSubtle);
            outlineStrong = runtimeColor(colors, "outlineStrong", outlineStrong);
            outlineFocus = runtimeColor(colors, "primary", outlineFocus);

            // State semantic
            stateSuccess = runtimeColor(colors, "success", stateSuccess);
            stateOnSuccess = runtimeColor(colors, "onSuccess", stateOnSuccess);
            stateSuccessContainer = runtimeColor(colors, "successContainer", stateSuccessContainer);
            stateOnSuccessContainer = runtimeColor(colors, "onSuccessContainer", stateOnSuccessContainer);
            stateWarning = runtimeColor(colors, "warning", stateWarning);
            stateOnWarning = runtimeColor(colors, "onWarning", stateOnWarning);
            stateWarningContainer = runtimeColor(colors, "warningContainer", stateWarningContainer);
            stateOnWarningContainer = runtimeColor(colors, "onWarningContainer", stateOnWarningContainer);
            stateDanger = runtimeColor(colors, "error", stateDanger);
            stateOnDanger = runtimeColor(colors, "onError", stateOnDanger);
            stateDangerContainer = runtimeColor(colors, "errorContainer", stateDangerContainer);
            stateOnDangerContainer = runtimeColor(colors, "onErrorContainer", stateOnDangerContainer);
            stateInfo = runtimeColor(colors, "info", stateInfo);
            stateOnInfo = runtimeColor(colors, "onInfo", stateOnInfo);
            stateInfoContainer = runtimeColor(colors, "infoContainer", stateInfoContainer);
            stateOnInfoContainer = runtimeColor(colors, "onInfoContainer", stateOnInfoContainer);

            // Accent interaction states
            if (colors.accent) {
                accentPrimary = runtimeColor(colors.accent, "primary", accentPrimary);
                accentSecondary = runtimeColor(colors.accent, "secondary", accentSecondary);
                accentTertiary = runtimeColor(colors.accent, "tertiary", accentTertiary);
                accentHover = runtimeColor(colors.accent, "hover", accentHover);
                accentPressed = runtimeColor(colors.accent, "pressed", accentPressed);
                accentFocus = runtimeColor(colors.accent, "focus", accentFocus);
            }

            // Effects
            if (data.effects) {
                glassPanelAlpha = Number(data.effects.surfaceOpacity) || glassPanelAlpha;
                glassScrimAlpha = Number(data.effects.scrimOpacity) || glassScrimAlpha;
            }

            // Personality classification
            if (data.selection && data.selection.personality) {
                personalityClass = data.selection.personality.class || personalityClass;
            }

            runtimeThemeHash = data.source && data.source.sha256 ? String(data.source.sha256) : "";
            runtimeThemeError = "";
            currentProfile = "wallpaper-runtime";
        } catch (error) {
            runtimeThemeError = "Wallpaper theme parse error: " + error;
        }
    }

    // Keep the visible chrome and border transitions coherent. Other semantic
    // roles update through the same singleton in the same event turn.
    Behavior on tonalBackground { ColorAnimation { duration: root.duration(380); easing.type: Easing.InOutCubic } }
    Behavior on tonalPrimary { ColorAnimation { duration: root.duration(380); easing.type: Easing.InOutCubic } }
    Behavior on tonalSecondary { ColorAnimation { duration: root.duration(380); easing.type: Easing.InOutCubic } }
    Behavior on tonalTertiary { ColorAnimation { duration: root.duration(380); easing.type: Easing.InOutCubic } }
    Behavior on tonalNeutral { ColorAnimation { duration: root.duration(380); easing.type: Easing.InOutCubic } }
    Behavior on surfaceSurfaceCanvas { ColorAnimation { duration: root.duration(380); easing.type: Easing.InOutCubic } }
    Behavior on surfaceSurfaceBase { ColorAnimation { duration: root.duration(380); easing.type: Easing.InOutCubic } }
    Behavior on surfaceSurface1 { ColorAnimation { duration: root.duration(380); easing.type: Easing.InOutCubic } }
    Behavior on surfaceSurface2 { ColorAnimation { duration: root.duration(380); easing.type: Easing.InOutCubic } }
    Behavior on surfaceSurface3 { ColorAnimation { duration: root.duration(380); easing.type: Easing.InOutCubic } }
    Behavior on surfaceSurfaceFloating { ColorAnimation { duration: root.duration(380); easing.type: Easing.InOutCubic } }
    Behavior on surfaceSurfaceContainerHigh { ColorAnimation { duration: root.duration(380); easing.type: Easing.InOutCubic } }
    Behavior on outlineDefault { ColorAnimation { duration: root.duration(380); easing.type: Easing.InOutCubic } }
    Behavior on accentPrimary { ColorAnimation { duration: root.duration(380); easing.type: Easing.InOutCubic } }
    Behavior on accentSecondary { ColorAnimation { duration: root.duration(380); easing.type: Easing.InOutCubic } }
    Behavior on accentTertiary { ColorAnimation { duration: root.duration(380); easing.type: Easing.InOutCubic } }

    /// Apply a named theme profile, updating all color properties.
    function applyProfile(name) {
        var p = Profiles.getProfile(name);
        if (!p) return;

        // tonals
        tonalBackground             = p.tonals.background;
        tonalPrimary                = p.tonals.primary;
        tonalOnPrimary              = p.tonals.onPrimary;
        tonalPrimaryContainer       = p.tonals.primaryContainer;
        tonalOnPrimaryContainer     = p.tonals.onPrimaryContainer;
        tonalSecondary              = p.tonals.secondary;
        tonalOnSecondary            = p.tonals.onSecondary;
        tonalSecondaryContainer     = p.tonals.secondaryContainer;
        tonalOnSecondaryContainer   = p.tonals.onSecondaryContainer;
        tonalTertiary               = p.tonals.tertiary;
        tonalOnTertiary             = p.tonals.onTertiary;
        tonalTertiaryContainer      = p.tonals.tertiaryContainer;
        tonalOnTertiaryContainer    = p.tonals.onTertiaryContainer;

        // surfaces — fine-grained ladder
        surfaceSurfaceCanvas       = p.surfaces.canvas      || p.surfaces.surface || surfaceSurfaceCanvas;
        surfaceSurfaceBase        = p.surfaces.base       || p.surfaces.surface || surfaceSurfaceBase;
        surfaceSurface1           = p.surfaces.surface     || surfaceSurface1;
        surfaceSurface2           = p.surfaces.surfaceAlt  || surfaceSurface2;
        surfaceSurface3           = p.surfaces.surfaceAlt2 || surfaceSurface3;
        surfaceSurfaceFloating    = p.surfaces.floating   || surfaceSurfaceFloating;
        // legacy aliases
        surfaceSurface              = p.surfaces.surface;
        surfaceSurfaceContainerLow  = p.surfaces.surfaceContainerLow;
        surfaceSurfaceContainer     = p.surfaces.surfaceContainer;
        surfaceSurfaceContainerHigh = p.surfaces.surfaceContainerHigh;
        surfaceSurfaceContainerHighest = p.surfaces.surfaceContainerHighest;
        surfaceSurfaceVariant       = p.surfaces.surfaceVariant;
        surfaceInverseSurface       = p.surfaces.inverseSurface;
        surfaceInverseOnSurface     = p.surfaces.inverseOnSurface;

        // neutral palette
        tonalNeutral             = p.neutral ? (p.neutral.primary || tonalNeutral) : tonalNeutral;
        tonalOnNeutral           = p.neutral ? (p.neutral.onPrimary || tonalOnNeutral) : tonalOnNeutral;
        tonalNeutralContainer    = p.neutral ? (p.neutral.container || tonalNeutralContainer) : tonalNeutralContainer;
        tonalOnNeutralContainer  = p.neutral ? (p.neutral.onContainer || tonalOnNeutralContainer) : tonalOnNeutralContainer;

        // text
        textPrimary                 = p.text.primary;
        textSecondary               = p.text.secondary;
        textMuted                   = p.text.muted;
        textDisabled               = p.text.disabled;
        textOnPrimary              = p.text.onPrimary;
        textOnSecondary            = p.text.onSecondary;
        textOnSurfaceVariant       = p.text.onSurfaceVariant;

        // outline
        outlineDefault             = p.outline.default;
        outlineSubtle              = p.outline.subtle;
        outlineStrong              = p.outline.strong;
        outlineFocus               = p.outline.focus;

        // state
        stateSuccess               = p.state.success;
        stateOnSuccess             = p.state.onSuccess;
        stateSuccessContainer      = p.state.successContainer || stateSuccessContainer;
        stateOnSuccessContainer    = p.state.onSuccessContainer || stateOnSuccessContainer;
        stateWarning               = p.state.warning;
        stateOnWarning             = p.state.onWarning;
        stateWarningContainer      = p.state.warningContainer || stateWarningContainer;
        stateOnWarningContainer    = p.state.onWarningContainer || stateOnWarningContainer;
        stateDanger                = p.state.danger;
        stateOnDanger              = p.state.onDanger;
        stateDangerContainer       = p.state.dangerContainer || stateDangerContainer;
        stateOnDangerContainer     = p.state.onDangerContainer || stateOnDangerContainer;
        stateInfo                  = p.state.info;
        stateOnInfo                = p.state.onInfo;
        stateInfoContainer         = p.state.infoContainer || stateInfoContainer;
        stateOnInfoContainer       = p.state.onInfoContainer || stateOnInfoContainer;
        stateHoverOverlay          = p.state.hoverOverlay;
        statePressedOverlay        = p.state.pressedOverlay;
        stateFocusOverlay          = p.state.focusOverlay;
        stateDisabledOverlay       = p.state.disabledOverlay;

        // accent interaction states
        accentPrimary              = p.accent ? (p.accent.primary || accentPrimary) : accentPrimary;
        accentSecondary            = p.accent ? (p.accent.secondary || accentSecondary) : accentSecondary;
        accentTertiary             = p.accent ? (p.accent.tertiary || accentTertiary) : accentTertiary;
        accentHover                = p.accent ? (p.accent.hover || accentHover) : accentHover;
        accentPressed              = p.accent ? (p.accent.pressed || accentPressed) : accentPressed;
        accentFocus                = p.accent ? (p.accent.focus || accentFocus) : accentFocus;

        currentProfile = name;
    }

    /// Apply a corner radius (in scaled pixels) atomically. Updates every
    /// radius step that depends on the base radius so the visual output and
    /// the displayed appearanceRadius label never diverge.
    function applyRadius(px) {
        var clamped = Math.max(0, Math.min(36, Math.round(Number(px) || 0)));
        radiusNone = 0;
        radiusXs = 4;
        radiusSm = 8;
        radiusMd = clamped;
        radiusLg = Math.min(clamped + 4, 28);
        radiusXl = Math.min(clamped + 8, 36);
        appearanceRadius = clamped;
    }
}
