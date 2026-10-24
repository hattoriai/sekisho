# Changelog

All notable changes to Sekisho are documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and Sekisho follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- A permissions module (`use Sekisho`) and policies (`Sekisho.Policy`):
  rules as functions that return `true`, `false` or an Ecto condition
  (`allow/2`, `deny/2`, which wins), and roles, with `derive` from a role
  of the same record, from a role or a permission of a related record
  (a `belongs_to`, or a relation of your sources), and down a relation to
  the same schema to any depth.
- `allowed?/3`, `authorize/3`, `authorize!/3` (`Sekisho.Denied`, a 403 or
  a 404), `where_allowed/3` and `with_permissions/3`, from one condition:
  the union of every path, each a set the database hashes.
- Grants (`sekisho_grants`): a role on a record to a person, a group or
  anyone with a link, for good or until a date; `grant/4`, `revoke/4`,
  `grants/2`, checked so no one gives a role above their own.
- Roles each record defines (`custom_roles()`, `sekisho_roles`):
  `create_role/4`, `update_role/3`, `delete_role/2`, `roles/2`.
- Roles, relations and groups from your own tables (`Sekisho.Sources`).
- Fields: `allow_fields/2`, `allowed_fields/2`, `redact/2`.
- `explain/3` (`Sekisho.Explanation`): the paths that allow a permission.
- `Sekisho.LiveView`: events checked before `handle_event/3`, and pages
  that lose their access sent away, over PubSub (`changed/0` for your own
  tables).
- `mix sekisho.install` (Igniter) and `mix sekisho.gen.migration`, on
  `PhoenixMountable.Migrations`.
- `Sekisho.Test`: `assert_allowed`, `refute_allowed`,
  `assert_where_allowed`; `validate!/0`.
- Any SQL database Ecto speaks to: the queries are plain SQL, and what one
  database does its own way is in its dialect (`Sekisho.SQL.Dialect`:
  PostgreSQL, SQLite, MySQL and MariaDB, and a standard one for the
  others). A custom role's permissions are rows of
  `sekisho_role_permissions`. If you ran version 1 of the migrations from
  0.1.0-dev, roll it back and run it again: its tables changed.
