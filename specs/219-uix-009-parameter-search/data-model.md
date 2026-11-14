# Data Model: UIX-009 Parameter Search

No stored data.

## ParameterSearchHit (ParameterGraph)

| Field | Type | Rule |
|---|---|---|
| id | ParameterID | a registered descriptor's ID |
| tier | ParameterSearchTier | worst tier over the query's words: namePrefix < nameSubstring < group < unit |
| score | Int | sum of word tiers |
| index | Int | catalog (registration) index; final tie-break |

## ParameterSearchRow (app)

| Field | Type | Rule |
|---|---|---|
| id | ParameterID | from the hit |
| name | String | descriptor display name |
| group | String | group display name |
| value | String | current value text, or "Read only" |
| onScreen | Bool | the descriptor's group is drawn by the current visual (display only) |
