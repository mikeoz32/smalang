# Локальні масиви у frontend, IR та backend

## Мета

Додати локальні фіксовані масиви в Smalang від вихідного `.py` коду до нативного виконання, використовуючи binding syntax, який уже є в `main`.

## Узгоджена поведінка

- Тип має форму `array[T, N]`; `N` — невід'ємний цілочисельний літерал часу компіляції й частина типу. Дозволені вкладені та нульової довжини масиви.
- Елементи масиву розташовані inline підряд. Допустимі типи елементів — типи з даними, зокрема цілі типи, `bool` і масиви. Source-level `None` поки немає; `unit` існує лише в IR і відхиляється verifier-ом як тип елемента.
- Оголошення використовує наявну форму binding: `items: mut[array[int, 3]] = [1, 2, 3]`. Ініціалізатор обов'язковий; нульового заповнення немає. Літерал містить рівно `N` compile-time constant елементів.
- Звичайна або `const` прив'язка дозволяє читати елементи. Indexed assignment, наприклад `items[index] = value`, вимагає `mut[array[T, N]]`.
- Індекс має тип `uint`. Відомий під час компіляції індекс поза `0..N-1` спричиняє семантичну помилку. Динамічна перевірка меж породжує внутрішній runtime-виняток `IndexOutOfBounds` зі source location.
- Присвоєння масиву, передавання масиву параметром і повернення масиву копіюють його елементи; зміна копії не змінює джерело.
- Для початкового x86_64 backend довжина та inline-розмір мають вміщатися у signed 32-bit stack-frame addressing; завеликі типи відхиляються під час IR lowering.
- Від'ємна індексація та глобальні масиви не входять до цього зрізу. Глобальне `.data`/`.bss` сховище лишається наступним кроком.
- Літерали масивів приймають лише compile-time constant елементи. Арифметичні вирази з літералів перевіряються семантичним аналізом і згортаються під час IR lowering; змінні й виклики всередині літерала відхиляються.

## Критерії приймання

- Frontend розбирає рекурсивні `array[T, N]` типи, масивні літерали, indexed reads та indexed assignment у function body.
- Семантичний аналіз перевіряє точну довжину, точні типи елементів, обов'язковий ініціалізатор, дозвіл на mutation через `mut`, індекс типу `uint` і compile-time межі.
- Nested arrays та `array[T, 0]` мають коректний розмір і поводяться за тими самими правилами.
- Typed IR має структуровані типи масивів і S-expression dump для їхніх типів та операцій. Verifier відхиляє неправильні типи, довжини й операнди.
- Backend розміщує локальні масиви у стековому кадрі, виконує точні копії та елементні load/store, а динамічний вихід за межі передає чинному runtime exception mechanism.
- Вихідні приклади демонструють читання, indexed mutation, copy independence, вкладені масиви та індексування параметром `uint`; помилки компіляції й runtime bounds exception мають окремі focused behavior checks.

## Кроки реалізації

1. Додати failing frontend behavior cases для типів і літералів масивів, індексації, mutable element assignment та помилок типів/меж.
2. Розширити AST і парсер рекурсивними типами масивів, літералами й індексацією; використати наявні локальні binding/assignment вузли.
3. Додати рекурсивні semantic types, constant evaluation для literal-only елементів, перевірку довжин, типів, mutability та відомих меж.
4. Розширити typed IR структурованими array types, локальним storage, load/store, copy і runtime bounds-check операцією; описати правила у S-expression dump і verifier.
5. Реалізувати компактне inline розташування в stack frame, підтипові load/store, copy та by-value передачу й повернення масивів; під'єднати `IndexOutOfBounds` до runtime.
6. Додати `.py` приклади й focused end-to-end checks; оновити README та ADR за фактичною реалізацією.

## Перевірка

- Кожна поведінка спершу має failing test із очікуваною діагностикою або виконуваною поведінкою.
- `crystal tool format --check`
- `crystal spec`
- End-to-end `.py` програми проходять lexer, parser, semantic analysis, IR lowering, ELF linking через `ld` і запуск.
- `git diff --check`

## Результат виконання

- Реалізовано рекурсивні масивні типи й AST-вузли для літералів та індексації, семантичні перевірки й constant folding для літералів масивів.
- Typed IR описує масивні SSA-значення, `array.get` та `array.set` як bounds-checking `invoke`; verifier перевіряє типи й забороняє `unit`/exception елементи.
- Backend використовує inline stack storage, копіювання за значенням для локальних оновлень, параметрів і результатів функцій, а також runtime `IndexOutOfBounds` зі source-level stack trace.
- Додано `examples/fixed_arrays.py` та focused frontend/IR/backend тести. Повна перевірка: `crystal tool format --check`, `crystal spec` (224 приклади), `git diff --check`.
