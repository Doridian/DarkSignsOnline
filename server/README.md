# The game server

The API the clients talk to and the website's account pages, in Rust. It
replaced a PHP server and answers at the same `.php` paths with the same
statuses, headers and bodies, so neither the clients nor any link changed.
It also serves the website's static files and the browser client, so the
binary and a database are the whole site.
How closely it matches is not a claim: [the parity test](#parity-with-the-php)
checks it, case by case, against what the PHP answered.

Nothing has to be in front of it. For TLS, put any reverse proxy there (and
send HSTS from it); it routes nothing and serves nothing, it only passes
requests on. `src/www.rs` is what nginx's `server.conf` used to be: the
cross-origin isolation headers on everything under `/game/`, the page
`no-cache` with no validators, the hashed assets `immutable`, `/game`
redirected to `/game/`.

## Layout

| Path | What |
|---|---|
| `src/api/` | One module per endpoint, named for the PHP script it replaces. `mod.rs` is what they shared: the CORS headers, authentication, the domain and money helpers |
| `src/site/` | The website pages. `templates/` is the PHP's literal HTML, extracted verbatim |
| `src/php.rs` | The PHP semantics the endpoints depend on: `(int)`, `empty()`, lenient base64, `preg_replace` back-references |
| `src/ctx.rs` | One request: output buffer, status, headers, `die`, the database connection |
| `src/request.rs` | `$_GET`/`$_POST`/`$_REQUEST`, Basic auth, the protocol version |
| `src/www.rs` | The static files: the website's, and the browser client under `/game/` |
| `tests/parity/` | The parity test, its seed, and the goldens recorded from the PHP |
| `database.sql` | The schema |

## Running it

Configuration is the environment, under the names the PHP deployment used:

| Variable | |
|---|---|
| `MYSQL_HOST`, `MYSQL_PORT` (3306), `MYSQL_USERNAME`, `MYSQL_PASSWORD`, `MYSQL_DATABASE` | The database. `MYSQL_SOCKET` instead of host and port for a unix socket |
| `JWT_PRIVATE_KEY`, `JWT_PUBLIC_KEY` | PEM, base64-encoded, for `domain_token.php` |
| `SMTP_HOST`, `SMTP_PORT`, `SMTP_FROM`, `SMTP_USERNAME`, `SMTP_PASSWORD` | Outgoing mail. With a username, STARTTLS is required |
| `DSO_LISTEN` | `host:port` (default `0.0.0.0:8080`) or `unix:/path` |
| `DSO_WWW` | The web root to serve static files from. Unset, only the API and pages answer. The `darksignsonline` package sets it |
| `DSO_TRUSTED_PROXIES` | Addresses and CIDRs, space- or comma-separated, whose `X-Real-IP` is believed (default `127.0.0.0/8 ::1`). A unix socket's peer always is |
| `DSO_GITREV` | The commit in the site's footer; `nix build` bakes it in |

What `_tasks.php` did under cron (drop expired password-reset codes) the
server does itself every 15 minutes. `/readyz` answers `OK` for a health
check. `SIGTERM` and `SIGINT` stop it.

The caller's address, recorded against transactions and uploads, is the
socket's peer unless that peer is a trusted proxy, in which case it is the
proxy's `X-Real-IP`. A proxy in front has to set that header (nginx:
`proxy_set_header X-Real-IP $remote_addr;`), and if it is not on this
machine, has to be named in `DSO_TRUSTED_PROXIES`.

```sh
nix build .#darksignsonline            # the server, with the site baked in as DSO_WWW
nix run   .#darksignsonline            # ...and run it, on :8080
nix build .#darksignsonline-server     # the bare binary
nix build .#darksignsonline-site       # the web root alone, with the client under game/
```

## Parity with the PHP

`tests/parity/` sends 274 requests to the server, in order, against a fresh MariaDB seeded from `seed.sql`, with the clock frozen
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
The PHP was recorded through nginx, so where its goldens had nginx's
`Server` header they now have the two this server sends on everything
(`X-Content-Type-Options`, `X-Frame-Options`), which that nginx added too.

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
- **No nginx in front.** A request nginx refused never reached the PHP; now
  the server sees it. The one case where that shows is a lower-case method:
  nginx answered `options` with its own `400`, and the endpoint, which
  compares methods without regard to case as the PHP did, now answers it as
  a preflight.
- **Mail goes out through lettre** rather than PHPMailer: the same sender,
  recipient, subject and body, in different headers.
- **Passwords verify as bcrypt** (`$2y$`, `$2b$`, `$2a$`), which is all
  `password_hash` ever made. New hashes are `$2y$` at cost 12, as PHP 8.4's.
