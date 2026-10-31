"""Mod rules that neither the FAF Lua compiler nor LuaLS can check.

check.py calls check_file() for every Lua file of a mod.
"""
import re
from pathlib import Path

BYTE_ORDER_MARK = b"\xef\xbb\xbf"

PCALL_BLOCK = re.compile(r"\bx?pcall\s*\(\s*function\b")
PREFS_CALL = re.compile(
    r"\b(?:SetToCurrentProfile|GetFromCurrentProfile|GetFieldFromCurrentProfile)"
    r"\s*\(\s*([^,()]+)"
)
STRING_ASSIGN = re.compile(r"\blocal\s+([A-Za-z_]\w*)\s*=\s*(['\"])([^'\"]*)\2")
STRING_LITERAL = re.compile(r"^(['\"])([^'\"]*)\1$")
TABLE_RETURN = re.compile(r"^\s*return\s*\{")


def strip_comments(source: str) -> str:
    """Blanks comments and keeps every line on its original number."""
    source = re.sub(r"--\[\[.*?\]\]", lambda found: "\n" * found.group().count("\n"), source,
                    flags=re.S)
    lines = []
    for line in source.split("\n"):
        kept, position, quote = [], 0, None
        while position < len(line):
            char = line[position]
            if quote:
                kept.append(char)
                if char == "\\" and position + 1 < len(line):
                    kept.append(line[position + 1])
                    position += 1
                elif char == quote:
                    quote = None
            elif char in "\"'":
                quote = char
                kept.append(char)
            elif line[position:position + 2] == "--":
                break
            else:
                kept.append(char)
            position += 1
        lines.append("".join(kept))
    return "\n".join(lines)


def blank_strings(code: str) -> str:
    return re.sub(r"\"(?:\\.|[^\"\\\n])*\"|'(?:\\.|[^'\\\n])*'", '""', code)


def wait_inside_pcall(code: str) -> list[str]:
    """WaitSeconds yields, and a coroutine cannot yield through the C function pcall."""
    problems = []
    depth = 0
    for number, line in enumerate(blank_strings(code).split("\n"), 1):
        stripped = line.strip()
        blocks = len(PCALL_BLOCK.findall(stripped))
        if depth or blocks:
            if re.search(r"\bWaitSeconds\b", stripped):
                problems.append(f"строка {number}: WaitSeconds внутри pcall")
            depth += blocks
            if depth and blocks == 0 and re.search(r"\b(do|then)\s*$", stripped):
                depth += 1
            elif depth and blocks == 0 and re.search(r"\bfunction\b", stripped):
                depth += 1
            depth = max(depth - len(re.findall(r"\bend\b", stripped)), 0)
    return problems


def dotted_prefs_keys(code: str) -> list[str]:
    """A key with a dot is written flat, but read as a path of nested tables."""
    assigned = {found.group(1): found.group(3) for found in STRING_ASSIGN.finditer(code)}
    problems = []
    for number, line in enumerate(code.split("\n"), 1):
        for call in PREFS_CALL.finditer(line):
            argument = call.group(1).strip()
            literal = STRING_LITERAL.match(argument)
            key = literal.group(2) if literal else assigned.get(argument)
            if key and "." in key:
                problems.append(f"строка {number}: точка в ключе настроек '{key}'")
    return problems


def table_returns(path: Path, code: str) -> list[str]:
    """import() ignores what a module file returns: it exports through globals."""
    if "modules" not in (part.lower() for part in path.parts):
        return []
    return [
        f"строка {number}: return таблицы в модуле игнорируется, экспортируй функции"
        for number, line in enumerate(code.split("\n"), 1)
        if TABLE_RETURN.match(line)
    ]


def check_file(path: Path) -> list[str]:
    raw = path.read_bytes()
    problems = []
    if raw.startswith(BYTE_ORDER_MARK):
        problems.append("строка 1: BOM в начале файла")
        raw = raw[len(BYTE_ORDER_MARK):]
    code = strip_comments(raw.decode("utf-8", errors="replace"))
    return (problems + wait_inside_pcall(code) + dotted_prefs_keys(code)
            + table_returns(path, code))
