pragma Singleton
import QtQml
import QtQuick
import "ThemeProfiles.js" as Profiles

QtObject {
    id: root

    // ── Current active profile name ──
    property string currentProfile: "material-expressive"

    // appearance (config-level, not per-profile)
    readonly property string appearanceMode: "dark"
    readonly property string appearanceDensity: "comfortable"
    readonly property int appearanceRadius: 14
    readonly property string appearanceMotion: "fluid"
    readonly property string appearanceTransparency: "balanced"

    // ── Tonal (writable — switched by applyProfile) ──
    property color tonalBackground: "#090B10"
    property color tonalPrimary: "#8FA8FF"
    property color tonalOnPrimary: "#101A3A"
    property color tonalPrimaryContainer: "#293A75"
    property color tonalOnPrimaryContainer: "#DCE3FF"
    property color tonalSecondary: "#7CE0D3"
    property color tonalOnSecondary: "#08201D"
    property color tonalSecondaryContainer: "#20504A"
    property color tonalOnSecondaryContainer: "#B8F3EA"
    property color tonalTertiary: "#D4B6F2"
    property color tonalOnTertiary: "#261334"
    property color tonalTertiaryContainer: "#503A68"
    property color tonalOnTertiaryContainer: "#EFDFFF"

    // ── Surface (writable) ──
    property color surfaceSurface: "#11141C"
    property color surfaceSurfaceContainerLow: "#0E1117"
    property color surfaceSurfaceContainer: "#181C27"
    property color surfaceSurfaceContainerHigh: "#222838"
    property color surfaceSurfaceContainerHighest: "#2C3344"
    property color surfaceSurfaceVariant: "#303749"
    property color surfaceInverseSurface: "#E1E5EF"
    property color surfaceInverseOnSurface: "#282B33"

    // ── Text (writable) ──
    property color textPrimary: "#F2F5FA"
    property color textSecondary: "#D7DEEA"
    property color textMuted: "#9EA8B8"
    property color textDisabled: "#687181"
    property color textOnPrimary: "#101A3A"
    property color textOnSecondary: "#08201D"
    property color textOnSurfaceVariant: "#C0C8D8"

    // ── Outline (writable) ──
    property color outlineDefault: "#596276"
    property color outlineSubtle: "#303749"
    property color outlineStrong: "#AAB5C9"
    property color outlineFocus: "#B8C7FF"

    // ── State (writable) ──
    property color stateSuccess: "#7ADFA4"
    property color stateOnSuccess: "#092616"
    property color stateWarning: "#F2C66D"
    property color stateOnWarning: "#2B2107"
    property color stateDanger: "#FF7993"
    property color stateOnDanger: "#3A0713"
    property color stateInfo: "#8DC9FF"
    property color stateOnInfo: "#08233A"
    property color stateHoverOverlay: "#FFFFFF"
    property color statePressedOverlay: "#000000"
    property color stateFocusOverlay: "#B8C7FF"
    property color stateDisabledOverlay: "#FFFFFF"

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

    // blur
    readonly property int blurNone: 0
    readonly property int blurSubtle: 8
    readonly property int blurMedium: 16
    readonly property int blurStrong: 28

    // height
    readonly property int heightIconButton: 40
    readonly property int heightButton: 40
    readonly property int heightControl: 44
    readonly property int heightField: 48
    readonly property int heightChip: 32
    // Keep the persistent bar thin; panels use their own control metrics.
    readonly property int heightToolbar: 40

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

        // surfaces
        surfaceSurface              = p.surfaces.surface;
        surfaceSurfaceContainerLow  = p.surfaces.surfaceContainerLow;
        surfaceSurfaceContainer     = p.surfaces.surfaceContainer;
        surfaceSurfaceContainerHigh = p.surfaces.surfaceContainerHigh;
        surfaceSurfaceContainerHighest = p.surfaces.surfaceContainerHighest;
        surfaceSurfaceVariant       = p.surfaces.surfaceVariant;
        surfaceInverseSurface       = p.surfaces.inverseSurface;
        surfaceInverseOnSurface     = p.surfaces.inverseOnSurface;

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
        stateWarning               = p.state.warning;
        stateOnWarning             = p.state.onWarning;
        stateDanger                 = p.state.danger;
        stateOnDanger               = p.state.onDanger;
        stateInfo                   = p.state.info;
        stateOnInfo                 = p.state.onInfo;
        stateHoverOverlay           = p.state.hoverOverlay;
        statePressedOverlay         = p.state.pressedOverlay;
        stateFocusOverlay           = p.state.focusOverlay;
        stateDisabledOverlay        = p.state.disabledOverlay;

        currentProfile = name;
    }
}
