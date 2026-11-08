def calculate(start: int, delta: mut[int]) -> int:
    base: int = start + 1
    fixed: const[int] = base + 1
    current: mut[int] = fixed
    current = current + delta
    delta = 2
    current = current + delta
    return current

def main() -> int:
    input: int = 3
    result: int = calculate(10, input)
    return input + result
