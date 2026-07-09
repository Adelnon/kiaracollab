# kiaracollab

A small collection of utilities. Currently ships a simple command-line calculator.

## Running the calculator

`calculator.py` is a standalone Python 3 script — no third-party dependencies are required. Make sure you have Python 3 installed, then run it in one of two modes.

### One-shot mode (pass an expression on the command line)

Provide a single expression as arguments and the script prints the result and exits:

```sh
python3 calculator.py 3 + 4
# 7.0

python3 calculator.py 10 / 4
# 2.5

python3 calculator.py 2 ** 8
# 256.0
```

Because most shells treat `*` as a glob, quote expressions that use multiplication or exponentiation:

```sh
python3 calculator.py "6 * 7"
python3 calculator.py "2 ** 10"
```

### Interactive mode (REPL)

Run the script with no arguments to drop into a prompt where you can enter expressions one at a time:

```sh
python3 calculator.py
```

```
Simple Calculator (type 'quit' or 'exit' to stop)
Supported operators: +, -, *, /, //, %, **
> 3 + 4
7.0
> 10 // 3
3.0
> quit
```

Type `quit` or `exit` (or press Ctrl-D / Ctrl-C) to leave the REPL.

### Expression format

Each expression must be exactly `<number> <operator> <number>` with spaces around the operator. Supported operators:

| Operator | Meaning              |
| -------- | -------------------- |
| `+`      | addition             |
| `-`      | subtraction          |
| `*`      | multiplication       |
| `/`      | division             |
| `//`     | floor division       |
| `%`      | modulo (remainder)   |
| `**`     | exponentiation       |

Dividing by zero or using an unsupported operator prints an `Error:` message; in one-shot mode the script also exits with a non-zero status.

### Optional: make it directly executable

The script has a `#!/usr/bin/env python3` shebang, so on Linux and macOS you can mark it executable and skip the `python3` prefix:

```sh
chmod +x calculator.py
./calculator.py 3 + 4
```
