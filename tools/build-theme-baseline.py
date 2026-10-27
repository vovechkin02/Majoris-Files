"""Build the committed Files baseline with the same native capture fixture."""
from pathlib import Path
import io
import subprocess
import tarfile

root=Path(__file__).resolve().parents[1]
source=root/'build/theme-baseline-source'
source.mkdir(exist_ok=True)
archive=subprocess.check_output(['git','archive','HEAD'],cwd=root)
with tarfile.open(fileobj=io.BytesIO(archive)) as files:
    files.extractall(source,filter='data')
fixture=(root/'tests/theme-integration.vala').read_text()
fixture=fixture.replace('browser.set_density(', 'baseline_density(')
fixture=fixture.replace('    reset_scroll(window);', '    if(!(name in new string[]{"grid-standard","details-standard","sidebar"}))return;\n    reset_scroll(window);')
fixture=fixture.replace('assert(browser.sidebar_width==224);','').replace('assert(browser.narrow);','').replace('assert(!browser.narrow);assert(browser.sidebar_width==260);','')
fixture=fixture.replace('using MajorisFiles;', 'using MajorisFiles;\nvoid baseline_density(string density) {}')
(source/'tests/theme-integration.vala').write_text(fixture)
with (source/'meson.build').open('a') as file:
    file.write("\nexecutable('theme-integration', 'tests/theme-integration.vala', core, ui, dependencies: deps)\n")
subprocess.run(['meson','setup',str(source/'build'),str(source)],check=True)
subprocess.run(['meson','compile','-C',str(source/'build'),'theme-integration'],check=True)
