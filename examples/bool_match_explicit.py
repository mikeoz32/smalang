def code_for(value: bool) -> int:
    return match value:
        case True: 17
        case False: 29

def main() -> int:
    return code_for(True) + code_for(False)
