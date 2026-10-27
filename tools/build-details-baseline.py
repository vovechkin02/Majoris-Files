"""Build committed Files with current native instrumentation, without editing it."""
import io
import os
from pathlib import Path
import subprocess
import tarfile

root=Path(__file__).resolve().parents[1]
source=root/'build/details-before-source'
source.mkdir(exist_ok=True)
revision=subprocess.check_output(['git','rev-parse',os.environ.get('MAJORIS_BASELINE_REVISION','dee2dd12de6e24e03abe13f14a98db8838b1367f')],cwd=root,text=True).strip()
archive=subprocess.check_output(['git','archive',revision],cwd=root)
with tarfile.open(fileobj=io.BytesIO(archive)) as files:
    files.extractall(source,filter='data')
for name in ('details-corrections.vala','native-evidence.vala'):
    (source/'tests'/name).write_text((root/'tests'/name).read_text())
with (source/'meson.build').open('a') as file:
    file.write("\nexecutable('details-corrections-before', 'tests/details-corrections.vala', 'tests/native-evidence.vala', core, ui, dependencies: deps)\n")
(source/'revision.txt').write_text(revision+'\n')
subprocess.run(['meson','setup',str(source/'build'),str(source),'--reconfigure'],check=True)
subprocess.run(['meson','compile','-C',str(source/'build'),'details-corrections-before'],check=True)
