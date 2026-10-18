---
name: write
description: Use when writing any prose for this project — code comments, doc comments, commit messages, PR titles and descriptions, review replies, docs under docs/, CLAUDE.md, skill and agent files, or localisation strings in assets/i18n/strings.csv. Covers which language goes where, technical terminology in Ukrainian and English (programming, testing, git, Godot, rendering, wargame), style, typography, and the game's own rules vocabulary.
---

# Writing for Advance Protocol

Every text here has a busy reader and one job: tell them what the code, the diff or the UI cannot.
Write that, in the language the slot requires, with the project's words — and stop.

The rules below come from the sources at the end and from what the repository already does.
Where the two disagree, the reason is stated.

**Terminology is the core of this skill.** Before writing, open the glossary for the language:

- [`terms-uk.md`](terms-uk.md) — programming, testing, git, Godot and rendering terms in Ukrainian,
  sourced from Godot/git/Blender translations and this repo's usage: translate, loanword, or code.
- [`terms-en.md`](terms-en.md) — precise English: confused pairs, exact Godot names, wargame
  vocabulary, requirement words.
- §8 below — the game's own rules vocabulary in both languages.

## 1. Which language where

| text | language | notes |
| --- | --- | --- |
| comments in `core/` | **Ukrainian** | CLAUDE.md §9 — mandatory |
| comments in `game/`, `tools/`, `tests/` | Ukrainian | what the code already does |
| commit subject and body | **Ukrainian**; `type(scope):` stays English | tools parse the prefix |
| PR title and description | Ukrainian | |
| `docs/`, `CLAUDE.md`, skills, agent files | **English** | |
| identifiers, `class_name`, translation keys | English | |
| player-facing text | **both**, in `assets/i18n/strings.csv` (`keys,uk,en`) | never hard-coded (§9) |

When editing a file, keep the language it is already in — a mixed-language file is worse.

## 2. Rules for every text

- **Why, not what.** If a comment restates the line below, delete it. If the code needs a "what",
  simplify the code. Write the reason, the constraint, or the trap: *what breaks if someone
  "simplifies" this.*
