# How it queries

Every question Sekisho answers is one condition, built in Elixir and run
in your database. This guide shows what that condition is, so you can
read its plans and give it the indexes it needs.

## One condition

For a permission on a schema:

    (allow OR id IN (records where a role that gives it is held)) AND NOT deny

`allow` and `deny` are your conditions, as you wrote them. The records
where a role is held are a set of ids: the union of every path to them.

```sql
SELECT d.* FROM documents AS d
WHERE (d.author_id = $1 OR d.id IN (
         SELECT resource_id FROM sekisho_grants
          WHERE resource_type = 'documents' AND role = ANY($2) AND actor_type = 'users' AND actor_id = $3
         UNION ALL
         SELECT id FROM documents WHERE org_id IN (SELECT resource_id FROM memberships ...)
         UNION ALL
         SELECT id FROM documents WHERE folder_id IN (
           WITH RECURSIVE tree AS (
             SELECT resource_id FROM sekisho_grants WHERE ... -- the folders shared with me
             UNION
             SELECT f.id FROM folders f JOIN tree t ON f.parent_id = t.id
           ) SELECT id FROM tree)))
  AND NOT d.locked
```

Each path is a query of its own, on its own indexes, and the database
hashes the union once. There is no chain of `OR` over joins, which a
planner cannot estimate.

* `allowed?/3` on a record is this condition and `id = $record`: one
  query on the primary key.
* `where_allowed/3` adds it to your query.
* `with_permissions/3` puts one condition per permission in the `SELECT`
  of one query over the records.
* A rule about the actor alone (`true`, `false`) adds nothing: no query
  for `allowed?/3`, and your query as it is for `where_allowed/3`.

## Nested records

A role passed down a relation to the same schema (a folder's parent) is a
recursive query, from the records that hold it themselves down to all
their descendants. It uses `UNION`, not `UNION ALL`, so a loop in your
data ends.

## Indexes

Sekisho's tables come with theirs: grants by record, by actor, and links
by token. Yours need:

* the foreign keys that `derive` follows: `documents(folder_id)`,
  `documents(org_id)`, `folders(parent_id)`;
* the actor columns your sources filter by: `memberships(user_id)`,
  `team_memberships(user_id)`;
* the columns of your own conditions, as for any query.

Phoenix's generators index foreign keys; check the ones you added by
hand.

## Any SQL database

The queries are plain Ecto, in SQL every database runs: joins, `UNION`,
`EXISTS`, and a recursive `WITH` for records nested in records of their
own kind. A custom role's permissions are rows of
`sekisho_role_permissions`, not an array.

What a database does its own way is in its dialect (`Sekisho.SQL.Dialect`),
and only there: making a grant again in one statement where the database
can (PostgreSQL, SQLite), and the type of a column where the standard one
does not fit (MySQL indexes a `varbinary`, not a `blob`). Another database
needs only a dialect, if anything, named for its adapter:

```elixir
config :sekisho, :dialects, %{Ecto.Adapters.Tds => MyApp.TdsDialect}
```

## Statistics and JIT

On PostgreSQL, the plans rely on its estimates. Keep autovacuum on, or
`ANALYZE` after a large import. PostgreSQL's JIT compiler starts above a
cost it estimates; on a database whose statistics are missing (a test
database, a fresh restore) a large estimate can make JIT cost more than
the query. `SET jit = off` for the role, as many apps do, if you see
"JIT" in a plan of a fast query.

## What it does not do

* **No cache between requests.** A grant, a membership or a role change
  counts at the next question. Within a LiveView, the hook checks again
  when grants change.
* **No checks in memory.** A record is checked as it is in the database.
  A rule about the actor alone needs no database at all.
