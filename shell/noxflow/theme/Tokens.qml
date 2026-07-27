pragma Singleton
import QtQml

QtObject {
    id: root

    // appearance
    readonly property string appearanceMode: "dark"
    readonly property string appearanceDensity: "comfortable"
    readonly property int appearanceRadius: 14
    readonly property string appearanceMotion: "fluid"
    readonly property string appearanceTransparency: "balanced"

    // tonal
    readonly property color tonalBackground: "#090B10"
    readonly property color tonalPrimary: "#8FA8FF"
    readonly property color tonalOnPrimary: "#101A3A"
    readonly property color tonalPrimaryContainer: "#293A75"
    readonly property color tonalOnPrimaryContainer: "#DCE3FF"
    readonly property color tonalSecondary: "#7CE0D3"
    readonly property color tonalOnSecondary: "#08201D"
    readonly property color tonalSecondaryContainer: "#20504A"
    readonly property color tonalOnSecondaryContainer: "#B8F3EA"
    readonly property color tonalTertiary: "#D4B6F2"
    readonly property color tonalOnTertiary: "#261334"
    readonly property color tonalTertiaryContainer: "#503A68"
    readonly property color tonalOnTertiaryContainer: "#EFDFFF"

    // surface
    readonly property color surfaceSurface: "#11141C"
    readonly property color surfaceSurfaceContainerLow: "#0E1117"
    readonly property color surfaceSurfaceContainer: "#181C27"
    readonly property color surfaceSurfaceContainerHigh: "#222838"
    readonly property color surfaceSurfaceContainerHighest: "#2C3344"
    readonly property color surfaceSurfaceVariant: "#303749"
    readonly property color surfaceInverseSurface: "#E1E5EF"
    readonly property color surfaceInverseOnSurface: "#282B33"

    // text
    readonly property color textPrimary: "#F2F5FA"
    readonly property color textSecondary: "#D7DEEA"
    readonly property color textMuted: "#9EA8B8"
    readonly property color textDisabled: "#687181"
    readonly property color textOnPrimary: "#101A3A"
    readonly property color textOnSecondary: "#08201D"
    readonly property color textOnSurfaceVariant: "#C0C8D8"

    // outline
    readonly property color outlineDefault: "#596276"
    readonly property color outlineSubtle: "#303749"
    readonly property color outlineStrong: "#AAB5C9"
    readonly property color outlineFocus: "#B8C7FF"

    // state
    readonly property color stateSuccess: "#7ADFA4"
    readonly property color stateOnSuccess: "#092616"
    readonly property color stateWarning: "#F2C66D"
    readonly property color stateOnWarning: "#2B2107"
    readonly property color stateDanger: "#FF7993"
    readonly property color stateOnDanger: "#3A0713"
    readonly property color stateInfo: "#8DC9FF"
    readonly property color stateOnInfo: "#08233A"
    readonly property color stateHoverOverlay: "#FFFFFF"
    readonly property color statePressedOverlay: "#000000"
    readonly property color stateFocusOverlay: "#B8C7FF"
    readonly property color stateDisabledOverlay: "#FFFFFF"

    // spacing
    readonly property int spacingNone: 0
    readonly property int spacingXs: 4
    readonly property int spacingSm: 8
    readonly property int spacingMd: 12
    readonly property int spacingLg: 16
    readonly property int spacingXl: 24
    readonly property int spacingXxl: 32
    readonly property int spacingSection: 40

    // radius
    readonly property int radiusNone: 0
    readonly property int radiusXs: 4
    readonly property int radiusSm: 8
    readonly property int radiusMd: 12
    readonly property int radiusLg: 16
    readonly property int radiusXl: 24
    readonly property int radiusPill: 999

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
    readonly property int heightToolbar: 56

    // reduced_motion
    readonly property bool reducedMotionEnabled: false
    readonly property real reducedMotionDurationScale: 0.0
    readonly property bool reducedMotionDisableBlur: true
    readonly property bool reducedMotionDisableScale: true

    property string activeDensity: appearanceDensity
    property bool reducedMotion: reducedMotionEnabled
    function scale(value, density) { return value * (density === "compact" ? 0.9 : density === "spacious" ? 1.1 : 1.0); }
    function scaled(value) { return scale(value, activeDensity); }
    function duration(value) { return reducedMotion ? reducedMotionDurationScale * value : value; }
    function withAlpha(value, alpha) { return Qt.rgba(value.r, value.g, value.b, alpha); }
}
