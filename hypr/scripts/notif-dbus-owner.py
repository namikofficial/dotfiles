#!/usr/bin/env python3
import json
import os
import shlex
import signal
import subprocess
import sys

from gi.repository import Gio, GLib


BUS_NAME = "org.freedesktop.Notifications"
OBJ_PATH = "/org/freedesktop/Notifications"
IFACE = "org.freedesktop.Notifications"

LOG_HELPER = os.path.expanduser("~/.config/hypr/scripts/lib/log.sh")
SOUND_HELPER = os.path.expanduser("~/.config/hypr/scripts/notify-sound.sh")
STATE_FILE = os.path.expanduser("~/.cache/hypr/notif/state.json")

_next_id = 1
_loop = None
_reg_id = 0


INTROSPECTION_XML = """<node>
  <interface name="org.freedesktop.Notifications">
    <method name="GetCapabilities">
      <arg direction="out" type="as"/>
    </method>
    <method name="Notify">
      <arg direction="in" type="s" name="app_name"/>
      <arg direction="in" type="u" name="replaces_id"/>
      <arg direction="in" type="s" name="app_icon"/>
      <arg direction="in" type="s" name="summary"/>
      <arg direction="in" type="s" name="body"/>
      <arg direction="in" type="as" name="actions"/>
      <arg direction="in" type="a{sv}" name="hints"/>
      <arg direction="in" type="i" name="expire_timeout"/>
      <arg direction="out" type="u" name="id"/>
    </method>
    <method name="CloseNotification">
      <arg direction="in" type="u" name="id"/>
    </method>
    <method name="GetServerInformation">
      <arg direction="out" type="s" name="name"/>
      <arg direction="out" type="s" name="vendor"/>
      <arg direction="out" type="s" name="version"/>
      <arg direction="out" type="s" name="spec_version"/>
    </method>
    <signal name="NotificationClosed">
      <arg type="u" name="id"/>
      <arg type="u" name="reason"/>
    </signal>
    <signal name="ActionInvoked">
      <arg type="u" name="id"/>
      <arg type="s" name="action_key"/>
    </signal>
  </interface>
</node>
"""


def dnd_enabled() -> bool:
  try:
    with open(STATE_FILE, "r", encoding="utf-8") as f:
      state = json.load(f)
    return bool(state.get("dnd", False))
  except Exception:
    return False


def unwrap_variant(value):
  if isinstance(value, GLib.Variant):
    return value.unpack()
  return value


def severity_from_hints(hints) -> str:
  urgency = hints.get("urgency", 1)
  urgency = unwrap_variant(urgency)
  if isinstance(urgency, bytes) and urgency:
    urgency = urgency[0]
  try:
    urgency = int(urgency)
  except Exception:
    urgency = 1

  if urgency >= 2:
    return "error"
  if urgency == 0:
    return "info"
  return "warn"


def sound_kind_from_hints(hints) -> str:
  urgency = hints.get("urgency", 1)
  urgency = unwrap_variant(urgency)
  if isinstance(urgency, bytes) and urgency:
    urgency = urgency[0]
  try:
    urgency = int(urgency)
  except Exception:
    urgency = 1

  if urgency >= 2:
    return "critical"
  if urgency == 0:
    return "system"
  return "message"


def play_sound(hints) -> None:
  if not os.path.isfile(SOUND_HELPER) or not os.access(SOUND_HELPER, os.X_OK):
    return

  try:
    subprocess.Popen(
      [SOUND_HELPER, sound_kind_from_hints(hints or {})],
      stdout=subprocess.DEVNULL,
      stderr=subprocess.DEVNULL,
      start_new_session=True,
    )
  except Exception:
    pass


def emit_event(app_name: str, summary: str, body: str, hints) -> None:
  if not os.path.isfile(LOG_HELPER) or not os.access(LOG_HELPER, os.X_OK):
    return

  if dnd_enabled():
    return

  severity = severity_from_hints(hints)
  title = summary.strip() or app_name.strip() or "Notification"
  component = app_name.strip() or "dbus-notify"
  payload = "\n".join(x for x in [summary.strip(), body.strip()] if x).strip()

  cmd = [
    LOG_HELPER,
    "--emit",
    severity,
    component[:80],
    title[:240],
    body[:2000],
    "",
    payload[:4000],
  ]
  try:
    subprocess.run(cmd, check=False, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
  except Exception:
    pass

  play_sound(hints)


def on_method_call(
  connection,
  sender,
  object_path,
  interface_name,
  method_name,
  parameters,
  invocation,
):
  global _next_id

  if method_name == "GetCapabilities":
    invocation.return_value(GLib.Variant("(as)", (["body", "body-markup"],)))
    return

  if method_name == "GetServerInformation":
    invocation.return_value(GLib.Variant("(ssss)", ("Noxflow Eww Notify", "Noxflow", "1.0", "1.2")))
    return

  if method_name == "CloseNotification":
    invocation.return_value(None)
    return

  if method_name == "Notify":
    (
      app_name,
      replaces_id,
      app_icon,
      summary,
      body,
      actions,
      hints,
      expire_timeout,
    ) = parameters.unpack()

    emit_event(str(app_name), str(summary), str(body), hints or {})

    if replaces_id and int(replaces_id) > 0:
      notif_id = int(replaces_id)
    else:
      notif_id = _next_id
      _next_id += 1

    invocation.return_value(GLib.Variant("(u)", (notif_id,)))
    return

  invocation.return_dbus_error(
    "org.freedesktop.DBus.Error.UnknownMethod",
    f"Unknown method: {method_name}",
  )


def on_bus_acquired(connection, name):
  global _reg_id
  node_info = Gio.DBusNodeInfo.new_for_xml(INTROSPECTION_XML)
  iface_info = node_info.interfaces[0]
  vtable = Gio.DBusInterfaceVTable(method_call=on_method_call)
  _reg_id = connection.register_object(OBJ_PATH, iface_info, vtable, None)


def on_name_lost(_connection, _name):
  if _loop is not None:
    _loop.quit()


def _handle_term(_signum, _frame):
  if _loop is not None:
    _loop.quit()


def main() -> int:
  global _loop
  signal.signal(signal.SIGTERM, _handle_term)
  signal.signal(signal.SIGINT, _handle_term)

  _loop = GLib.MainLoop()
  Gio.bus_own_name(
    Gio.BusType.SESSION,
    BUS_NAME,
    Gio.BusNameOwnerFlags.NONE,
    on_bus_acquired,
    None,
    on_name_lost,
  )
  _loop.run()
  return 0


if __name__ == "__main__":
  sys.exit(main())
