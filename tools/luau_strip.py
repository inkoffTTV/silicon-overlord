"""Strip Luau type annotations so pure modules can be executed on a plain Lua VM (lupa).

Supported subset (the project's coding convention):
  * `--!strict` / `--!nonstrict` directives (comments, untouched)
  * `type X = ...` / `export type X = ...` declarations
  * `: T` annotations on locals, params, for-vars and return types
  * `:: T` casts
  * generic parameter lists on `function name<T, U>(`
Luau-only statements (continue, +=, `if-then-else` expressions, backtick strings) are
deliberately NOT used in the codebase so the stripped output is valid Lua 5.4/5.5.
"""
import re
import sys

TOKEN_RE = re.compile(r"""
    (?P<ws>\s+)
  | (?P<longcomment>--\[(?P<ceq>=*)\[.*?\](?P=ceq)\])
  | (?P<comment>--[^\n]*)
  | (?P<longstring>\[(?P<seq>=*)\[.*?\](?P=seq)\])
  | (?P<string>"(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*')
  | (?P<number>0[xX][0-9a-fA-F_]+|\d[\d_]*\.?[\d_]*(?:[eE][+-]?\d+)?|\.\d[\d_]*(?:[eE][+-]?\d+)?)
  | (?P<name>[A-Za-z_][A-Za-z0-9_]*)
  | (?P<op>\.\.\.|::|->|==|~=|<=|>=|\.\.|[-+*/%^#&~|<>=(){}\[\];:,.?])
""", re.X | re.S)

KEYWORDS = {"and","break","do","else","elseif","end","false","for","function","goto","if","in",
            "local","nil","not","or","repeat","return","then","true","until","while"}

def tokenize(src):
    pos = 0
    out = []
    while pos < len(src):
        m = TOKEN_RE.match(src, pos)
        if not m:
            raise SyntaxError("cannot tokenize at %d: %r" % (pos, src[pos:pos+30]))
        kind = m.lastgroup
        if kind in ("ceq", "seq"):
            kind = "longcomment" if m.group("longcomment") else "longstring"
        out.append((kind, m.group(0)))
        pos = m.end()
    return out

