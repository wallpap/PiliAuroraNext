import argparse
import json
import os
import re
import subprocess
import sys
from bisect import bisect_right
from collections import Counter
from dataclasses import asdict, dataclass
from functools import cache
from pathlib import Path

from pygments.lexers import get_lexer_by_name
from pygments.token import Comment as CommentToken

LEXERS = {
    ".c": "c",
    ".cc": "cpp",
    ".cmake": "cmake",
    ".cpp": "cpp",
    ".glsl": "glsl",
    ".gradle": "groovy",
    ".h": "cpp",
    ".hpp": "cpp",
    ".html": "html",
    ".ini": "ini",
    ".iss": "inno",
    ".java": "java",
    ".js": "javascript",
    ".json": "json",
    ".jsonc": "json",
    ".kt": "kotlin",
    ".kts": "kotlin",
    ".manifest": "xml",
    ".pro": "properties",
    ".properties": "properties",
    ".proto": "protobuf",
    ".ps1": "powershell",
    ".psd1": "powershell",
    ".py": "python",
    ".rc": "cpp",
    ".sh": "bash",
    ".toml": "toml",
    ".xml": "xml",
    ".yaml": "yaml",
    ".yml": "yaml",
}

SPECIAL_NAMES = {
    ".fvmrc": "json",
    ".gitattributes": "properties",
    ".gitignore": "properties",
    ".ignore": "properties",
    ".metadata": "yaml",
    "CMakeLists.txt": "cmake",
    "pubspec.lock": "yaml",
    "uv.lock": "toml",
}

UPSTREAM_PATHS = (
    "third_party/",
    "tool/protocol/schema/bilibili/",
    "assets/shaders/Anime4K_",
    "windows/packaging/exe/ChineseSimplified.isl",
)

CMAKE_PARTS = re.compile(
    r"(?P<block>\#\[(?P<comment_eq>=*)\[.*?\](?P=comment_eq)\])|"
    r"\[(?P<literal_eq>=*)\[.*?\](?P=literal_eq)\]|"
    r'"(?:\\.|[^"\\])*"|\\.|(?P<line>\#[^\n]*)',
    re.DOTALL,
)


@dataclass(frozen=True)
class Comment:
    line: int
    endLine: int
    text: str


def language(name):
    path = Path(name)
    return SPECIAL_NAMES.get(path.name, LEXERS.get(path.suffix.lower()))


def in_scope(name):
    return not name.startswith(UPSTREAM_PATHS) and (
        language(name) is not None or name.endswith(".patch")
    )


@cache
def _lexer(alias):
    return get_lexer_by_name(alias)


def _spans(source, alias):
    if alias == "cmake":
        for match in CMAKE_PARTS.finditer(source):
            if match.group("block") is not None or match.group("line") is not None:
                yield match.start(), match.end()
        return
    if alias == "inno":
        sections = [*re.finditer(r"(?im)^[ \t]*\[(\w+)\][ \t]*$", source)]
        ranges = [
            (0, "ini"),
            *(
                (section.start(), "pascal" if section[1].lower() == "code" else "ini")
                for section in sections
            ),
        ]
        for (offset, syntax), (limit, _) in zip(
            ranges, [*ranges[1:], (len(source), "")]
        ):
            section_text = source[offset:limit]
            spans = (
                (
                    (match.start(1), match.end(1))
                    for match in re.finditer(r"(?m)^[ \t]*(;[^\n]*)", section_text)
                )
                if syntax == "ini"
                else _spans(section_text, syntax)
            )
            for start, end in spans:
                yield start + offset, end + offset
        return
    for start, token, value in _lexer(alias).get_tokens_unprocessed(source):
        if (
            token not in CommentToken
            or token in CommentToken.Preproc
            or token in CommentToken.PreprocFile
        ):
            continue
        text = value.rstrip("\n")
        if text:
            yield start, start + len(text)


def _source_inventory(source, alias):
    starts = [0, *(index + 1 for index, char in enumerate(source) if char == "\n")]
    starts.append(len(source))
    spans = list(_spans(source, alias))
    touched = set()
    uncommented = list(source)
    comments = []
    for start, end in spans:
        first, last = bisect_right(starts, start), bisect_right(starts, end - 1)
        comments.append(Comment(first, last, source[start:end]))
        touched.update(range(first, last + 1))
        uncommented[start:end] = [
            char if char == "\n" else " " for char in source[start:end]
        ]
    cleaned = "".join(uncommented)
    removable = {
        line for line in touched if not cleaned[starts[line - 1] : starts[line]].strip()
    }
    return comments, touched, removable


