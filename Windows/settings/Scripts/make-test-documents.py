#!/usr/bin/env python3
"""Makes the settings documents the Settings app's unit tests read (AllInOneIMESettings.Tests/Documents), from a build of
the engine, so that the tests draw what the core really sends:

- golden-*.json: the answers to the settings golden's requests (Core/Tests/AllInOneIMEWireTests/WireGoldens/
  settings.jsonl), replayed on the golden's own config (fixtures/settings.json) with the interface in English;
- every-kind-<language>.json: a config that shows every kind of field (Bedrock, the typing speed, hidden words, a
  custom agent, an app's settings, a script extension bundle with each kind of preference, a custom command, fuzzy
  pinyin), in English, Simplified Chinese, French and Japanese;
- notion-en.json: Notion as @note's destination (a secret and a button that takes a link);
- broken-en.json: a config file that doesn't parse (every field read-only).

    python make-test-documents.py <AllInOneIMEEngine.exe>

Each engine runs in test mode on a pipe of its own (--pipe), with a config in a folder of its own and its keys in
memory: nothing of the user's is read or written. Run it again when the core's document changes.
"""
import json
import os
import shutil
import struct
import subprocess
import sys
import tempfile
import time

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, '..', 'AllInOneIMESettings.Tests', 'Documents')
REPO = os.path.abspath(os.path.join(HERE, '..', '..', '..'))
GOLDEN = os.path.join(REPO, 'Core', 'Tests', 'AllInOneIMEWireTests', 'WireGoldens', 'settings.jsonl')

BUNDLE = {
    "schemaVersion": 1, "name": "tools", "title": "Team Tools", "version": "1.2.0", "author": "Someone",
    "description": "Commands for the team",
    "preferences": [
        {"name": "apiToken", "type": "password", "title": "API token", "required": True},
        {"name": "region", "type": "dropdown", "title": "Region", "default": "eu",
         "data": [{"title": "Europe", "value": "eu"}, {"title": "Asia", "value": "asia"}]},
        {"name": "verbose", "type": "checkbox", "title": "Verbose", "default": False},
        {"name": "host", "title": "Host", "default": "example.com"},
    ],
    "commands": [{"script": "find.sh", "name": "find", "title": "Find someone"}],
}


def every_kind(language, extensions):
    return {
        "uiLanguage": language,
        "provider": "bedrock",
        "modelId": "us.anthropic.claude-haiku-5-5",
        "temperature": 0.5,
        "inputLanguages": ["en", "zh"],
        "fuzzyPinyin": ["z-zh", "en-eng"],
        "typeOut": True,
        "redaction": {"enabled": True, "customWords": ["Project X", "Jane"]},
        "agent": "custom",
        "agentCommand": ["muse", "--model", "big one"],
        "notes": {"destination": "folder", "folder": "C:\\Notes"},
        "customCommands": [{"name": "polite", "type": "prompt", "prompt": "Make it polite"},
                           {"name": "upper", "type": "run", "argv": ["python3", "-c", "print(input().upper())"]}],
        "appProfiles": {"win:notepad.exe": {"noAI": True, "inputLanguage": "zh", "rewriteStyles": ["formal"]}},
        "extensionFolders": [extensions],
    }


def frame(obj):
    body = json.dumps(obj, ensure_ascii=False).encode('utf-8')
    return struct.pack('<I', len(body)) + body


