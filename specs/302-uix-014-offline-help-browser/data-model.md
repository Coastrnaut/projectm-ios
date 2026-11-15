# Data Model: UIX-014 Offline Help Browser

## HelpIndex (`Resources/Help/index.json`)

| Field | Type | Rule |
|---|---|---|
| `version` | Int | 1 |
| `articles` | [HelpEntry] | 11 entries, unique `id`, list order = display order |

## HelpEntry

| Field | Type | Rule |
|---|---|---|
| `id` | String | lowercase letters, digits and `-`; unique |
| `title` | String | equals the article's level-1 heading |
| `file` | String | `<name>.md`, present in `Resources/Help` |
| `keywords` | [String] | at least 3, lowercase |

## HelpArticle (parsed, in memory only)

- `entry`: HelpEntry
- `blocks`: [HelpBlock], non-empty; first is `.heading(level: 1, text: title)`

## HelpBlock

`heading(level: 1…3, text)`, `paragraph(text)`, `bullet(text)`, `numbered(number, text)`. Text keeps inline
`**bold**` / `*italic*` markers, rendered with inline-only Markdown parsing. Consecutive non-empty lines of a
paragraph join with a space; a blank line ends a block.

No state transitions; nothing is persisted.
