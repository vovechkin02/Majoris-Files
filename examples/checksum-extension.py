#!/usr/bin/python3
"""Example installed user service; never imported into the Files process."""
import hashlib
import os
import pathlib
import stat
import urllib.parse
from gi.repository import Gio, GLib

INTERFACE = '''<node><interface name="com.majoris.Files.Extension1">
<method name="GetVersion"><arg type="u" direction="out"/></method>
<method name="GetActions"><arg type="as" direction="in"/><arg type="a(ss)" direction="out"/></method>
<method name="Activate"><arg type="s" direction="in"/><arg type="as" direction="in"/></method>
<method name="GetFileInfo"><arg type="s" direction="in"/><arg type="a{ss}" direction="out"/></method>
<method name="GetColumns"><arg type="a(ss)" direction="out"/></method>
<method name="GetProperties"><arg type="s" direction="in"/><arg type="a(ss)" direction="out"/></method>
</interface></node>'''


def local(uri):
    parsed = urllib.parse.urlsplit(uri)
    if parsed.scheme != 'file' or parsed.netloc not in ('', 'localhost'):
        raise ValueError('This example accepts local files only')
    return pathlib.Path(urllib.parse.unquote(parsed.path))


def eligible(uris):
    try:
        return bool(uris) and len(uris) <= 10 and all(
            stat.S_ISREG(local(uri).lstat().st_mode) and local(uri).lstat().st_size <= 16 * 1024 * 1024
            and not pathlib.Path(str(local(uri)) + '.sha256').exists() for uri in uris)
    except (OSError, ValueError):
        return False


def method(connection, sender, path, interface, name, parameters, invocation):
    try:
        args = parameters.unpack()
        if name == 'GetVersion':
            invocation.return_value(GLib.Variant('(u)', (1,)))
        elif name == 'GetActions':
            invocation.return_value(GLib.Variant('(a(ss))', ([('checksum', 'Create SHA-256 Sidecar')] if eligible(args[0]) else [],)))
        elif name == 'GetColumns':
            invocation.return_value(GLib.Variant('(a(ss))', ([('Bytes', 'Bytes'), ('Extension', 'Extension')],)))
        elif name == 'GetFileInfo':
            source = local(args[0])
            invocation.return_value(GLib.Variant('(a{ss})', ({'Bytes': str(source.lstat().st_size), 'Extension': source.suffix},)))
        elif name == 'GetProperties':
            invocation.return_value(GLib.Variant('(a(ss))', ([('Provider', 'Isolated checksum example'), ('Sidecar', str(local(args[0])) + '.sha256')],)))
        elif name == 'Activate':
            if args[0] != 'checksum' or not eligible(args[1]):
                raise ValueError('The requested action is unavailable')
            for uri in args[1]:
                source = local(uri)
                descriptor = os.open(source, os.O_RDONLY | os.O_NOFOLLOW)
                digest, count = hashlib.sha256(), 0
                with os.fdopen(descriptor, 'rb') as stream:
                    if not stat.S_ISREG(os.fstat(stream.fileno()).st_mode):
                        raise ValueError('Not a regular file')
                    while block := stream.read(65536):
                        count += len(block)
                        if count > 16 * 1024 * 1024:
                            raise ValueError('Example size limit exceeded')
                        digest.update(block)
                descriptor = os.open(str(source) + '.sha256', os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
                with os.fdopen(descriptor, 'w') as stream:
                    stream.write(digest.hexdigest() + '  ' + source.name + '\n')
            invocation.return_value(None)
        else:
            invocation.return_dbus_error('com.majoris.Files.Extension1.UnknownMethod', 'Unknown method')
    except Exception as error:
        invocation.return_dbus_error('com.majoris.Files.Extension1.Failed', str(error))


loop = GLib.MainLoop()


def acquired(connection, name):
    connection.register_object('/com/majoris/Files/ExampleChecksum', Gio.DBusNodeInfo.new_for_xml(INTERFACE).interfaces[0], method, None, None)


Gio.bus_own_name(Gio.BusType.SESSION, 'com.majoris.Files.ExampleChecksum', Gio.BusNameOwnerFlags.NONE, acquired, None, lambda *args: loop.quit())
loop.run()
