# Formula Custom Fields for Redmine

Turn any Redmine custom field into a **calculated field**. Tick *"Calculated from a formula"*, type a
spreadsheet-style formula, and Redmine fills the value in **on the server every time the issue
(project, user, version, …) is saved**.

* No JavaScript, no View Customize snippets – it also works for the REST API, CSV import and bulk edit.
* **Safe**: formulas are parsed by a small interpreter, never passed to Ruby's `eval`. A formula can only do
  arithmetic, text and date work.
* **Stable**: fields are referenced by id (`{#12}`), so renaming a field never breaks a formula.
* **Exact**: numbers use decimal arithmetic (`0.1 + 0.2` is `0.3`, not `0.30000000000000004`).

Requires Redmine 5.0 or later.

## Install

```sh
cd /path/to/redmine/plugins
git clone https://github.com/MontejTech/formula_custom_field.git formula_custom_field     # the directory must be named formula_custom_field
cd ..
bundle exec rake redmine:plugins:migrate RAILS_ENV=production
# restart Redmine
```

## Quick start

Say your *Issue* custom fields are:

| Id | Name | Format |
|---:|---|---|
| 1 | Unit price | Float |
| 2 | Quantity | Integer |
| 3 | Discount % | Float |
| 4 | Line total | Float ← **will be calculated** |

1. *Administration → Custom fields →* open **Line total**.
2. Tick **Calculated from a formula**.
3. Enter the formula, using the list below the box (double-click a field to insert its `{#id}`):

   ```
   ROUND({#1} * {#2} * (1 - {#3} / 100), 2)
   ```
4. Save. From now on **Line total** is recalculated whenever an issue is saved, and is read-only in the issue form.

## Formula syntax

| Syntax | Meaning |
|---|---|
| `{#12}` | value of the custom field with id 12 (same object type: an issue field can use other issue fields) |
| `{@estimated_hours}` | a built-in attribute of the object, e.g. `{@done_ratio}`, `{@start_date}`, `{@due_date}` |
| `1`, `2.5` | numbers |
| `"text"` or `'text'` | text (double the quote to include one: `"say ""hi"""`) |
| `TRUE`, `FALSE`, `BLANK` | constants |
| `+  -  *  /  %  ^` | add, subtract, multiply, divide, remainder, power |
| `&` | join text: `"Order-" & {#2}` |
| `=  <>  <  <=  >  >=` | comparisons (text compares case-insensitively) |
| `( )` | grouping |

Rules

* Blank in → blank out. If any input of `+ - * /` is blank the result is blank. Use `COALESCE({#1}, 0)` to treat blank as 0.
* Division by zero gives blank, not an error.
* Date + number = date, date − number = date, date − date = number of days.
* A formula can use other formula fields; the order is worked out automatically. Circular references are rejected when you save the field.
* If a formula fails at run time (e.g. text where a number is needed), the field is stored blank and a warning
  `[formula_custom_field] ...` goes to the Rails log. Saving the issue is never blocked.
* Supported field formats: integer, float, text, long text, date, boolean (single-value only). The result is converted to the field's format.

## Functions – with an example each

In these examples `{#1}` is an empty field, so you can see how blanks behave.

### Logic

| Function | What it does | Example | Result |
|---|---|---|---|
| `IF(test, then, else)` | picks a value; `else` is optional (blank if omitted) | `IF(5 > 3, "yes", "no")` | `yes` |
| `AND(a, b, …)` | true if all are true | `AND(1 < 2, 2 < 3)` | `TRUE` |
| `OR(a, b, …)` | true if any is true | `OR(1 > 2, 2 < 3)` | `TRUE` |
| `NOT(a)` | opposite | `NOT(1 > 2)` | `TRUE` |
| `ISBLANK(a)` | true if empty | `ISBLANK({#1})` | `TRUE` |
| `COALESCE(a, b, …)` | first non-empty value | `COALESCE({#1}, 10)` | `10` |

### Numbers

| Function | What it does | Example | Result |
|---|---|---|---|
| `ABS(n)` | remove the minus sign | `ABS(-4.5)` | `4.5` |
| `ROUND(n, digits)` | round half away from zero (`digits` optional, default 0) | `ROUND(2.567, 2)` | `2.57` |
| `ROUNDUP(n, digits)` | always round away from zero | `ROUNDUP(2.561, 2)` | `2.57` |
| `ROUNDDOWN(n, digits)` | always round toward zero (truncate) | `ROUNDDOWN(2.569, 2)` | `2.56` |
| `CEIL(n)` | next whole number up | `CEIL(2.1)` | `3` |
| `FLOOR(n)` | next whole number down | `FLOOR(2.9)` | `2` |
| `SQRT(n)` | square root (blank for negatives) | `SQRT(16)` | `4` |
| `SUM(a, b, …)` | total (blanks ignored) | `SUM(1, 2, 3.5)` | `6.5` |
| `MIN(a, b, …)` | smallest | `MIN(4, 2, 9)` | `2` |
| `MAX(a, b, …)` | largest | `MAX(4, 2, 9)` | `9` |
| `AVG(a, b, …)` | average (blanks ignored) | `AVG(2, 4, 9)` | `5` |

