"""Tiny Docker-save shaped archives for offline tests; never production images."""
import io
import json
import tarfile


def write_image_archive(path, references, arch='amd64'):
    with tarfile.open(path, 'w') as archive:
        def add(name, value):
            data = value if isinstance(value, bytes) else json.dumps(value).encode()
            entry = tarfile.TarInfo(name)
            entry.size = len(data)
            archive.addfile(entry, io.BytesIO(data))
        manifest = []
        for index, reference in enumerate(references):
            config, layer = f'config-{index}.json', f'layer-{index}.tar'
            add(config, {'os': 'linux', 'architecture': arch})
            add(layer, b'FAKE LAYER FOR TEST ONLY')
            manifest.append({'Config': config, 'Layers': [layer], 'RepoTags': [reference]})
        add('manifest.json', manifest)
