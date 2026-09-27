#!/usr/bin/env python3
"""Check local links in the maintained Sonexis Markdown documentation."""

from __future__ import annotations

import argparse
from html.parser import HTMLParser
from pathlib import Path
import re
import sys
from tempfile import TemporaryDirectory
from urllib.parse import unquote, urlsplit


MAINTAINED_DOCS = ("README.md", "CONTRIBUTING.md", "docs/README.md")
REFERENCE = re.compile(r"^\s{0,3}\[[^\]\n]+\]:\s*(<[^>\n]+>|\S+)", re.MULTILINE)
EMAIL = re.compile(r"^[^/\s]+@[^/\s]+$")
INLINE_CODE = re.compile(r"(?<!\x60)(\x60+).*?(?<!\x60)\1(?!\x60)", re.DOTALL)


def _blank(text: str) -> str:
    return "".join("\n" if char == "\n" else " " for char in text)


def without_code(text: str) -> str:
    """Mask fenced, indented, and inline code while preserving Markdown link delimiters."""
    tick = chr(96)
    fence = re.compile(rf"^ {{0,3}}({tick}{{3,}}|~{{3,}})")
    output: list[str] = []
    in_fence = False
    fence_char = ""
    fence_size = 0

    for line in text.splitlines(keepends=True):
        match = fence.match(line)
        if not in_fence and match:
            marker = match.group(1)
            fence_char, fence_size = marker[0], len(marker)
            in_fence = True
            output.append(_blank(line))
            continue
        if in_fence:
            output.append(_blank(line))
            if match and match.group(1)[0] == fence_char and len(match.group(1)) >= fence_size:
                in_fence = False
            continue
        if line.startswith(("    ", "\t")):
            output.append(_blank(line))
            continue
        output.append(line)

    masked = "".join(output)
    return INLINE_CODE.sub(lambda match: _blank(match.group(0)), masked)


def markdown_targets(text: str) -> list[str]:
    masked = without_code(text)
    targets: list[str] = []

    targets.extend(inline_link_targets(masked))

    for match in REFERENCE.finditer(masked):
        target = match.group(1)
        if target.startswith("<") and target.endswith(">"):
            target = target[1:-1]
        targets.append(target)

    parser = _HTMLTargets()
    parser.feed(masked)
    targets.extend(parser.targets)
    return targets


def _is_escaped(text: str, index: int) -> bool:
    backslashes = 0
    index -= 1
    while index >= 0 and text[index] == "\\":
        backslashes += 1
        index -= 1
    return backslashes % 2 == 1


def inline_link_targets(text: str) -> list[str]:
    targets: list[str] = []
    index = 0

    while index < len(text):
        if text[index] == "[":
            label_start = index
        elif text[index] == "!" and text[index + 1 : index + 2] == "[":
            label_start = index + 1
        else:
            index += 1
            continue

        if _is_escaped(text, label_start):
            index = label_start + 1
            continue

        depth = 1
        escaped = False
        cursor = label_start + 1
        while cursor < len(text) and text[cursor] != "\n":
            char = text[cursor]
            if escaped:
                escaped = False
            elif char == "\\":
                escaped = True
            elif char == "[":
                depth += 1
            elif char == "]":
                depth -= 1
                if depth == 0:
                    if text[cursor + 1 : cursor + 2] == "(":
                        target = destination_after_open_paren(text, cursor + 2)
                        if target:
                            targets.append(target)
                    index = cursor + 1
                    break
            cursor += 1
        else:
            index = label_start + 1

    return targets


def destination_after_open_paren(text: str, index: int) -> str | None:
    while index < len(text) and text[index].isspace():
        index += 1
    if index >= len(text):
        return None

    if text[index] == "<":
        end = index + 1
        escaped = False
        while end < len(text):
            char = text[end]
            if char == ">" and not escaped:
                return text[index + 1 : end]
            if char == "\\" and not escaped:
                escaped = True
            else:
                escaped = False
            end += 1
        return None

    chars: list[str] = []
    depth = 0
    escaped = False
    while index < len(text):
        char = text[index]
        if escaped:
            chars.append(char)
            escaped = False
        elif char == "\\":
            escaped = True
        elif char == "(":
            depth += 1
            chars.append(char)
        elif char == ")":
            if depth == 0:
                break
            depth -= 1
            chars.append(char)
        elif char.isspace() and depth == 0:
            break
        else:
            chars.append(char)
        index += 1

    target = "".join(chars)
    return target or None


class _HTMLTargets(HTMLParser):
    def __init__(self) -> None:
        super().__init__(convert_charrefs=True)
        self.targets: list[str] = []

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        del tag
        for name, value in attrs:
            if name.lower() in {"href", "src"} and value is not None:
                self.targets.append(value)

    def handle_startendtag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        self.handle_starttag(tag, attrs)


