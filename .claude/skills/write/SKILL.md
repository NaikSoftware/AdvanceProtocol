---
name: write
description: Use when writing any prose for this project — code comments, doc comments, commit messages, PR titles and descriptions, review replies, docs under docs/, CLAUDE.md, skill and agent files, or localisation strings in assets/i18n/strings.csv. Covers which language goes where, technical English and Ukrainian style, and the project's fixed terminology in both languages.
---

# Writing for Advance Protocol

Every text here has one reader who is busy and one job: tell them something the code, the diff or
the UI cannot. Write that, in the language the slot requires, with the project's words — and stop.

## 1. Which language where

| text | language | notes |
| --- | --- | --- |
| comments in `core/` | **Ukrainian** | CLAUDE.md §9 — mandatory |
| comments in `game/`, `tools/`, `tests/` | Ukrainian | matches what is already there |
| commit subject and body | **Ukrainian**, Conventional Commits prefix in English | `fix(pause): помилка збереження не переживає закриття паузи` |
| PR title and description | Ukrainian | |
| `docs/`, `CLAUDE.md`, skills, agent files | **English** | |
| identifiers, `class_name`, translation keys | English | `snake_case` / `PascalCase` / `UPPER_SNAKE` keys |
| player-facing strings | **both**, via `assets/i18n/strings.csv` (`keys,uk,en`) | never hard-coded (§9) |

When editing a file, keep its language even if it breaks the table — a mixed-language file is worse.

## 2. Rules for every text

- **Why, not what.** A comment that restates the line below is noise; delete it. Say the reason,
  the constraint, or the trap: *what breaks if someone "simplifies" this.*
- **Cite the rule.** Gameplay comments point at the spec: `§3.4`, `§3.3.1`. Cross-references use
  `path:line` or a symbol (`BattleState.damage_dealt`), never "see above" or "the other file".
- **One claim per sentence.** Short sentences. Active voice. Present tense for how the code
  behaves (`повертає`, `returns`), not future (`буде повертати`, `will return`).
- **Concrete over vague.** Numbers, names, tiles, AP values. "Fast" → "6 tiles on road".
  "Improves handling" → say what changed.
- **No filler.** Cut: "basically", "simply", "it should be noted", "в принципі", "варто
  зазначити", "даний" (use "цей"), "здійснює" (use the real verb).
- **No hype, no apology.** No "robust", "seamless", "powerful", "elegant"; no "sorry", "hopefully".
- **Don't narrate history in code.** "Раніше тут було…", "fixed bug where…" belong in the commit,
  not the comment. The comment describes the code as it is.
- **Emphasis is rare.** Bold only the one thing a skimming reader must not miss.
- **No real armies, nations, insignia or identifiable vehicles** — in any text (CLAUDE.md §2).
  Unit names are role labels.

## 3. Comments

- `##` doc comment above a class, function or field: what it is for and the rule behind it.
  `#` inline: the non-obvious why of one line.
- Name the alternative you rejected when it is the obvious one — that is what stops the next
  person re-introducing it:
  > `## Окремий клас, а не прапорець у ShotFired — вигляд мусить відрізняти відповідь від пострілу, не здогадуючись про це з порядку подій.`
- A deliberate limit gets `# shortcut: <обмеження>, <коли переробити>`.
- Wrap at ~100 columns, like the surrounding code.

## 4. Commits

```
<type>(<scope>): <що змінилось, з погляду результату>

<чому — лише якщо це не очевидно з заголовка>
```

- Types: `feat fix refactor test docs chore perf`. Scope: `core`, `battle`, `pause`, `tools`,
  `phase-N`, … — follow `git log`.
- Subject in Ukrainian, lowercase, no trailing period, ≤ ~72 chars, describes the **behaviour**,
  not the edit: `шкода від мін зараховується власнику міни`, not `додав поле в BattleState`.
- Several unrelated changes → several commits, not one subject joined by commas.

## 5. Pull requests

Title: one Ukrainian phrase, the user-visible result. Body:

```markdown
- **<Зміна>.** Що тепер відбувається і чому. Імена полів/класів у `code`, правила як §3.x.
- **<Зміна>.** …

## Перевірка
- `./run_tests.sh`: N скриптів, X/X.
- <e2e, якщо є>: N/N PASS.
- Код переглянув окремий агент; зауваження виправлено.
```

