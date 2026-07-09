#!/usr/bin/env python3
"""Calculator GUI supporting +, -, *, /, //, %, and ** operations."""

import operator
import tkinter as tk

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


def format_result(value):
    if isinstance(value, float) and value.is_integer():
        return str(int(value))
    return str(value)


class CalculatorApp:
    BUTTON_ROWS = [
        ["C", "//", "%", "**"],
        ["7", "8", "9", "/"],
        ["4", "5", "6", "*"],
        ["1", "2", "3", "-"],
        ["0", ".", "=", "+"],
    ]

    def __init__(self, root):
        self.pending_a = None
        self.pending_op = None
        self.reset_on_next_digit = False

        self.display_var = tk.StringVar(value="0")
        display = tk.Entry(
            root, textvariable=self.display_var, font=("Helvetica", 24),
            justify="right", state="readonly", readonlybackground="white",
        )
        display.grid(row=0, column=0, columnspan=4, sticky="nsew", padx=4, pady=4)

        for row_index, row in enumerate(self.BUTTON_ROWS, start=1):
            for col_index, label in enumerate(row):
                button = tk.Button(
                    root, text=label, font=("Helvetica", 16), width=4, height=2,
                    command=lambda label=label: self.on_button(label),
                )
                button.grid(row=row_index, column=col_index, sticky="nsew", padx=2, pady=2)

        for col_index in range(4):
            root.grid_columnconfigure(col_index, weight=1)

    def on_button(self, label):
        if label == "C":
            self.clear()
        elif label == "=":
            self.equals()
        elif label in OPERATORS:
            self.set_operator(label)
        else:
            self.append_digit(label)

    def clear(self):
        self.pending_a = None
        self.pending_op = None
        self.reset_on_next_digit = False
        self.display_var.set("0")

    def append_digit(self, digit):
        current = self.display_var.get()
        if self.reset_on_next_digit or current == "0" or current.startswith("Error"):
            current = ""
            self.reset_on_next_digit = False
        if digit == "." and "." in current:
            return
        self.display_var.set(current + digit)

    def set_operator(self, op):
        if self.pending_op is not None and not self.reset_on_next_digit:
            self.equals()
        try:
            self.pending_a = float(self.display_var.get())
        except ValueError:
            return
        self.pending_op = op
        self.reset_on_next_digit = True

    def equals(self):
        if self.pending_op is None:
            return
        try:
            b = float(self.display_var.get())
            result = calculate(self.pending_a, self.pending_op, b)
            self.display_var.set(format_result(result))
        except (ValueError, ZeroDivisionError) as exc:
            self.display_var.set(f"Error: {exc}")
        self.pending_a = None
        self.pending_op = None
        self.reset_on_next_digit = True


def main():
    root = tk.Tk()
    root.title("Calculator")
    CalculatorApp(root)
    root.mainloop()


if __name__ == "__main__":
    main()
