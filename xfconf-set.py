#!/usr/bin/env python3
"""Set Xfce settings (xfconf) for the current user by editing the channel XML directly.

xfconf-query needs a running Xfce session (xfconfd on the session bus), which a fresh install
or an SSH shell does not have. This writes ~/.config/xfce4/xfconf/xfce-perchannel-xml/CHANNEL.xml
instead; xfconfd reads it at the next Xfce login, on top of the system defaults in /etc/xdg.
Refuses to run while xfconfd is up: it would overwrite the file from memory on its next save.

Usage, as the desktop user (the xrdp-*.sh scripts pipe this file into python3 -I -):
  xfconf-set.py CHANNEL PROPERTY TYPE VALUE [PROPERTY TYPE VALUE ...]
  xfconf-set.py CHANNEL --copy FROM TO ...
TYPE is bool, int, uint, double or string; add [] for an array of comma-separated values
(double[] 0,0,0,1). --copy copies the FROM subtree (user file first, else /etc/xdg) to TO,
only if TO does not exist yet. Operations run in order.
"""
import copy
import os
import subprocess
import sys
import xml.etree.ElementTree as ET

TYPES = {"bool", "int", "uint", "double", "string"}


def die(msg):
    sys.exit(f"xfconf-set: {msg}")


def channel_path(config_dir, channel):
    return os.path.join(config_dir, "xfce4", "xfconf", "xfce-perchannel-xml", channel + ".xml")


def load(path, channel):
    if os.path.exists(path):
        return ET.parse(path).getroot()
    return ET.Element("channel", name=channel, version="1.0")


def child(node, name):
    return next((c for c in node.findall("property") if c.get("name") == name), None)


def find(root, prop):
    node = root
    for part in prop.strip("/").split("/"):
        node = child(node, part)
        if node is None:
            return None
    return node


def make(root, prop):
    """Find PROP, creating it and any missing parents as empty-typed properties."""
    node = root
    for part in prop.strip("/").split("/"):
        sub = child(node, part)
        if sub is None:
            sub = ET.SubElement(node, "property", name=part, type="empty")
        node = sub
    return node


def set_prop(root, prop, typ, value):
    is_array = typ.endswith("[]")
    base = typ[:-2] if is_array else typ
    if base not in TYPES:
        die(f"unknown type '{typ}' for {prop}")
    node = make(root, prop)
    # Child properties (e.g. a shortcut's startup-notify) stay; old array values go.
    for v in node.findall("value"):
        node.remove(v)
    node.attrib.pop("value", None)
    if is_array:
        node.set("type", "array")
        for i, item in enumerate(value.split(",")):
            node.insert(i, ET.Element("value", type=base, value=item))
    else:
        node.set("type", base)
        node.set("value", value)


def copy_tree(root, system, src, dst):
    if find(root, dst) is not None:
        return
    tree = find(root, src)
    if tree is None:
        tree = find(system, src)
    if tree is None:
        return
    parent_path, _, name = dst.strip("/").rpartition("/")
    parent = make(root, parent_path) if parent_path else root
    new = copy.deepcopy(tree)
    new.set("name", name)
    parent.append(new)


def main():
    if len(sys.argv) < 3:
        die("usage: xfconf-set.py CHANNEL PROPERTY TYPE VALUE ... (see the file header)")
    channel, ops = sys.argv[1], sys.argv[2:]
    running = subprocess.run(["pgrep", "-u", str(os.getuid()), "-x", "xfconfd"],
                             stdout=subprocess.DEVNULL).returncode == 0
    if running:
        die("an Xfce session is running (xfconfd). Log out of the RDP session and run again.")

    config_dir = os.environ.get("XDG_CONFIG_HOME") or os.path.expanduser("~/.config")
    path = channel_path(config_dir, channel)
    root = load(path, channel)
    system = load(channel_path("/etc/xdg", channel), channel)

    i = 0
    while i < len(ops):
        if len(ops) - i < 3:
            die(f"incomplete operation: {' '.join(ops[i:])}")
        if ops[i] == "--copy":
            copy_tree(root, system, ops[i + 1], ops[i + 2])
        else:
            set_prop(root, *ops[i:i + 3])
        i += 3

    os.makedirs(os.path.dirname(path), exist_ok=True)
    ET.indent(root, space="  ")
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        f.write('<?xml version="1.0" encoding="UTF-8"?>\n\n')
        f.write(ET.tostring(root, encoding="unicode"))
        f.write("\n")
    os.replace(tmp, path)


if __name__ == "__main__":
    main()