class Engine:
    def __init__(self, exe, config_text, name):
        self.folder = tempfile.mkdtemp(prefix='aio-docs-')
        self.config = os.path.join(self.folder, 'config.json')
        with open(self.config, 'w', encoding='utf-8') as f:
            f.write(config_text)
        self.pipe = r'\\.\pipe\aio-test-documents-' + name
        self.process = subprocess.Popen([exe, '--test', '--quiet', '--no-panel', '--config', self.config,
                                         '--pipe', self.pipe], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        for _ in range(100):
            try:
                self.f = open(self.pipe, 'r+b', buffering=0)
                break
            except OSError:
                time.sleep(0.1)
        else:
            raise SystemExit('no pipe ' + self.pipe)
        self.id = 0
        hello = self.request({"type": "hello", "versions": [1], "client": "settings/test-documents", "platform": "win",
                              "arch": "x64", "pid": os.getpid(), "capabilities": ["settings"]})
        assert 'settings' in hello['capabilities'], hello

    def request(self, obj):
        self.id += 1
        obj = dict(obj, v=1, id=self.id)
        self.f.write(frame(obj))
        while True:
            data = self.f.read(1 << 21)
            n = struct.unpack('<I', data[:4])[0]
            assert n == len(data) - 4
            answer = json.loads(data[4:].decode('utf-8'))
            if answer.get('re') == self.id:
                return answer

    def close(self):
        self.f.close()
        self.process.kill()
        self.process.wait()
        shutil.rmtree(self.folder, ignore_errors=True)


def save(name, answer):
    answer = {k: v for k, v in answer.items() if k not in ('v', 'id', 're')}
    with open(os.path.join(OUT, name + '.json'), 'w', encoding='utf-8', newline='\n') as f:
        json.dump(answer, f, ensure_ascii=False, indent=1, sort_keys=True)
        f.write('\n')
    print('  ' + name)


def main():
    exe = sys.argv[1]
    os.makedirs(OUT, exist_ok=True)
    for old in os.listdir(OUT):
        if old.endswith('.json'):
            os.remove(os.path.join(OUT, old))

    # The golden's requests, on its config, in English.
    with open(os.path.join(os.path.dirname(GOLDEN), 'fixtures', 'settings.json'), encoding='utf-8') as f:
        config = json.load(f)
    config['uiLanguage'] = 'en'
    engine = Engine(exe, json.dumps(config), 'golden')
    n = 0
    with open(GOLDEN, encoding='utf-8') as f:
        for line in f:
            if line.startswith('#! connect'):
                break
            if not line.startswith('> '):
                continue
            sent = json.loads(line[2:])
            if not sent['type'].startswith('settings') or ('value' not in sent and sent['type'] == 'settingsSet'):
                continue
            sent = {k: v for k, v in sent.items() if k not in ('v', 'id')}
            n += 1
            what = sent['type'] + ('-' + sent['field'] if 'field' in sent else '') + ('-' + sent['action'] if 'action' in sent else '')
            save('golden-%02d-%s' % (n, what.replace('.', '_')), engine.request(sent))
    engine.close()

    # Every kind of field, in four languages.
    extensions = tempfile.mkdtemp(prefix='aio-docs-extensions-')
    bundle = os.path.join(extensions, 'tools')
    os.makedirs(bundle)
    with open(os.path.join(bundle, 'extension.json'), 'w', encoding='utf-8') as f:
        json.dump(BUNDLE, f)
    with open(os.path.join(bundle, 'find.sh'), 'w', encoding='utf-8', newline='\n') as f:
        f.write('#!/bin/sh\necho found\n')
    with open(os.path.join(extensions, 'hello.sh'), 'w', encoding='utf-8', newline='\n') as f:
        f.write('#!/bin/sh\n# @allinoneime.schemaVersion 1\n# @allinoneime.title Say hi\necho hi\n')
    for language in ['en', 'zh-Hans', 'fr', 'ja']:
        engine = Engine(exe, json.dumps(every_kind(language, extensions)), 'every-' + language)
        save('every-kind-' + language, engine.request({"type": "settingsGet"}))
        engine.close()
    shutil.rmtree(extensions, ignore_errors=True)

    engine = Engine(exe, json.dumps({"uiLanguage": "en", "provider": "openai", "inputLanguages": ["en"],
                                     "notes": {"destination": "notion"}, "extensionFolders": []}), 'notion')
    save('notion-en', engine.request({"type": "settingsGet"}))
    engine.close()

    engine = Engine(exe, '{ "uiLanguage": "en", nope', 'broken')
    save('broken-en', engine.request({"type": "settingsGet"}))
    engine.close()


if __name__ == '__main__':
    main()
