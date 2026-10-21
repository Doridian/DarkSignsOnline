# The game server

The API the clients talk to and the website's account pages, in Rust. It
replaced a PHP server and answers at the same `.php` paths with the same
statuses, headers and bodies, so neither the clients nor any link changed.
How closely it matches is not a claim: [the parity test](#parity-with-the-php)
checks it, case by case, against what the PHP answered.

nginx stays in front. It serves the static files in `www/` and the browser
client under `/game/`, and hands every `/<name>.php` and `/api/<name>.php` to
this server on a unix socket. See `rootfs/etc/nginx/server.conf`.

## Layout

| Path | What |
|---|---|
| `src/api/` | One module per endpoint, named for the PHP script it replaces. `mod.rs` is what they shared: the CORS headers, authentication, the domain and money helpers |
| `src/site/` | The website pages. `templates/` is the PHP's literal HTML, extracted verbatim |
| `src/php.rs` | The PHP semantics the endpoints depend on: `(int)`, `empty()`, lenient base64, `preg_replace` back-references |
| `src/ctx.rs` | One request: output buffer, status, headers, `die`, the database connection |
| `src/request.rs` | `$_GET`/`$_POST`/`$_REQUEST`, Basic auth, the protocol version |
| `tests/parity/` | The parity test, its seed, and the goldens recorded from the PHP |
| `rootfs/` | nginx, s6 and cron configuration for a container, and the schema |

## Running it

Configuration is the environment, under the names the PHP deployment used:

| Variable | |
|---|---|
| `MYSQL_HOST`, `MYSQL_PORT` (3306), `MYSQL_USERNAME`, `MYSQL_PASSWORD`, `MYSQL_DATABASE` | The database. `MYSQL_SOCKET` instead of host and port for a unix socket |
| `JWT_PRIVATE_KEY`, `JWT_PUBLIC_KEY` | PEM, base64-encoded, for `domain_token.php` |
| `SMTP_HOST`, `SMTP_PORT`, `SMTP_FROM`, `SMTP_USERNAME`, `SMTP_PASSWORD` | Outgoing mail. With a username, STARTTLS is required |
| `DSO_LISTEN` | `unix:/path` (default `unix:/run/darksignsonline/server.sock`) or `host:port` |
| `DSO_GITREV` | The commit in the site's footer; `nix build` bakes it in |

`darksignsonline-server tasks` does what `_tasks.php` did (drops expired
password-reset codes) and exits; cron runs it every 15 minutes.

nginx has to pass the caller's address as `X-Real-IP`, which the server
trusts, so it must only be reachable through nginx.

```sh
nix build .#darksignsonline-server     # the binary
nix build .#darksignsonline            # the static site, with the client under game/
```

## Parity with the PHP

`tests/parity/` sends 274 requests through a real nginx to the server, in
order, against a fresh MariaDB seeded from `seed.sql`, with the clock frozen
by libfaketime and mail caught by an SMTP sink. For each request it records
the status, the headers, the body, every row that changed, and every mail
sent. It compares all of that with `golden.jsonl`, which is the same run
recorded against the PHP under php-fpm with production's php.ini.

```sh
nix develop .#server --command cargo test --manifest-path server/Cargo.toml -- --include-ignored
```

Values that are random on both sides (keycodes, generated IPs, verification
codes, bcrypt salts) are learned from the database and replaced with numbered
placeholders, so a goldens line reads `<rand3>` where the run had a keycode.
Header names compare without regard to case, and `Date`, `Content-Length`,
`Transfer-Encoding`, `Connection` and `X-Powered-By` are not compared.

The goldens are the PHP's answers, so they only change when the cases do or
when behaviour is deliberately changed. A deliberate change of behaviour
means editing the goldens by hand, which is the point: the diff says what
changed for clients. The PHP itself was last in the tree at `91612d0`.

For a new case, `DSO_PARITY_RECORD=1` writes this server's answers over the
goldens instead of comparing. That makes them true by definition, so read the
diff: every line in it should be the new case.

```sh
DSO_PARITY_RECORD=1 \
  nix develop .#server --command cargo test --manifest-path server/Cargo.toml --test parity -- --ignored
```

## Where it differs on purpose

- **The database is always spoken to in utf8mb4.** PHP used whatever the
  server announced. Production's MariaDB announces utf8mb4, so the data was
  already stored that way.
- **Request parsing is plain form-urlencoding.** No PHP array syntax
  (`a[]=`), no `.`-to-`_` renaming of variable names, and no
  `multipart/form-data`. The clients send none of these.
- **Pages escape `& < > " '` and leave the rest as UTF-8**, where PHP turned
  every Latin-1 letter into a named entity. Only the reset form reflects
  free input.
- **Only endpoints and pages answer.** The PHP's include files, `phpinfo.php`
  and `_tasks.php` were reachable as URLs; they are now 404s like any other
  missing script.
- **Mail goes out through lettre** rather than PHPMailer: the same sender,
  recipient, subject and body, in different headers.
- **Passwords verify as bcrypt** (`$2y$`, `$2b$`, `$2a$`), which is all
  `password_hash` ever made. New hashes are `$2y$` at cost 12, as PHP 8.4's.