def _patch_inventory(source):
    comments, touched, removable = [], set(), set()
    target = None
    hunk = []
    added = {}
    reading = False

    def flush():
        alias = "dart" if (target or "").endswith(".dart") else language(target or "")
        if alias and added:
            found, _, standalone = _source_inventory("".join(hunk), alias)
            for comment in found:
                lines = range(comment.line, comment.endLine + 1)
                if not all(line in added for line in lines):
                    continue
                comments.append(
                    Comment(added[comment.line], added[comment.endLine], comment.text)
                )
                touched.update(added[line] for line in lines)
                removable.update(added[line] for line in lines if line in standalone)
        hunk.clear()
        added.clear()

    for line_number, line in enumerate(source.splitlines(keepends=True), 1):
        if line.startswith("diff --git "):
            flush()
            reading = False
            target = None
        elif line.startswith("+++ ") and not reading:
            target = line[4:].strip().split("\t")[0].removeprefix("b/")
        elif line.startswith("@@ "):
            flush()
            reading = True
        elif reading and line.startswith(("+", " ")):
            hunk.append(line[1:])
            if line.startswith("+"):
                added[len(hunk)] = line_number
    flush()
    return comments, touched, removable


def inventory(name, source):
    source = source.replace("\r\n", "\n").replace("\r", "\n")
    if name.endswith(".patch"):
        return _patch_inventory(source)
    return _source_inventory(source, language(name))


def added_comments(name, before, after):
    allowed = Counter(comment.text for comment in inventory(name, before)[0])
    for comment in inventory(name, after)[0]:
        if allowed[comment.text]:
            allowed[comment.text] -= 1
        else:
            yield comment


def git_bytes(*arguments):
    return subprocess.run(
        ["git", *arguments],
        check=True,
        capture_output=True,
    ).stdout


def git(*arguments):
    return git_bytes(*arguments).decode("utf-8")


def git_paths(*arguments):
    return set(filter(in_scope, git(*arguments).split("\0")))


def untracked():
    return git_paths("ls-files", "-z", "--others", "--exclude-standard")


def regular_file(name):
    path = Path(name)
    return path.is_file() and not path.is_symlink()


def decode_source(data):
    if data.startswith((b"\xff\xfe", b"\xfe\xff")):
        return data.decode("utf-16")
    return data.decode("utf-8-sig")


def check(revision):
    base = git(
        "rev-parse", "--verify", "--end-of-options", f"{revision}^{{commit}}"
    ).strip()
    changed = git_paths(
        "diff", "--name-only", "-z", "--no-renames", "--diff-filter=ACMRT", base
    )
    existing = git_paths("ls-tree", "-r", "--name-only", "-z", base)
    violations = 0
    files = sorted(filter(regular_file, changed | untracked()))
    for name in files:
        before = (
            decode_source(git_bytes("show", "--no-textconv", f"{base}:{name}"))
            if name in existing
            else ""
        )
        for comment in added_comments(
            name, before, decode_source(Path(name).read_bytes())
        ):
            print(f"{name}:{comment.line}: 不允许新增或改写注释。", file=sys.stderr)
            violations += 1
    if violations:
        print(
            f"非 Dart 注释棘轮检查失败：{violations} 条新增或改写的注释。",
            file=sys.stderr,
        )
        return 1
    print(f"非 Dart 注释棘轮检查通过（{len(files)} 个有变更的源码或配置文件）。")
    return 0


def report(selection, emit_inventory):
    selection = selection.replace("\\", "/").rstrip("/")
    files = sorted(
        name
        for name in git_paths("ls-files", "-z", "--cached") | untracked()
        if (selection == "." or name == selection or name.startswith(f"{selection}/"))
        and regular_file(name)
    )
    if not files:
        raise ValueError(f"范围内没有第一方非 Dart 源码或配置文件：{selection}")
    tokens = comment_lines = removable_lines = 0
    for name in files:
        comments, touched, removable = inventory(
            name, decode_source(Path(name).read_bytes())
        )
        tokens += len(comments)
        comment_lines += len(touched)
        removable_lines += len(removable)
        if emit_inventory:
            for comment in comments:
                print(json.dumps({"path": name, **asdict(comment)}, ensure_ascii=False))
    if not emit_inventory:
        print(
            f"{selection}：{len(files)} 个非 Dart 文件，{tokens} 个注释 token，"
            f"{comment_lines} 个含注释行，最多减少 {removable_lines} 行。"
        )


def main():
    parser = argparse.ArgumentParser()
    modes = parser.add_mutually_exclusive_group()
    modes.add_argument("--check", metavar="BASE", default="HEAD")
    modes.add_argument("--inventory", nargs="?", const=".", metavar="PATH")
    modes.add_argument("--stats", nargs="?", const=".", metavar="PATH")
    arguments = parser.parse_args()
    try:
        if arguments.inventory is not None or arguments.stats is not None:
            report(
                arguments.inventory or arguments.stats, arguments.inventory is not None
            )
            return 0
        return check(arguments.check)
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        detail = getattr(error, "stderr", None)
        print(
            f"注释检查无法完成：{detail.decode('utf-8', errors='replace') if detail else error}",
            file=sys.stderr,
        )
        return 2


if __name__ == "__main__":
    if os.name == "nt":
        sys.stdout.reconfigure(encoding="utf-8")
        sys.stderr.reconfigure(encoding="utf-8")
    sys.exit(main())
