#!/usr/bin/env python3
"""
Recusa qualquer bloco de ingress aberto para a internet.

Existe porque o trivy nao cobre este caso. Verificado empiricamente: com
`ingress { cidr_blocks = ["0.0.0.0/0"] }` na porta 5432, o trivy reporta zero
problemas em todas as severidades, enquanto acusa o egress equivalente.

A validacao da variavel `allowed_cidr_blocks` cobre quem passa o valor por
variavel; esta verificacao cobre quem escreve direto no .tf.
"""
import re
import sys
from pathlib import Path

OPEN_CIDRS = ("0.0.0.0/0", "::/0")


def ingress_blocks(text: str):
    """Devolve (linha_inicial, corpo) de cada bloco ingress, casando chaves."""
    for match in re.finditer(r"\bingress\s*\{", text):
        start = match.end()
        depth = 1
        index = start
        while index < len(text) and depth:
            if text[index] == "{":
                depth += 1
            elif text[index] == "}":
                depth -= 1
            index += 1
        line = text.count("\n", 0, match.start()) + 1
        yield line, text[start : index - 1]


def main() -> int:
    findings = []
    for path in sorted(Path(".").rglob("*.tf")):
        if ".terraform" in path.parts:
            continue
        text = path.read_text()
        for line, body in ingress_blocks(text):
            for cidr in OPEN_CIDRS:
                if f'"{cidr}"' in body:
                    findings.append((path, line, cidr))

    if not findings:
        print("ok: nenhum ingress aberto para a internet")
        return 0

    for path, line, cidr in findings:
        print(f"{path}:{line}: ingress aberto para {cidr}", file=sys.stderr)
    print(
        f"\n{len(findings)} bloco(s) de ingress aberto(s). "
        "Restrinja a origem antes de seguir.",
        file=sys.stderr,
    )
    return 1


if __name__ == "__main__":
    sys.exit(main())