- **Name the rejected alternative** when it is the obvious one — that stops it coming back.
- **Cite the rule** as a bare `§3.4` (330 uses in the repo; `CLAUDE.md §3.4` only when outside the
  repo's own text). Point at code with `path:line` or a symbol (`BattleState.damage_dealt`), never
  "see above".
- **Active voice, present tense** for how things behave: `повертає`, `returns`. Future only for
  what really happens later.
- **Concrete over vague.** Numbers, names, tiles, AP. "Fast" → "6 tiles on road".
- **No filler, hype or apology.** Cut: just, simply, easy, basically, "it should be noted",
  robust, seamless, powerful; «в принципі», «варто зазначити», «по суті».
- **The code describes itself as it is now.** History ("раніше тут…", "fixed the bug where…")
  belongs in the commit message.
- **Bold is rare** — the one thing a skimming reader must not miss.
- **No real armies, nations, insignia or identifiable vehicles** in any text (CLAUDE.md §2).

## 3. Code comments (GDScript)

- `##` is a doc comment: it attaches to the class (top of file), or to the signal, enum, constant,
  variable or function directly below it, and shows in the editor's help. `#` is for one line's
  non-obvious why; tests mostly use `#`.
- A space after `#` / `##`. Commented-out code has none (`#print(x)`) — and should not be committed.
- Prefer comments on their own line; an inline comment is a few words.
- Code inside comments goes in backticks: `` `90 + rand(0, 90)` ``. The repo uses backticks, not
  Godot BBCode (`[code]`, `[param]`) — keep it so. BBCode renders in the help panel only, and the
  project's readers read the source.
- Lines ≤ 100 columns (the repo averages ~70).
- A deliberate limit: `# shortcut: <обмеження>, <коли переробити>`. A TODO names the trigger:
  `# TODO(Фаза 5): …` — never an open-ended "колись".
- When a change makes an existing comment false, fix the comment in the same commit.

Example of the house style:

```gdscript
## §3.3.1: ціль, що вижила, стріляє у відповідь. Окремий клас, а не
## прапорець у ShotFired — вигляд мусить відрізняти відповідь від
## пострілу, не здогадуючись про це з порядку подій.
```

## 4. Commits ([Conventional Commits 1.0](https://www.conventionalcommits.org/en/v1.0.0/))

```
<type>(<scope>): <що тепер є правдою>

<тіло: чому, і яку очевидну альтернативу відкинуто>

Co-Authored-By: …
```

- Types in use: `feat fix docs chore test refactor` (+ `perf`). Scopes in use: `core game battle
  pause menu ui tools plan skills agents phase-N` — follow `git log` before inventing one. A
  breaking change gets `!` before the colon.
- **Subject in Ukrainian is a statement of the result, not an order.** Present-tense or a noun
  phrase: `шкода від мін зараховується власнику міни`, `новий матч починається за гейтом
  передачі`. Never imperative (`додай`) — in Ukrainian it reads as a command to a person. This is
  the log's own convention; there is no external standard for non-English subjects.
- Lowercase after the colon, no trailing period, ≤ 72 characters (the log averages 60).
- Describe **behaviour**, not the edit: not `додав поле в BattleState`.
- Body wraps at 72 and explains why. Unrelated changes are separate commits.
- English subjects (old history) were imperative: `fix(game): stop dimming a unit that has fired`.

## 5. Pull requests

Title: one Ukrainian phrase naming the user-visible result — no type prefix (recent PRs). Never
"Фаза 1", "Виправлення", "Різне".

```markdown
- **<Зміна>.** Що тепер відбувається і чому. Код у `code`, правила як §3.x.
- **<Зміна>.** …

## Перевірка
- `./run_tests.sh`: N скриптів, X/X.
- <e2e, якщо є>: N/N PASS.
- Код переглянув окремий агент; зауваження виправлено.

## Що лишилось            ← лише якщо щось лишилось
- …
```

- Lead with what changed for the player or the rules; implementation second.
- Say where the reviewer should look hardest, if anywhere.
- **Перевірка lists only what was actually run**, with real counts. Skipped → say so.
- Re-read the description before merging — the change drifts during review.

## 6. Docs (English)

- Present tense, declarative: "Firing sets AP to 0." Rule first, reason after.
- Sentence-case headings, no trailing period. Address the reader as "you" when instructing.
- **British spelling, `-ise`:** armour, colour, centre, behaviour, localisation, defence, metre,
  grey, analyse, recentre. Identifiers keep the engine's spelling (`Color`, `center_on`) — never
  "correct" anything inside code font.
- Code elements in code font, and never as a verb, plural or possessive: "the value of
  `fire_cost`", not "`fire_cost`'s value".
- Oxford comma. Numerals for all game quantities (AP, HP, tiles, ranges); spell out other
  numbers below ten. Don't start a sentence with a numeral.
- Numbered lists for sequences, bullets otherwise, tables for parallel attributes.
- Avoid: e.g. / i.e. (write "for example" / "that is"), whitelist/blacklist, master/slave,
  abort/kill (stop, cancel).
- Link the doc that owns a fact; don't restate it.

## 7. Ukrainian style

### Calques — and things that only look like them

| ✗ | ✓ |
| --- | --- |
| приймати участь | брати участь |
| на протязі | протягом |
| слідуючий | наступний, такий |
| являється (= є) | є |
| співпадати | збігатися |
| вірний (= correct) | правильний, слушний |
| рахувати, що | вважати, що |
| співставляти | зіставляти, порівнювати |
| в якості | як |
| так як | оскільки, бо |
| по відношенню до | щодо, стосовно |
| приймати рішення | ухвалювати рішення, вирішувати |
| міроприємство | захід |
| любий (= any) | будь-який |
| ведучий (= leading) | провідний |
| згідно наказу, відповідно з | згідно з наказом, відповідно до |
| в залежності від | залежно від |
| складає (про число) | становить |
| по замовчуванню | типово, типовий (як у Godot uk) |

**Not errors, but weaker style:** «даний» → prefer «цей»; «здійснити видалення» → «видалити»
(verb + noun is the fault, not the verb); «відміняти» is accepted, «скасувати» is the UI word.

### Typography

| | rule |
| --- | --- |
| apostrophe | **ASCII `'`** everywhere — comments, commits, docs, `strings.csv`. Matches Godot's and git's uk translations and most of the repo; one character keeps `grep` working. |
| quotes | «ялинки» in prose; nested „лапки“ inside «»; straight `"` only in code and CSV fields |
| dash | `—` with spaces. A hyphen is never a dash (`Так - здатися` ✗) |
| ranges | `–` without spaces: `2–3 гравці`, `0–5` |
| numbers | decimal comma `2,5`; thousands with a space `1 000` |
| case | no English Title Case in Ukrainian — buttons, headings, unit names all sentence case |

### Technical words → [`terms-uk.md`](terms-uk.md)

- Anything with a name in code goes in backticks, Latin: `Command`, `BattleEvent`, `seen`,
  `visible`, `Viewport`, `null`. Identifiers in prose without backticks (`seen 23`, `null 11` in
  the repo today) are a slip.
- Otherwise the standard Ukrainian term (вузол, подія, екземпляр, типовий); a loanword only where
  developers don't use the official one (коміт, репозиторій, асет, меш).
- No English stems with Ukrainian endings: емітить, пофіксити, лукап, креш, девтул.
- «вигляд» is the presentation layer (`game/`), `core/` is the rules layer — not «ядро», not
  «шар показу».

## 8. Project terminology

**Comments use the same word as the UI.** Where code needs precision, add the identifier:
«розвідане (`seen`)».

| English | Українська | note |
| --- | --- | --- |
| turn | хід | |
| hot-seat | гра на одному пристрої | |
| handover gate | гейт передачі | dev word; the UI says «Передайте пристрій» |
| action points | очки дії, `AP` | UI abbreviation «ОД» |
| shot / fire | постріл / вогонь | |
| retaliation | вогонь у відповідь, постріл у відповідь | military usage |
| facing | напрям, `facing` | turning = поворот |
| armour: front / side / rear | лоб / борт / корма; лобова / бортова / кормова броня | as the UI says; **not** бік / тил |
| flank | фланг, бити у фланг | |
| fog of war | туман війни | |
| `seen` | розвідане | the rule-bearing grid (§3.5) |
| `visible` | у полі зору, видиме | only extends `seen` |
| vision diamond | ромб огляду | |
| weapon range | дальність | |
| tile | тайл (dev), клітинка (UI) | |
| terrain penalty | штраф місцевості | |
| cross-country | прохідність | |
| ground: dry / mud / frozen | сухо / багно / мерзлота | `hud_ground_*` |
| road | дорога | |
| mine / minefield | міна / мінне поле | |
| drone strike | удар дрона | not «безпілотник» |
| target (of a shot) | ціль | |
| elimination | знищення всіх юнітів | |
| surrender | здача, здатися | not «капітуляція» |
| unit / squad | юніт / відділення | |
| engineer | інженер | the class name; not «сапер» |
| infantry · light vehicle · tank · artillery | піхота · легка техніка · танк · артилерія | |
| tank destroyer · troop carrier | винищувач танків · бронетранспортер | `UNIT_*` rows |
| wreck / crater / ruts | уламки / вирва / колії | |

Unit names: the `UNIT_*` rows of `strings.csv` are the source of truth — quote, don't re-translate.

## 9. Player-facing strings

- Add each key to `assets/i18n/strings.csv` with **both** `uk` and `en`.
- Keys: `UPPER_SNAKE` for what `core/` emits (`ERR_*` validation errors, `UNIT_*` names);
  `lower_snake` prefixed by screen for the view (`hud_`, `pause_`, `results_`, `settings_`,
  `setup_`, `handover_`, `menu_`, `common_`).
- **Buttons are verbs.** Ukrainian infinitive: «Зберегти», «Скасувати», «Здатися»; English
  imperative: "Save", "Surrender". One or two words. A confirmation's buttons answer its question
  («Здатися?» → «Так — здатися» / «Скасувати»).
- **Case:** sentence case in both columns. Exception: English unit names are Title Case
  ("Heavy Tank").
- **Periods:** none on buttons, labels, headings; yes on full sentences in dialogs and hints.
- **Errors** say what is wrong in the player's terms and, if possible, what to do. Never blame
  ("Ви помилились" ✗). «Недостатньо очок дії», "Not enough action points".
- **Address:** formal «ви», lowercase; better, no pronoun at all: «Матч збережено».
- **Numbers in templates:** keep the number out of case agreement — «Дронів лишилось: %d», not
  «Лишилось %d дрони».
- Every rule-relevant number on screen carries its unit or icon (CLAUDE.md §1.5).

## 10. Known inconsistencies — don't copy them

Comments and docs follow this skill (terminology pass, 2026-10-17). What still deviates is
outside them — string literals:

- `ERR_*` strings say «сапер»; the unit is «інженер».
- `pause_surrender_yes` uses a hyphen as a dash: «Так - здатися».
- «очок дії» (UI) vs «очки дій» (Ukrainian wargame usage) — not settled; keep the UI's form.
- Assertion messages in `tests/` still carry `ʼ` and old terms (сапер, клітинка, інстанс).

Fix these when you touch the line anyway; don't open a sweep without asking.

## Before you finish

Reread once and cut every sentence the reader would not miss. Then check: the right language for
the slot, words from §8, typography from §7, no claim you did not verify.

## Sources

- Microsoft Ukrainian Style Guide — <https://download.microsoft.com/download/6/4/a/64a8b98e-e69f-47c9-96dd-f8bc55c176c6/ukr-ukr-StyleGuide.pdf>
- Mozilla uk l10n style guide — <https://mozilla-l10n.github.io/styleguides/uk/>
- Список типових мовних помилок — <https://uk.wikipedia.org/wiki/Довідка:Список_типових_мовних_помилок>
- Лапки / Тире (Правопис 2019 §161, §164) — <https://uk.wikipedia.org/wiki/Лапки>, <https://uk.wikipedia.org/wiki/Тире>
- Godot editor uk.po — <https://github.com/godotengine/godot-editor-l10n/blob/master/editor/uk.po>; git uk.po — <https://github.com/git/git/blob/master/po/uk.po>
- Google developer documentation style guide — <https://developers.google.com/style>
- Microsoft Writing Style Guide — <https://learn.microsoft.com/en-us/style-guide/>
- Google eng-practices, CL descriptions — <https://google.github.io/eng-practices/review/developer/cl-descriptions.html>
- Godot doc comments — <https://docs.godotengine.org/en/stable/tutorials/scripting/gdscript/gdscript_documentation_comments.html>; GDScript style guide — <https://docs.godotengine.org/en/stable/tutorials/scripting/gdscript/gdscript_styleguide.html>
- Windows app writing style (UI strings) — <https://learn.microsoft.com/en-us/windows/apps/design/style/writing-style>
