#!/usr/bin/env python3
import json
import re
import sys
import time
from html.parser import HTMLParser
from pathlib import Path, PurePosixPath
from urllib.error import HTTPError
from urllib.parse import quote, urlparse
from urllib.request import Request, urlopen


class ScriptCollector(HTMLParser):
    def __init__(self):
        super().__init__()
        self.in_script = False
        self.scripts = []

    def handle_starttag(self, tag, attrs):
        if tag == "script":
            self.in_script = True
            self.scripts.append([])

    def handle_endtag(self, tag):
        if tag == "script":
            self.in_script = False

    def handle_data(self, data):
        if self.in_script:
            self.scripts[-1].append(data)


def fail(message):
    print(f"resolve-skills-pack: {message}", file=sys.stderr)
    raise SystemExit(1)


def fetch(url):
    request = Request(url, headers={"User-Agent": "skills-cli"})
    last_error = None
    for attempt in range(3):
        try:
            with urlopen(request, timeout=30) as response:
                return response.read()
        except HTTPError as error:
            detail = error.read().decode("utf-8", errors="replace")
            last_error = f"HTTP {error.code}: {detail}"
            if error.code < 500:
                break
        except Exception as error:
            last_error = str(error)
        if attempt < 2:
            time.sleep(2**attempt)
    fail(f"could not fetch {url}: {last_error}")


def pack_id_from_url(url):
    parsed = urlparse(url)
    if parsed.scheme != "https" or parsed.hostname not in {"skills.sh", "www.skills.sh"}:
        fail(f"unsupported pack URL: {url}")
    match = re.fullmatch(r"/p/([A-Za-z0-9_-]+)/*", parsed.path)
    if not match:
        fail(f"unsupported pack URL: {url}")
    return match.group(1)


def flight_payloads(html):
    collector = ScriptCollector()
    collector.feed(html)
    decoder = json.JSONDecoder()
    marker = "self.__next_f.push("

    for chunks in collector.scripts:
        script = "".join(chunks)
        offset = 0
        while True:
            start = script.find(marker, offset)
            if start < 0:
                break
            try:
                value, length = decoder.raw_decode(script, start + len(marker))
            except json.JSONDecodeError:
                break
            offset = start + len(marker) + length
            if (
                isinstance(value, list)
                and len(value) > 1
                and value[0] == 1
                and isinstance(value[1], str)
            ):
                yield value[1]


def pack_rows(html, pack_id):
    decoder = json.JSONDecoder()
    pack_marker = f'"packId":"{pack_id}"'

    for payload in flight_payloads(html):
        pack_start = payload.find(pack_marker)
        if pack_start < 0:
            continue
        rows_start = payload.find('"rows":', pack_start)
        if rows_start < 0:
            continue
        try:
            rows, _ = decoder.raw_decode(payload, rows_start + len('"rows":'))
        except json.JSONDecodeError:
            continue
        if isinstance(rows, list):
            return rows
    fail("pack membership was not present in the skills.sh response")


def main():
    if len(sys.argv) != 3:
        fail("usage: resolve-skills-pack.py PACK_URL OUTPUT_DIR")

    url = sys.argv[1]
    output_dir = Path(sys.argv[2])
    pack_id = pack_id_from_url(url)
    html = fetch(url).decode("utf-8")

    entries = []
    seen_names = set()
    for row in pack_rows(html, pack_id):
        source = row.get("source") if isinstance(row, dict) else None
        skill = row.get("skillId") if isinstance(row, dict) else None
        if not isinstance(source, str) or not re.fullmatch(
            r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+", source
        ):
            fail("pack contains a skill without a supported public source")
        if not isinstance(skill, str) or not re.fullmatch(
            r"[A-Za-z0-9][A-Za-z0-9._-]*", skill
        ):
            fail("pack contains an invalid skill identifier")
        if skill in seen_names:
            fail(f"pack contains duplicate skill name: {skill}")
        seen_names.add(skill)
        entries.append((source, skill))

    if not entries:
        fail("pack contains no installable skills")

    output_dir.mkdir(parents=True, exist_ok=False)
    for source, skill in entries:
        owner, repo = source.split("/", 1)
        snapshot_url = (
            "https://skills.sh/api/download/"
            f"{quote(owner, safe='')}/{quote(repo, safe='')}/{quote(skill, safe='')}"
        )
        try:
            snapshot = json.loads(fetch(snapshot_url))
        except (json.JSONDecodeError, UnicodeDecodeError):
            fail(f"skills.sh returned invalid snapshot JSON for {source}/{skill}")
        files = snapshot.get("files") if isinstance(snapshot, dict) else None
        if not isinstance(files, list) or not files:
            fail(f"skills.sh returned no snapshot files for {source}/{skill}")

        skill_dir = output_dir / skill
        found_skill_md = False
        for file in files:
            path = file.get("path") if isinstance(file, dict) else None
            contents = file.get("contents") if isinstance(file, dict) else None
            if not isinstance(path, str) or not isinstance(contents, str):
                fail(f"skills.sh returned an invalid snapshot file for {source}/{skill}")
            relative = PurePosixPath(path)
            if relative.is_absolute() or any(part in {"", ".", ".."} for part in relative.parts):
                fail(f"skills.sh returned an unsafe snapshot path for {source}/{skill}")
            target = skill_dir.joinpath(*relative.parts)
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text(contents, encoding="utf-8")
            found_skill_md = found_skill_md or relative.as_posix().lower() == "skill.md"

        if not found_skill_md:
            fail(f"skills.sh snapshot is missing SKILL.md for {source}/{skill}")
        print(skill)


if __name__ == "__main__":
    main()
