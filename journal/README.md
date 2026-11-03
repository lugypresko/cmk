# יומן הסוכנים – CMK

## מה זה?
כל סוכן כותב רשומה אחרי כל פעולה משמעותית. היומן משמש כ**זיכרון לסוכנים** וגם כ**לוג קריא בשבילך**.

## איפה?
- `journal/entries/` – קובץ לכל פעולה, ממוין לפי תאריך ומספר.
- `journal/AGENT_JOURNAL.md` – הסבר מלא (EN).
- DB: הטבלה `cmk.agent_journal`.

## איך לקרוא רשומה
| שדה | משמעות |
|---|---|
| `ts` | זמן (שעון ישראל) |
| `agent` | מי עשה |
| `workflow` | A / B / C / ops |
| `action` | מה נעשה |
| `outputs` | אילו קבצים נוצרו |
| `status` | done / approved / blocked ... |
| `human_gate` | האם נדרש/ניתן אישור שלך |

## מה דורש ממך תשומת לב?
חפש רשומות שבהן `human_gate` אינו `none` ואינו `itay_approved`:
`grep -L "human_gate: none\|itay_approved" journal/entries/*.md`

## כללים
- Append-only: לא עורכים רשומות ישנות, רק מוסיפים חדשות.
- ה-Orchestrator קורא את 20 הרשומות האחרונות לפני כל תכנון.
