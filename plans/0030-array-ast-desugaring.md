# План 0030 — AST-to-AST lowering масивів

## Мета

Перенести реалізацію фіксованих масивів із typed IR/backend у frontend AST-to-AST lowering. Зберегти погоджену source-семантику й після lowering прибрати з IR та backend типи й операції, спеціальні для масивів.

## Поведінка та межі

- Залишити незмінними source-семантику з ADR 0001 і правила Memory API з ADR 0004: масиви inline, `[T, N]` із compile-time `N`, вкладені й нульової довжини; літерали з точним числом compile-time constant елементів; копіювання за значенням; `uint` індекси; статично відомий вихід за межі — compile-time error, динамічний — `IndexOutOfBounds`; indexed assignment обчислює RHS першим, основу й індекси — зліва направо й один раз, перевіряє всі межі до першого запису.
- Розширити `size_of` та `align_of` на рекурсивні типи `array[T, N]`, з перевіркою переповнення layout.
- Виконувати окремий AST-to-AST pass після source semantic checks і до AST-to-IR lowering. Згенеровані вузли мають коректні типи, symbol bindings та source locations. Низькорівневі виклики використовують ті самі `stack_storage`, `copy_memory`, `offset`, `cast`, `load`, `store` та інші погоджені примітиви, що доступні `unsafe` коду.
- Представляти локальні масиви як byte storage у стековому кадрі. Скалярні елементи читати/записувати через типізований вказівник і scalar `load`/`store`; агрегати копіювати через `copy_memory`. Для `array[T, 0]` не читати й не записувати елементи; якщо потрібна адреса, виділяти мінімальне ненульове сховище з належним alignment.
- Зберегти передачу параметрів за значенням: call site створює окрему копію аргументу в storage і передає її адресу внутрішній lowered-функції. Зберегти повернення за значенням через caller-provided result storage; результат не може посилатися на стековий кадр callee.
- У IR залишаються лише типонезалежні pointer, scalar, storage, copy та memory-effect операції. Не вводити окрему `bounds_check`: додати загальні цілочисельні порівняння, conditional branch і `raise` terminator. Порівняння повертає canonical `bool`, підтримує equality та signed/unsigned order predicates для scalar integer типів. `raise(kind, exceptional_successor, source_location)` створює exception record і передає owned exception value по exceptional edge; verifier перевіряє ownership як для exceptional edge `invoke`. Lowering генерує unsigned `index < length`; хибна гілка створює `IndexOutOfBounds`. Ці примітиви мають бути придатні для інших умовних runtime-перевірок. Операції, що самі можуть провалитися через зовнішній результат (наприклад, виклик функції чи syscall-backed allocation), залишаються `invoke`.
- AST-to-AST lowering може створювати внутрішні вузли compare, conditional branch та raise, які не породжуються parser-ом і не додають source-синтаксису. AST-to-IR lowering безпосередньо відображає їх у загальні compare/branch/raise IR інструкції.
- Видалити `IrArrayType`, array literal/get/set IR-вузли й visitor/builder/verifier підтримку, а також спеціальне array storage/register allocation/call/return/access codegen у x86-64 backend. Не змінювати SIMD layout або вже погоджену семантику.
- Глобальні масиви, від'ємні індекси, нові типи/синтаксис мови й динамічні масиви залишаються поза обсягом.

## Критерії приймання

- Компілятор проходить AST-to-AST pass для локальних, вкладених і нульової довжини масивів, індексних читань/записів та масивів у параметрах, викликах і результатах функцій.
- Перевірки evaluation order, рівноразового обчислення, копіювання за значенням та меж зберігають observable behavior, зокрема відсутність часткового запису, якщо пізніша перевірка меж кидає виняток.
- `size_of` та `align_of` повертають правильний compile-time layout для скалярів, вказівників і вкладених масивів; переповнення відхиляється.
- Немає типів, інструкцій, операцій або backend класів, спеціалізованих для array value/get/set. Є загальні integer comparison та raise механізми з перевіркою exceptional CFG і ownership. Згенерований IR проходить verifier і містить потрібні memory effects та порядки винятків.
- End-to-end програми компілюються в об'єкт, лінкуються системним `ld` і виконуються з очікуваною поведінкою.

## Кроки

1. Додати failing behavior tests для layout-запитів масивів, локального storage, елементного доступу, вкладених/нульових масивів, function argument/result copy, runtime bounds exception і evaluation order.
2. Додати до AST/semantic infrastructure безпечне представлення згенерованих імен, source provenance та фактів для нових вузлів; побудувати rewriter, що створює нову AST arena й повторно перевіряє згенероване дерево.
3. Розширити type-layout query syntax та semantic layout обчислення для рекурсивних масивів.
4. Додати загальні scalar integer comparisons, compiler-generated conditional/raise AST nodes і `raise` IR terminator: визначити signed/unsigned predicates, runtime exception creation, exceptional CFG edge, source location та ownership перевірки; перевірити кілька exception kinds, не лише `IndexOutOfBounds`.
5. Реалізувати lowering локального storage, літералів, присвоєнь, індексації й evaluation order через універсальні memory-примітиви.
6. Реалізувати lowering array parameters, call sites і returns через копії та caller-provided storage; зберегти lifetime й by-value семантику, включно з вкладеними викликами.
7. Видалити array-specific типи/операції з IR і весь відповідний backend код, verifier, dump та структурні тести; лишити тести на стабільні контракти generic IR.
8. Оновити приклади, README й ADR зі статусом реалізації; переглянути повний diff.

## Перевірка

- Для кожної поведінки спершу додати failing observable behavior test і переконатися, що він падає з очікуваної причини.
- `crystal tool format --check`
- `crystal spec`
- End-to-end `.py` програми проходять lexer, parser, semantic analysis, AST-to-AST lowering, IR lowering, ELF link через `ld` та запуск.
- `git diff --check`