def maintained_markdown_files(root: Path) -> list[Path]:
    files = [root / relative for relative in MAINTAINED_DOCS if (root / relative).is_file()]
    scripts = root / "Scripts"
    if scripts.is_dir():
        files.extend(path for path in scripts.rglob("*.md") if path.is_file())
    return sorted(set(path.resolve() for path in files))


def check_root(root: Path) -> tuple[list[str], int]:
    root = root.resolve()
    errors: list[str] = []
    files = maintained_markdown_files(root)

    for source in files:
        source_rel = source.relative_to(root).as_posix()
        text = source.read_text(encoding="utf-8")
        for target in markdown_targets(text):
            problem = resolve_target(root, source, source_rel, target)
            if problem is not None:
                errors.append(problem)

    return errors, len(files)


def resolve_target(root: Path, source: Path, source_rel: str, target: str) -> str | None:
    original = target
    target = target.strip()
    if not target or target.startswith("#"):
        return None

    parsed = urlsplit(target)
    if parsed.scheme or parsed.netloc or EMAIL.match(parsed.path):
        return None

    path = unquote(parsed.path)
    if path.startswith("/"):
        candidate = root / path.lstrip("/")
    elif path:
        candidate = source.parent / path
    else:
        candidate = source

    resolved = candidate.resolve()
    try:
        resolved_rel = resolved.relative_to(root).as_posix()
    except ValueError:
        return f"{source_rel}: {original!r} -> {resolved} (outside repository)"

    if not resolved.exists():
        return f"{source_rel}: {original!r} -> {resolved_rel} (missing)"
    return None


def repository_root(script_path: Path) -> Path:
    return script_path.resolve().parent.parent


def self_test() -> None:
    with TemporaryDirectory(prefix="sonexis-doc-links-") as temporary:
        root = Path(temporary)
        (root / "docs").mkdir()
        (root / "Scripts" / "guides").mkdir(parents=True)
        (root / "assets").mkdir()
        script_path = root / "Scripts" / "check-local-doc-links.py"
        script_path.touch()
        assert repository_root(script_path) == root.resolve(), (
            "repository root was not derived from the script location"
        )
        (root / "docs" / "guide.md").write_text("# Guide\n", encoding="utf-8")
        (root / "assets" / "image.png").write_bytes(b"fixture")
        fence = chr(96) * 3
        readme = (
            "[guide](docs/guide.md?view=1#start) "
            "![image](assets/image.png) "
            "[web](https://example.com/page) "
            "[email](mailto:docs@example.com)\n"
            "[reference][guide]\n\n[guide]: <docs/guide.md?mode=full#top>\n"
            "[x [y]](docs/guide.md)\n"
            + r"\[escaped](missing-escaped.md)"
            + "\n"
            + fence
            + "md\n[ignored](missing-fenced.md)\n"
            + fence
            + "\n"
            + "    [ignored](missing-indented.md)\n"
            + chr(96)
            + "[ignored](missing-inline-code.md)"
            + chr(96)
            + "\n"
        )
        (root / "README.md").write_text(readme, encoding="utf-8")
        assert "docs/guide.md" in markdown_targets("[x [y]](docs/guide.md)"), (
            "balanced brackets in an inline-link label were not parsed"
        )
        (root / "docs" / "README.md").write_text(
            "[root](../README.md#top)\n", encoding="utf-8"
        )
        (root / "Scripts" / "guides" / "usage.md").write_text(
            '<img src="../../assets/image.png">\n', encoding="utf-8"
        )

        errors, count = check_root(root)
        assert not errors, f"valid fixture failed: {errors}"
        assert count == 3, f"expected 3 maintained Markdown files, got {count}"

        with (root / "docs" / "README.md").open("a", encoding="utf-8") as fixture:
            fixture.write("[missing](missing.md?view=docs#intro)\n")
        errors, _ = check_root(root)
        assert len(errors) == 1, f"expected one missing-link error, got {errors}"
        expected = ("docs/README.md", "missing.md?view=docs#intro", "docs/missing.md")
        assert all(part in errors[0] for part in expected), (
            "diagnostic omitted source, original target, or resolved path: " + errors[0]
        )
        print("Self-test passed (valid links accepted; missing-link diagnostic verified).")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--self-test",
        action="store_true",
        help="run passing and failing link-check fixtures",
    )
    args = parser.parse_args()
    if args.self_test:
        self_test()
        return 0

    errors, count = check_root(repository_root(Path(__file__)))
    if errors:
        print("\n".join(errors), file=sys.stderr)
        return 1
    print(f"Checked local links in {count} maintained Markdown file(s).")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
