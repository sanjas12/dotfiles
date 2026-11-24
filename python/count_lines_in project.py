# запустите скрипт из корня проекта 


from io import BytesIO
from pathlib import Path
import re
import subprocess
import tokenize

ignored = {
    tokenize.COMMENT, tokenize.ENCODING, tokenize.ENDMARKER,
    tokenize.INDENT, tokenize.DEDENT, tokenize.NEWLINE, tokenize.NL,
}

# Сначала распознаём комментарии и строки, затем остальные символы кода.
qml_tokens = re.compile(
    r"""//[^\n]*|/\*[\s\S]*?\*/|"(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*'|`(?:\\.|[^`\\])*`|\S"""
)


counts = {".py": 0, ".qml": 0}
files = subprocess.check_output(["git", "ls-files", "-z"]).decode("utf-8")

for name in files.split("\0"):
    path = Path(name)
    if path.suffix not in counts or not path.is_file():
        continue

    code_lines = set()
    if path.suffix == ".py":
        for token in tokenize.tokenize(BytesIO(path.read_bytes()).readline):
            if token.type not in ignored and token.string.strip():
                code_lines.update(range(token.start[0], token.end[0] + 1))
    else:
        source = path.read_text(encoding="utf-8-sig")
        line = 1
        previous_end = 0
        for match in qml_tokens.finditer(source):
            line += source.count("\n", previous_end, match.start())
            token = match.group()
            end_line = line + token.count("\n")
            if not token.startswith(("//", "/*")):
                code_lines.update(range(line, end_line + 1))
            line = end_line
            previous_end = match.end()

    counts[path.suffix] += len(code_lines)

for suffix, count in counts.items():
    print(f"{suffix}: {count}")
print(f"Total: {sum(counts.values())}")
