import { readFileSync } from "fs";
import { fileURLToPath } from "url";
import { dirname, join } from "path";

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);
// __dirname is shell/noxflow/tests
// NOXFLOW_ROOT is shell/noxflow (the project root for these tests)
const NOXFLOW_ROOT = join(__dirname, "..");

// ── NF-17: Clipboard copy must not introduce unsupported daemon action ──
// ClipboardPanel.qml uses wl-copy directly for clipboard writes. The daemon
// IPC contract has no clipboard_copy action. This test verifies the copy path
// uses wl-copy and does NOT send clipboard_copy via runAction.
function testClipboardCopyContract() {
    const panel = readFileSync(join(NOXFLOW_ROOT, "surfaces/clipboard/ClipboardPanel.qml"), "utf8");

    // Must use wl-copy for clipboard writes
    if (!panel.includes("wl-copy")) {
        throw new Error("ClipboardPanel must use wl-copy for clipboard writes");
    }

    // Must NOT send clipboard_copy action to daemon
    if (panel.includes("runAction({") && panel.includes("clipboard_copy")) {
        throw new Error("ClipboardPanel must not send clipboard_copy via runAction - use wl-copy instead");
    }

    // copyEntry function must exist and guard against empty entry
    if (!panel.includes("function copyEntry(entry)")) {
        throw new Error("ClipboardPanel must have copyEntry function");
    }

    // copyEntry must check for null/empty entry
    const copyEntryMatch = panel.match(/function copyEntry\(entry\)[\s\S]*?\{[\s\S]*?\}/);
    if (!copyEntryMatch || !copyEntryMatch[0].includes("if (!entry || !entry.text)")) {
        throw new Error("copyEntry must guard against null/empty entry");
    }

    console.log("  clipboard copy contract checks passed");
}

// ── NF-20: QuickShare must use stable device ID, not array index ──
// selectedDeviceIndex is racy when devices reorder between selection and send.
// The fix captures selectedDeviceId at selection time and validates presence
// before sending, using a stable string ID rather than array position.
function testQuickShareStableIdentity() {
    const share = readFileSync(join(NOXFLOW_ROOT, "surfaces/share/QuickShareContent.qml"), "utf8");

    // Must use selectedDeviceId (string) not selectedDeviceIndex (int)
    if (share.includes("property int selectedDeviceIndex")) {
        throw new Error("QuickShareContent must not use selectedDeviceIndex int - use selectedDeviceId string for stable identity");
    }

    // Must have selectedDeviceId property of type string
    if (!share.includes("property string selectedDeviceId")) {
        throw new Error("QuickShareContent must have property string selectedDeviceId");
    }

    // TapHandler must capture modelData.id, not array index
    const tapHandlerMatch = share.match(/onTapped:\s*root\.selectedDeviceId\s*=/);
    if (!tapHandlerMatch) {
        throw new Error("QuickShareContent TapHandler must capture modelData.id as selectedDeviceId");
    }

    // sendFiles must check selectedDeviceId (string), not index
    if (!share.includes("!root.selectedDeviceId")) {
        throw new Error("QuickShareContent sendFiles must guard on selectedDeviceId");
    }

    // onExited handler must verify device is still present by ID before sending
    if (!share.includes("deviceStillPresent") || !share.includes("selectedDeviceId")) {
        throw new Error("QuickShareContent onExited must verify device still present by ID");
    }

    // The send call must use selectedDeviceId, not devices[index].id
    if (share.includes("transfer.send(root.transfer.devices[") ||
        share.includes("transfer.send(root.transfer.devices[root.selectedDeviceIndex]")) {
        throw new Error("QuickShareContent must not send using devices[index] - use captured selectedDeviceId");
    }

    console.log("  quick share stable identity checks passed");
}

// ── NF-17: ClipboardModel persistence and error handling ──
// ClipboardModel must handle first-run (missing file), corrupt JSON, and
// ensure directory exists before saving. Duplicate entries must not lose data.
function testClipboardModelPersistence() {
    const model = readFileSync(join(NOXFLOW_ROOT, "ClipboardModel.qml"), "utf8");

    // Must have storagePath and storageDir
    if (!model.includes("storagePath") || !model.includes("storageDir")) {
        throw new Error("ClipboardModel must have storagePath and storageDir properties");
    }

    // addEntry must handle duplicate text by updating timestamp, not skipping
    const addEntryMatch = model.match(/function addEntry[\s\S]*?\{[\s\S]*?\}/);
    if (!addEntryMatch || !addEntryMatch[0].includes("timestamp = Date.now()")) {
        throw new Error("ClipboardModel addEntry must update timestamp on duplicate");
    }

    // save() must use try/catch to avoid crashing on write errors
    if (!model.includes("try {") || !model.includes("catch")) {
        throw new Error("ClipboardModel save() must use try/catch for error handling");
    }

    // onLoadFailed must create directory, not silently fail
    if (!model.includes("ensureDirProcess") || !model.includes("mkdir")) {
        throw new Error("ClipboardModel must create storage directory on load failure");
    }

    console.log("  clipboard model persistence checks passed");
}

console.log("testing clipboard and share contract...");

testClipboardCopyContract();
testQuickShareStableIdentity();
testClipboardModelPersistence();

console.log("all clipboard/share contract tests passed");
