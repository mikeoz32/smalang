def code_for(value: bool) -> int:
    return match value:
        case False: 29
        case _: 17

def main() -> int:
    return code_for(True)
