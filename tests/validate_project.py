"""Static consistency checks only; never a substitute for WDK/InfVerif."""
from pathlib import Path
import re
import xml.etree.ElementTree as ET
root = Path(__file__).resolve().parents[1]
ns = {'m': 'http://schemas.microsoft.com/developer/msbuild/2003'}
count = 0
for project in (root / 'driver/StorageFilter.vcxproj', root / 'checker/Checker.vcxproj'):
    tree = ET.parse(project)
    assert tree.find('m:Import', ns) is not None
    configs = tree.findall('m:ItemGroup/m:ProjectConfiguration', ns)
    assert {c.attrib['Include'] for c in configs} == {'Debug|x64', 'Release|x64'}
    for tag in ('ClCompile', 'ClInclude'):
        for node in tree.findall(f'm:ItemGroup/m:{tag}', ns):
            assert (project.parent / node.attrib['Include']).is_file(), node.attrib
            count += 1
inf = (root / 'package/StorageFilter.inf.in').read_text()
assert inf.count('__LAB_HARDWARE_ID__') == 1
assert 'Class=Extension' in inf and 'FilterPosition=Upper' in inf
assert 'AddFilter=StorageFilter,,FilterPosition' in inf
assert 'ServiceBinary=%13%\\StorageFilter.sys' in inf
assert 'UpperFilters' not in inf and 'LowerFilters' not in inf
assert 'ClassGuid={e2f84ce7-8efa-411c-aa69-97454ca4cb57}' in inf
# Detect accidental writes into the completed storage response.
storage = (root / 'driver/storage.c').read_text()
assert not re.search(r'(?:SystemBuffer\s*\[[^]]*\]|input->\w+)\s*=(?!=)', storage)
print(f'PASS: XML parsed, {count} project source/header references exist; INF template consistency checked')