- Lead with what changed for the player or the rules; implementation details second.
- **Перевірка lists only what was actually run**, with real counts. Skipped → say it was skipped.
- Known gaps and follow-ups go in their own short list, not buried in a bullet.
- End with the attribution line the session gives.

## 6. Docs (English)

- Present tense, declarative: "Firing sets AP to 0." Not "should", unless it is a recommendation.
- Rule first, reason after. Tables for anything with more than two parallel attributes.
- British spelling, as the codebase uses it: **armour**, **localisation**, **colour**, **centre**.
- A decision that was argued gets its reason written down; a decision that was reversed says so.
- Don't duplicate: link to the doc that owns the fact (`docs/rules/combat.md`), don't restate it.

## 7. Ukrainian style

- Literary Ukrainian, not calque from Russian or English:

| ✗ | ✓ |
| --- | --- |
| приймати участь | брати участь |
| на протязі | протягом |
| слідуючий | наступний |
| являється | є |
| згідно з / у відповідності до (для правила) | за (§3.4) / відповідно до |
| співпадати | збігатися |
| міроприємство | захід |
| на даний момент | зараз |
| реалізувати функціонал | зробити, додати |
| юзер, юзати | гравець / користувач, використовувати |

- Apostrophe: `ʼ` (U+02BC) in new comments and docs; quotes «ялинки» in prose, straight `"` in
  code and CSV.
- Dash with spaces — `—`. Ranges without spaces: `0–5`.
- Established English tech terms stay in Latin script and in `code` when they name a thing in
  the code: `Command`, `BattleEvent`, `seen`, `visible`, `AP`, `GUT`, `GLB`, `e2e`. Don't invent
  Ukrainian for them and don't transliterate (`коммаНд`, `евент` ✗).
- General programming words have Ukrainian forms — use them: тест, гілка, злиття, збереження,
  сцена, вузол, сигнал, подія, виклик, змінна, функція, клас, перевірка, кеш.

## 8. Project terminology

Use exactly these words. If you need a term not listed, check `assets/i18n/strings.csv` and
`docs/rules/` first; add it here if it becomes recurring.

| English | Українська | note |
| --- | --- | --- |
| turn | хід | |
| hot-seat / pass-and-play | гра на одному пристрої | |
| handover gate | гейт передачі (ходу) | |
| action points, AP | очки дії, AP | |
| fire cost | вартість пострілу | |
| movement zones (gold / red) | зони руху (золота / червона) | |
| fire radius | радіус вогню | |
| retaliation | відповідний вогонь, постріл у відповідь | |
| facing | напрям, facing | `facing` in code |
| armour sector: front / side / rear | сектор броні: лоб / борт / корма | |
| flank | фланг, бити у фланг | |
| fog of war | туман війни | |
| scouted (`seen`) | розвідане | |
| in sight (`visible`) | у полі зору | |
| vision diamond | ромб огляду | |
| weapon range | дальність зброї | |
| tile | тайл | |
| terrain penalty | штраф місцевості | |
| cross-country | прохідність | |
| ground state: dry / mud / frozen | стан ґрунту: сухо / багно / мерзлота | `hud_ground_*` |
| road | дорога | |
| mine / minefield | міна / мінне поле | |
| drone strike | удар дрона | |
| experience / level | досвід / рівень | |
| objective / capture | ціль / захоплення | |
| elimination | знищення всіх юнітів | |
| surrender / concede | здача, здатися | |
| unit / squad | юніт / відділення | |
| infantry · light vehicle · tank · artillery · engineer | піхота · легка техніка · танк · артилерія · інженер | |
| wreck / crater / ruts | уламки / вирва / колії | |
| core vs view | ядро (`core/`) vs вигляд (`game/`) | |
| rule / ruling | правило / рішення щодо правила | |

Unit names — the `UNIT_*` rows of `strings.csv` are the source of truth; quote them, don't
re-translate.

## 9. Localisation strings

- Add a key to `assets/i18n/strings.csv` with **both** `uk` and `en` filled — never one.
- Keys in English, describing the slot (`hud_drones`, `ERR_NO_DRONES_LEFT`), following the
  neighbouring keys' case.
- UI text is short: button = verb (`Здатися`, `Surrender`), errors say what is wrong in plain
  words (`Дрон не б'є піхоту`). No trailing periods on labels and buttons.
- Every rule-relevant number on screen gets its unit or icon (CLAUDE.md §1.5).

## Before you finish

Reread once and cut every sentence that the reader would not miss. Then check: right language
for the slot, terms from §8, no claim you did not verify.
