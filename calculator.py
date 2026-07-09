#!/usr/bin/env python3
"""Simple command-line calculator supporting +, -, *, /, //, %, and ** operations."""

import operator
import sys

OPERATORS = {
    "+": operator.add,
    "-": operator.sub,
    "*": operator.mul,
    "/": operator.truediv,
    "//": operator.floordiv,
    "%": operator.mod,
    "**": operator.pow,
}


def calculate(a, op, b):
    if op not in OPERATORS:
        raise ValueError(f"Unsupported operator: {op}")
    if op in ("/", "//", "%") and b == 0:
        raise ZeroDivisionError("Cannot divide by zero")
    return OPERATORS[op](a, b)


def parse_expression(expression):
    tokens = expression.split()
    if len(tokens) != 3:
        raise ValueError("Expression must be in the form: <number> <operator> <number>")
    a_str, op, b_str = tokens
    return float(a_str), op, float(b_str)


def repl():
    print("Simple Calculator (type 'quit' or 'exit' to stop)")
    print(f"Supported operators: {', '.join(OPERATORS)}")
    while True:
        try:
            expression = input("> ").strip()
        except (EOFError, KeyboardInterrupt):
            print()
            break
        if expression.lower() in ("quit", "exit"):
            break
        if not expression:
            continue
        try:
            a, op, b = parse_expression(expression)
            result = calculate(a, op, b)
            print(result)
        except (ValueError, ZeroDivisionError) as exc:
            print(f"Error: {exc}")


def main():
    if len(sys.argv) > 1:
        expression = " ".join(sys.argv[1:])
        try:
            a, op, b = parse_expression(expression)
            print(calculate(a, op, b))
        except (ValueError, ZeroDivisionError) as exc:
            print(f"Error: {exc}")
            sys.exit(1)
    else:
        repl()


if __name__ == "__main__":
    main()
