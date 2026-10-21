#!/usr/bin/python3
"""Runs only inside the Files preview sandbox with a private /tmp and no network."""
import os
import pathlib
import subprocess
import sys
import time
import shutil
import uno
from com.sun.star.beans import PropertyValue


def prop(name, value):
    item = PropertyValue()
    item.Name, item.Value = name, value
    return item


def main():
    profile = pathlib.Path('/tmp/profile')
    profile.mkdir(mode=0o700)
    env = dict(os.environ, SAL_USE_VCLPLUGIN='svp')
    process = subprocess.Popen([
        '/usr/bin/soffice', '--headless', '--nologo', '--nodefault', '--norestore',
        '-env:UserInstallation=file:///tmp/profile',
        '--accept=pipe,name=majoris_render;urp;StarOffice.ComponentContext',
    ], env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    desktop = document = None
    try:
        context = uno.getComponentContext()
        resolver = context.ServiceManager.createInstanceWithContext('com.sun.star.bridge.UnoUrlResolver', context)
        deadline = time.monotonic() + 15
        while True:
            try:
                remote = resolver.resolve('uno:pipe,name=majoris_render;urp;StarOffice.ComponentContext')
                break
            except Exception:
                if process.poll() is not None or time.monotonic() >= deadline:
                    raise RuntimeError('Document renderer did not start')
                time.sleep(0.1)
        desktop = remote.ServiceManager.createInstanceWithContext('com.sun.star.frame.Desktop', remote)
        extension = sys.argv[1] if len(sys.argv) == 2 else 'bin'
        if extension not in {'docx', 'xlsx', 'pptx', 'odt', 'ods', 'odp', 'doc', 'xls', 'ppt'}:
            raise RuntimeError('Unsupported document extension')
        local = pathlib.Path('/tmp/input.' + extension)
        shutil.copyfile('/input', local)
        document = desktop.loadComponentFromURL(local.as_uri(), '_blank', 0, (
            prop('Hidden', True), prop('ReadOnly', True),
            prop('MacroExecutionMode', 0), prop('UpdateDocMode', 0),
        ))
        if document is None:
            raise RuntimeError('Unsupported document')
        if document.supportsService('com.sun.star.sheet.SpreadsheetDocument'):
            filter_name = 'calc_pdf_Export'
        elif document.supportsService('com.sun.star.presentation.PresentationDocument'):
            filter_name = 'impress_pdf_Export'
        else:
            filter_name = 'writer_pdf_Export'
        document.storeToURL('file:///tmp/rendered.pdf', (
            prop('FilterName', filter_name), prop('Overwrite', False),
            prop('FilterData', uno.Any('[]com.sun.star.beans.PropertyValue', (
                prop('ExportBookmarks', False), prop('ExportFormFields', False),
                prop('ExportLinksRelativeFsys', False), prop('ExportNotes', False),
            ))),
        ))
        output = pathlib.Path('/tmp/rendered.pdf')
        if output.stat().st_size > 64 * 1024 * 1024:
            raise RuntimeError('Rendered document exceeds the preview limit')
        with output.open('rb') as stream:
            while chunk := stream.read(65536):
                sys.stdout.buffer.write(chunk)
    finally:
        if document is not None:
            document.close(True)
        if desktop is not None:
            desktop.terminate()
        if process.poll() is None:
            try:
                process.terminate()
            except ProcessLookupError:
                pass
        try:
            process.wait(timeout=2)
        except subprocess.TimeoutExpired:
            process.kill()


if __name__ == '__main__':
    main()