### Dates

| Function | What it does | Example | Result |
|---|---|---|---|
| `TODAY()` | current date | `{@due_date} - TODAY()` | days until due |
| `DATE(y, m, d)` | build a date (blank if invalid) | `DATE(2026, 3, 15)` | `2026-03-15` |
| `DAYS(end, start)` | days between two dates | `DAYS(DATE(2026, 3, 15), DATE(2026, 3, 1))` | `14` |
| `YEAR(date)` | year part | `YEAR(DATE(2026, 3, 15))` | `2026` |
| `MONTH(date)` | month part | `MONTH(DATE(2026, 3, 15))` | `3` |
| `DAY(date)` | day-of-month part | `DAY(DATE(2026, 3, 15))` | `15` |

### Text

| Function | What it does | Example | Result |
|---|---|---|---|
| `CONCAT(a, b, …)` | join values as text | `CONCAT("Order-", 42)` | `Order-42` |
| `UPPER(text)` | capitals | `UPPER("abc")` | `ABC` |
| `LOWER(text)` | lower case | `LOWER("ABC")` | `abc` |
| `TRIM(text)` | remove spaces at both ends | `TRIM("  hi  ")` | `hi` |
| `LEN(text)` | number of characters | `LEN("hello")` | `5` |
| `PART(text, separator, n)` | the n-th piece of a text split at a separator (case-insensitive, trimmed, 1 = first; blank if missing) | `PART("5 X 7", "x", 2)` | `7` |
| `VALUE(text)` | text to number (blank stays blank; error if not numeric) | `VALUE("12.5")` | `12.5` |

## More realistic examples

Assume these Issue fields: `#1` Unit price, `#2` Quantity, `#3` Discount %, `#4` Cost, `#5` Start date,
`#6` Lead time (days), `#7` First name, `#8` Last name, `#9` Priority (text), `#10` Estimated cost, `#11` Actual cost.

| Goal | Formula |
|---|---|
| Line total with discount | `ROUND({#1} * {#2} * (1 - {#3} / 100), 2)` |
| Tax-inclusive price (18 %) | `ROUND({#1} * 1.18, 2)` |
| Margin % | `IF({#1} = 0, BLANK, ROUND(({#1} - {#4}) / {#1} * 100, 1))` |
| Delivery date | `{#5} + {#6}` |
| Days until due | `DAYS({@due_date}, TODAY())` |
| Full name | `TRIM({#7} & " " & {#8})` |
| Multiply a text like `5 X 7` | `VALUE(PART({#9}, "x", 1)) * VALUE(PART({#9}, "x", 2))` |
| Overdue flag | `IF(AND(NOT(ISBLANK({@due_date})), {@due_date} < TODAY()), "Overdue", "OK")` |
| Budget status | `IF({#11} > {#10}, "Over budget", "Within budget")` |
| Hours per day of effort | `ROUND({@estimated_hours} / MAX(1, DAYS({@due_date}, {@start_date})), 2)` |
| Reference code | `UPPER(CONCAT("INV-", YEAR({#5}), "-", {@id}))` |
| Cost with default | `COALESCE({#4}, 0) * {#2}` |
| Tier by amount | `IF({#1} * {#2} >= 10000, "A", IF({#1} * {#2} >= 1000, "B", "C"))` |

## Recalculating existing data

A new or edited formula applies to an object the next time it is saved. To backfill everything now:

```sh
bundle exec rake redmine:formula_custom_field:recompute RAILS_ENV=production              # all formula fields
bundle exec rake redmine:formula_custom_field:recompute FIELD_ID=4 RAILS_ENV=production   # one field
```

This writes values directly: no journals, no `updated_on` change, no notifications.

## Tests

The engine is plain Ruby and needs no Redmine:

```sh
ruby -Ilib test/engine_test.rb
```

## Known limits

* A formula sees only the object being saved. Rolling up values from **child issues** (e.g. a parent's total = sum of its children) is not supported yet.
* Calculated fields are made read-only in the form for issues. For other object types the user's input is simply overwritten on save.
* Only a custom field's **id** is accepted in references. Ids are shown in the field picker under the formula box and in the URL of the custom field's edit page.

## License

[MIT](LICENSE) © 2026 Dipak Mali - Montej Tech LLP
