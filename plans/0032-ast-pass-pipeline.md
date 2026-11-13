# План 0032 — спільний інтерфейс AST passes

## Мета

Зробити array lowering звичайним AST-to-AST compiler pass і додати спільний механізм послідовного запуску таких проходів, щоб нові AST lowering-и підключалися тим самим способом.

## Узгоджені межі

- Спільний pass interface стосується лише перетворень AST-to-AST. Semantic analysis залишається валідацією між трансформаціями; AST-to-IR та IR/backend passes залишаються окремими етапами.
- Кожен AST pass отримує семантично перевірений `SemanticModule` і повертає новий `ParsedModule` або source-located діагностику.
- Ordered AST pass pipeline виконує проходи послідовно, повторно запускає semantic analysis після кожного успішного проходу й передає оновлений `SemanticModule` наступному проходу.
- Array lowering реалізує спільний інтерфейс і є проходом стандартного pipeline. Результат останнього успішного semantic check передається наявному IR lowering.
- Помилка проходу або повторної семантичної перевірки зупиняє pipeline і перетворюється на наявний source-located `IrLoweringResult` diagnostic без втрати source span і повідомлення.
- `MatchLowerer`, semantic analyzer, IR instruction passes і backend не маскуються під AST passes, бо не повертають переписаний AST.

## Критерії приймання

- `IrLowerer` більше не створює ArrayAstLowerer напряму й не містить окремої для нього orchestration логіки.
- Array AST lowering виконується через спільний ordered pass pipeline; інтерфейс дозволяє передати кілька AST passes.
- Після кожного pass оновлюються semantic facts для наступного; перша помилка зупиняє виконання з правильною source-located діагностикою.
- Наявні array semantics, IR output, verifier, executable behavior та незмінність вхідних AST/type arenas зберігаються.
- Тести перевіряють pipeline composition/failure behavior і наскрізну роботу стандартного pipeline.
- README описує спільний AST pass pipeline та місце semantic revalidation.
- `crystal tool format --check`, `git diff --check` і `crystal spec` проходять.

## Кроки

1. Ввести спільний AST pass result/diagnostic contract та інтерфейс pass-у.
2. Винести послідовний запуск, semantic revalidation і error propagation у AST pass pipeline.
3. Перевести array lowering на новий інтерфейс і підключити його через стандартний ordered pipeline в `IrLowerer`.
4. Додати тести композиції/помилки pass-ів і перевірити збереження наявної наскрізної поведінки.
5. Оновити README, пройти незалежне рев’ю та повний набір перевірок.