class Stripper:
    def __init__(self, toks):
        self.toks = toks
        self.i = 0
        self.out = []

    # ---- helpers ----
    def peek(self, k=0):
        j = self.i
        n = 0
        while j < len(self.toks):
            kind, val = self.toks[j]
            if kind in ("ws", "comment", "longcomment"):
                j += 1
                continue
            if n == k:
                return self.toks[j]
            n += 1
            j += 1
        return ("eof", "")

    def prev_sig(self):
        for kind, val in reversed(self.out):
            if kind not in ("ws", "comment", "longcomment"):
                return (kind, val)
        return ("eof", "")

    def skip_trivia_silent(self):
        while self.i < len(self.toks) and self.toks[self.i][0] in ("ws", "comment", "longcomment"):
            # keep newlines so line numbers survive
            kind, val = self.toks[self.i]
            if kind == "ws":
                self.out.append((kind, val))
            else:
                self.out.append(("ws", "\n" * val.count("\n")))
            self.i += 1

    def take(self):
        t = self.toks[self.i]
        self.i += 1
        return t

    def drop(self):
        """drop a significant token but preserve its newlines"""
        kind, val = self.toks[self.i]
        self.i += 1
        nl = val.count("\n")
        if nl:
            self.out.append(("ws", "\n" * nl))

    # ---- type expression consumer ----
    def drop_balanced(self, open_, close):
        depth = 0
        while self.i < len(self.toks):
            kind, val = self.toks[self.i]
            if kind in ("ws", "comment", "longcomment"):
                self.drop(); continue
            if val == open_:
                depth += 1
            elif val == close:
                depth -= 1
            self.drop()
            if depth == 0:
                return

    def drop_type(self, allow_pack=False):
        """Consume one Luau type expression (unions/intersections/optionals included)."""
        self.drop_trivia()
        self.drop_type_atom(allow_pack)
        while True:
            self.drop_trivia_inline()
            kind, val = self.peek()
            if val in ("|", "&"):
                self.drop_trivia(); self.drop(); self.drop_trivia(); self.drop_type_atom()
            elif val == "?":
                self.drop_trivia(); self.drop()
            else:
                return

    def drop_trivia(self):
        while self.i < len(self.toks) and self.toks[self.i][0] in ("ws", "comment", "longcomment"):
            self.drop()

    def drop_trivia_inline(self):
        # only skip trivia that does not contain a newline (type continues on same line
        # unless the next significant token is | or &)
        j = self.i
        while j < len(self.toks) and self.toks[j][0] in ("ws", "comment", "longcomment"):
            j += 1
        if j < len(self.toks) and self.toks[j][1] in ("|", "&", "?"):
            while self.i < j:
                self.drop()

    def drop_type_atom(self, allow_pack=False):
        kind, val = self.peek()
        if val == "(":
            start = self.i
            # detect a top-level comma inside the parentheses (a type pack) before consuming
            depth, has_comma, j = 0, False, self.i
            while j < len(self.toks):
                tk = self.toks[j][1]
                if tk in ("(", "{", "<"):
                    depth += 1
                elif tk in (")", "}", ">"):
                    depth -= 1
                    if depth == 0:
                        break
                elif tk == "," and depth == 1:
                    has_comma = True
                j += 1
            self.drop_balanced("(", ")")
            self.drop_trivia()
            if self.peek()[1] == "->":
                self.drop(); self.drop_trivia(); self.drop_type_atom(True)
            elif has_comma and not allow_pack:
                raise SyntaxError("type pack '(a, b)' used as a type (Luau requires '-> ' after it)")
            return
        if val == "{":
            self.drop_balanced("{", "}")
            return
        if kind in ("string", "number"):
            self.drop(); return
        if val == "...":
            self.drop()
            # `...any` (same line only) — a following `local` on the next line is NOT part of the type
            j = self.i
            while j < len(self.toks) and self.toks[j][0] == "ws" and "\n" not in self.toks[j][1]:
                j += 1
            if j < len(self.toks) and (self.toks[j][0] == "name" or self.toks[j][1] in ("{", "(")):
                while self.i < j:
                    self.drop()
                self.drop_type_atom()
            return
        if val == "typeof":
            self.drop(); self.drop_trivia(); self.drop_balanced("(", ")"); return
        if kind == "name":
            self.drop()
            # dotted names and generics
            while True:
                k2, v2 = self.peek()
                if v2 == ".":
                    self.drop(); self.drop_trivia(); self.drop()
                elif v2 == "<":
                    self.drop_balanced("<", ">")
                else:
                    break
            return
        raise SyntaxError("unexpected token in type: %r" % (val,))

    # ---- main ----
    def run(self):
        while self.i < len(self.toks):
            kind, val = self.toks[self.i]
            if kind in ("ws", "comment", "longcomment", "string", "longstring", "number"):
                self.out.append(self.take()); continue
            # `export type` / `type` declarations
            if kind == "name" and val == "export" and self.peek(1)[1] == "type":
                self.drop(); self.drop_trivia(); self.drop_type_decl(); continue
            if kind == "name" and val == "type" and self.peek(1)[0] == "name" and self.peek(2)[1] in ("=", "<"):
                self.drop_type_decl(); continue
            if val == "::":
                self.drop(); self.drop_type(); continue
            if val == ":":
                nk, nv = self.peek(1)
                nk2, nv2 = self.peek(2)
                is_method = (nk == "name" and (nv2 in ("(", "{") or nk2 == "string" or nk2 == "longstring"))
                if is_method:
                    self.out.append(self.take()); continue
                # a ':' right after ')' is a function return annotation: type packs are legal there
                is_return = self.prev_sig()[1] == ")"
                self.drop(); self.drop_type(allow_pack=is_return); continue
            if kind == "name" and val == "function":
                self.out.append(self.take())
                # function name<T>( or function<T>(
                j = self.i
                while True:
                    k2, v2 = self.peek()
                    if k2 == "name" or v2 in (".", ":"):
                        self.skip_trivia_silent(); self.out.append(self.take())
                    else:
                        break
                self.skip_trivia_silent()
                if self.peek()[1] == "<":
                    self.drop_balanced("<", ">")
                continue
            self.out.append(self.take())
        return "".join(v for _, v in self.out)

    def drop_type_decl(self):
        self.drop()  # 'type'
        self.drop_trivia(); self.drop()  # name
        self.drop_trivia()
        if self.peek()[1] == "<":
            self.drop_balanced("<", ">"); self.drop_trivia()
        assert self.peek()[1] == "=", "expected = in type decl"
        self.drop()
        self.drop_type()

def strip(src):
    return Stripper(tokenize(src)).run()

if __name__ == "__main__":
    sys.stdout.write(strip(open(sys.argv[1], encoding="utf-8").read()))
