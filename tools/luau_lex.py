"""Luau 소스에서 문자열 리터럴과 주석을 구분하는 최소 토크나이저.

l10n_scan.py 와 check_strings.py 가 같이 쓴다. 정확한 파서가 아니라
"이 한글이 주석인가 / 문자열인가 / 어느 줄인가"만 알면 되는 수준이다.
"""
import re

LONG_OPEN = re.compile(r"\[(=*)\[")


def tokens(src):
    """(kind, text, line, start, end) 를 낸다. kind: comment · string · istring.

    text 는 따옴표를 뺀 내용이다. start/end 는 따옴표를 포함한 원본 위치다.
    """
    i, n, line = 0, len(src), 1
    while i < n:
        c = src[i]
        if c == "\n":
            line += 1
            i += 1
        elif src.startswith("--", i):
            m = LONG_OPEN.match(src, i + 2)
            if m:
                close = "]" + m.group(1) + "]"
                j = src.find(close, m.end())
                j = n if j < 0 else j + len(close)
            else:
                j = src.find("\n", i)
                j = n if j < 0 else j
            text = src[i:j]
            yield ("comment", text, line, i, j)
            line += text.count("\n")
            i = j
        elif c == "[" and LONG_OPEN.match(src, i):
            m = LONG_OPEN.match(src, i)
            close = "]" + m.group(1) + "]"
            j = src.find(close, m.end())
            j = n if j < 0 else j + len(close)
            text = src[m.end():j - len(close)]
            yield ("string", text, line, i, j)
            line += src[i:j].count("\n")
            i = j
        elif c in "\"'`":
            j = i + 1
            while j < n and src[j] != c:
                if src[j] == "\\":
                    j += 1
                elif src[j] == "\n" and c != "`":
                    break
                j += 1
            text = src[i + 1:j]
            yield ("istring" if c == "`" else "string", text, line, i, j + 1)
            line += text.count("\n")
            i = j + 1
        else:
            i += 1
