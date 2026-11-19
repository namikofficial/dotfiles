.pragma library

// Recognize screen-cast producer nodes. The xdg-desktop-portal-wlr stream
// properties are also used by the Hyprland portal backend; camera-role nodes
// must never be mistaken for screen sharing.
function screenCaptureActive(output) {
    var nodes = JSON.parse(String(output || ""));
    if (!Array.isArray(nodes)) throw new Error("PipeWire dump is not an array");

    for (var i = 0; i < nodes.length; i++) {
        var node = nodes[i];
        if (!node || node.type !== "PipeWire:Interface:Node" || !node.info
                || node.info.state !== "running") continue;

        var props = node.info.props || {};
        if (props["media.class"] !== "Video/Source") continue;

        var role = String(props["media.role"] || "");
        if (role === "Screen") return true;
        if (role !== "") continue;

        var nodeName = String(props["node.name"] || "");
        var mediaName = String(props["media.name"] || "");
        if (nodeName.indexOf("xdg-desktop-portal") === 0
                && mediaName.indexOf("xdpw-stream-") === 0) return true;
    }

    return false;
}
