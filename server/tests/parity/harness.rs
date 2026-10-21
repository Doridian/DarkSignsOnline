//! The machinery behind the parity test: a throwaway MariaDB, the server
//! under test behind a real nginx, frozen time, an SMTP sink, and a raw HTTP
//! client that sees exactly what nginx sent.

use std::collections::BTreeMap;
use std::io::{BufRead, BufReader, Read, Write};
use std::net::{TcpListener, TcpStream};
use std::path::{Path, PathBuf};
use std::process::{Child, Command, Stdio};
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

/// The moment every request happens at. Frozen, so a run is reproducible
/// down to the timestamps in the bodies.
pub const FAKE_NOW: &str = "2026-10-21 12:00:00";
pub const GITREV: &str = "parity-test";

pub fn fixture(name: &str) -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR")).join("tests/parity").join(name)
}

fn free_port() -> u16 {
    TcpListener::bind("127.0.0.1:0").unwrap().local_addr().unwrap().port()
}

fn wait_for(what: &str, mut ready: impl FnMut() -> bool) {
    let start = Instant::now();
    while !ready() {
        assert!(
            start.elapsed() < Duration::from_secs(30),
            "timed out waiting for {what}"
        );
        std::thread::sleep(Duration::from_millis(50));
    }
}

/// A child process killed when dropped.
pub struct Proc(Child);

impl Drop for Proc {
    fn drop(&mut self) {
        let _ = self.0.kill();
        let _ = self.0.wait();
    }
}

fn spawn(cmd: &mut Command, log: &Path) -> Proc {
    let log = std::fs::File::create(log).unwrap();
    let child = cmd
        .stdin(Stdio::null())
        .stdout(log.try_clone().unwrap())
        .stderr(log)
        .spawn()
        .unwrap_or_else(|e| panic!("starting {cmd:?}: {e}"));
    Proc(child)
}

/// The environment that freezes a process's clock at [`FAKE_NOW`].
pub fn faketime(cmd: &mut Command) -> &mut Command {
    let lib = std::env::var("DSO_FAKETIME_LIB").expect("DSO_FAKETIME_LIB (use `nix develop .#server`)");
    cmd.env("LD_PRELOAD", lib)
        .env("FAKETIME", FAKE_NOW)
        .env("FAKETIME_DONT_FAKE_MONOTONIC", "1")
        .env("TZ", "UTC")
}

pub struct Db {
    pub socket: PathBuf,
    _proc: Proc,
}

impl Db {
    pub fn start(dir: &Path) -> Db {
        let data = dir.join("mysql");
        let socket = dir.join("mysql.sock");
        let status = Command::new("mariadb-install-db")
            .args([
                "--no-defaults",
                "--auth-root-authentication-method=normal",
                "--skip-test-db",
            ])
            .arg(format!("--datadir={}", data.display()))
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .status()
            .expect("mariadb-install-db");
        assert!(status.success(), "mariadb-install-db failed");
        let proc = spawn(
            Command::new("mariadbd")
                .arg("--no-defaults")
                .arg(format!("--datadir={}", data.display()))
                .arg(format!("--socket={}", socket.display()))
                .args(["--skip-networking", "--skip-grant-tables"])
                .args([
                    "--character-set-server=utf8mb4",
                    "--collation-server=utf8mb4_general_ci",
                ]),
            &dir.join("mariadb.log"),
        );
        let db = Db { socket, _proc: proc };
        wait_for("mariadb", || db.try_sql("SELECT 1").is_ok());
        db
    }

    fn client(&self) -> Command {
        let mut cmd = Command::new("mariadb");
        cmd.arg("--no-defaults")
            .arg(format!("--socket={}", self.socket.display()))
            .args([
                "-u",
                "root",
                "--default-character-set=utf8mb4",
                "--batch",
                "--skip-column-names",
            ]);
        cmd
    }

    fn try_sql(&self, sql: &str) -> Result<String, String> {
        let out = self.client().args(["-e", sql]).output().map_err(|e| e.to_string())?;
        if !out.status.success() {
            return Err(String::from_utf8_lossy(&out.stderr).into_owned());
        }
        Ok(String::from_utf8_lossy(&out.stdout).into_owned())
    }

    pub fn sql(&self, sql: &str) -> String {
        self.try_sql(sql).unwrap_or_else(|e| panic!("{sql}: {e}"))
    }

    /// A fresh `dso` database: the production schema, then the seed.
    pub fn reset(&self) {
        self.sql("DROP DATABASE IF EXISTS dso; CREATE DATABASE dso");
        for file in [
            Path::new(env!("CARGO_MANIFEST_DIR")).join("rootfs/etc/database.sql"),
            fixture("seed.sql"),
        ] {
            let out = self
                .client()
                .arg("dso")
                .stdin(std::fs::File::open(&file).unwrap())
                .output()
                .unwrap();
            assert!(
                out.status.success(),
                "{}: {}",
                file.display(),
                String::from_utf8_lossy(&out.stderr)
            );
        }
    }

    /// Every row of every table, one line each, as `table: col\tcol...`.
    pub fn dump(&self) -> Vec<String> {
        const TABLES: &[&str] = &[
            "users",
            "domains",
            "domain_scripts",
            "domain_files",
            "dsmail",
            "chat",
            "file_database",
            "libraries",
            "textspace",
            "transactions",
            "email_codes",
        ];
        let sql: String = TABLES
            .iter()
            .map(|t| format!("SELECT '{t}', t.* FROM dso.{t} t ORDER BY t.id;"))
            .collect();
        self.sql(&sql)
            .lines()
            .map(|l| {
                let (table, rest) = l.split_once('\t').unwrap();
                format!("{table}: {rest}")
            })
            .collect()
    }
}

/// One message as it arrived at the SMTP sink.
#[derive(Clone, Debug)]
pub struct Mail {
    pub envelope: Vec<String>,
    pub data: String,
}

pub struct SmtpSink {
    pub port: u16,
    pub mails: Arc<Mutex<Vec<Mail>>>,
}

impl SmtpSink {
    pub fn start() -> SmtpSink {
        let listener = TcpListener::bind("127.0.0.1:0").unwrap();
        let port = listener.local_addr().unwrap().port();
        let mails = Arc::new(Mutex::new(Vec::new()));
        let sink = mails.clone();
        std::thread::spawn(move || {
            for stream in listener.incoming().flatten() {
                let _ = Self::session(stream, &sink);
            }
        });
        SmtpSink { port, mails }
    }

    fn session(stream: TcpStream, mails: &Mutex<Vec<Mail>>) -> std::io::Result<()> {
        let mut out = stream.try_clone()?;
        let mut lines = BufReader::new(stream);
        out.write_all(b"220 sink ESMTP\r\n")?;
        let mut envelope = Vec::new();
        let mut line = String::new();
        loop {
            line.clear();
            if lines.read_line(&mut line)? == 0 {
                return Ok(());
            }
            let cmd = line.trim_end().to_string();
            let verb = cmd.split([' ', ':']).next().unwrap_or("").to_ascii_uppercase();
            match verb.as_str() {
                "MAIL" | "RCPT" => {
                    envelope.push(cmd);
                    out.write_all(b"250 OK\r\n")?;
                }
                "DATA" => {
                    out.write_all(b"354 go ahead\r\n")?;
                    let mut data = String::new();
                    loop {
                        line.clear();
                        lines.read_line(&mut line)?;
                        if line == ".\r\n" || line.is_empty() {
                            break;
                        }
                        data.push_str(&line);
                    }
                    mails.lock().unwrap().push(Mail {
                        envelope: std::mem::take(&mut envelope),
                        data,
                    });
                    out.write_all(b"250 queued\r\n")?;
                }
                "QUIT" => {
                    out.write_all(b"221 bye\r\n")?;
                    return Ok(());
                }
                _ => out.write_all(b"250 OK\r\n")?,
            }
        }
    }
}

/// Which server is behind nginx.
pub enum Backend {
    /// The old PHP tree, under php-fpm, configured as production was.
    Php { www: PathBuf },
    /// The Rust server.
    Rust,
}

pub struct Site {
    pub port: u16,
    _procs: Vec<Proc>,
}

impl Site {
    pub fn start(dir: &Path, backend: &Backend, db: &Db, smtp_port: u16) -> Site {
        let mut procs = Vec::new();
        let private_pem = std::fs::read_to_string(fixture("jwt-private.pem")).unwrap();
        let public_pem = std::fs::read_to_string(fixture("jwt-public.pem")).unwrap();
        let b64 = |s: &str| {
            let out = Command::new("base64")
                .arg("-w0")
                .stdin(Stdio::piped())
                .stdout(Stdio::piped())
                .spawn()
                .unwrap();
            out.stdin.as_ref().unwrap().write_all(s.as_bytes()).unwrap();
            String::from_utf8(out.wait_with_output().unwrap().stdout).unwrap()
        };

        let (root, location) = match backend {
            Backend::Php { www } => {
                // A copy of the tree, pointed at a config file of our own
                // instead of the one under /run.
                let root = dir.join("www");
                let status = Command::new("cp").arg("-r").arg(www).arg(&root).status().unwrap();
                assert!(status.success());
                Command::new("chmod").args(["-R", "u+w"]).arg(&root).status().unwrap();
                let config = dir.join("dso-config.php");
                for f in ["api/function_base.php", "api/domain_token_public.php"] {
                    let p = root.join(f);
                    let src = std::fs::read_to_string(&p).unwrap();
                    std::fs::write(
                        &p,
                        src.replace("/run/darksignsonline/dso-config.php", config.to_str().unwrap()),
                    )
                    .unwrap();
                }
                std::fs::write(root.join("api/gitrev.txt"), format!("{GITREV}\n")).unwrap();
                std::fs::write(
                    &config,
                    format!(
                        "<?php\n$MYSQL_HOST = 'localhost';\n$MYSQL_USERNAME = 'root';\n$MYSQL_PASSWORD = '';\n$MYSQL_DATABASE = 'dso';\n\
                         $JWT_PRIVATE_KEY = base64_decode('{}');\n$JWT_PUBLIC_KEY = base64_decode('{}');\n\
                         $SMTP_HOST = '127.0.0.1';\n$SMTP_PORT = '{smtp_port}';\n$SMTP_FROM = 'noreply@darksignsonline.com';\n\
                         $SMTP_USERNAME = '';\n$SMTP_PASSWORD = '';\n",
                        b64(&private_pem),
                        b64(&public_pem)
                    ),
                )
                .unwrap();

                // The settings of Alpine's php.ini-production that the
                // scripts can tell apart from PHP's built-in defaults.
                let ini = dir.join("php.ini");
                std::fs::write(
                    &ini,
                    format!(
                        "output_buffering = 4096\nexpose_php = On\nrequest_order = \"GP\"\nvariables_order = \"GPCS\"\n\
                         date.timezone = UTC\nmysqli.default_socket = {}\n",
                        db.socket.display()
                    ),
                )
                .unwrap();
                let sock = dir.join("php-fpm.sock");
                let conf = dir.join("php-fpm.conf");
                std::fs::write(
                    &conf,
                    format!(
                        "[global]\nerror_log = {dir}/php-fpm.log\ndaemonize = no\n\
                         [www]\nlisten = {sock}\npm = static\npm.max_children = 2\ncatch_workers_output = yes\n\
                         php_flag[display_errors] = off\nphp_admin_value[error_log] = {dir}/php-error.log\nphp_admin_flag[log_errors] = on\n",
                        dir = dir.display(),
                        sock = sock.display()
                    ),
                )
                .unwrap();
                procs.push(spawn(
                    faketime(
                        Command::new("php-fpm")
                            .arg("-F")
                            .arg("-y")
                            .arg(&conf)
                            .arg("-c")
                            .arg(&ini),
                    ),
                    &dir.join("php-fpm.out"),
                ));
                wait_for("php-fpm", || sock.exists());
                let location = format!(
                    "fastcgi_pass unix:{sock};\n\
                     fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;\n\
                     fastcgi_param SCRIPT_NAME $fastcgi_script_name;\n\
                     fastcgi_param QUERY_STRING $query_string;\n\
                     fastcgi_param REQUEST_METHOD $request_method;\n\
                     fastcgi_param CONTENT_TYPE $content_type;\n\
                     fastcgi_param CONTENT_LENGTH $content_length;\n\
                     fastcgi_param REQUEST_URI $request_uri;\n\
                     fastcgi_param DOCUMENT_URI $document_uri;\n\
                     fastcgi_param DOCUMENT_ROOT $document_root;\n\
                     fastcgi_param SERVER_PROTOCOL $server_protocol;\n\
                     fastcgi_param GATEWAY_INTERFACE CGI/1.1;\n\
                     fastcgi_param REMOTE_ADDR $remote_addr;\n\
                     fastcgi_param REMOTE_PORT $remote_port;\n\
                     fastcgi_param SERVER_ADDR $server_addr;\n\
                     fastcgi_param SERVER_PORT $server_port;\n\
                     fastcgi_param SERVER_NAME $server_name;\n\
                     fastcgi_param REDIRECT_STATUS 200;\n",
                    sock = sock.display()
                );
                (root, location)
            }
            Backend::Rust => {
                let sock = dir.join("server.sock");
                procs.push(spawn(
                    faketime(&mut Command::new(env!("CARGO_BIN_EXE_darksignsonline-server")))
                        .env("DSO_LISTEN", format!("unix:{}", sock.display()))
                        .env("MYSQL_SOCKET", &db.socket)
                        .env("MYSQL_USERNAME", "root")
                        .env("MYSQL_DATABASE", "dso")
                        .env("JWT_PRIVATE_KEY", b64(&private_pem))
                        .env("JWT_PUBLIC_KEY", b64(&public_pem))
                        .env("SMTP_HOST", "127.0.0.1")
                        .env("SMTP_PORT", smtp_port.to_string())
                        .env("SMTP_FROM", "noreply@darksignsonline.com")
                        .env("DSO_GITREV", GITREV),
                    &dir.join("server.out"),
                ));
                wait_for("the server", || sock.exists());
                // The same proxying as `rootfs/etc/nginx/server.conf`.
                let location = format!(
                    "proxy_pass http://unix:{}:$uri$is_args$args;\nproxy_set_header X-Real-IP $remote_addr;\n",
                    sock.display()
                );
                let root = dir.join("www");
                std::fs::create_dir_all(&root).unwrap();
                (root, location)
            }
        };

        let port = free_port();
        let tmp = dir.join("nginx-tmp");
        std::fs::create_dir_all(&tmp).unwrap();
        let conf = dir.join("nginx.conf");
        std::fs::write(
            &conf,
            format!(
                "daemon off;\npid {dir}/nginx.pid;\nerror_log {dir}/nginx-error.log notice;\nworker_processes 1;\n\
                 events {{ worker_connections 64; }}\n\
                 http {{\n  access_log off;\n\
                 client_body_temp_path {tmp}/body; proxy_temp_path {tmp}/proxy; fastcgi_temp_path {tmp}/fastcgi;\n\
                 uwsgi_temp_path {tmp}/uwsgi; scgi_temp_path {tmp}/scgi;\n\
                 proxy_http_version 1.1; proxy_request_buffering off; proxy_buffering off;\n\
                 fastcgi_request_buffering off; fastcgi_buffering off;\n\
                 server {{\n    listen 127.0.0.1:{port};\n    root {root};\n    index index.php index.htm index.html;\n\
                 location = / {{ rewrite ^ /index.php last; }}\n\
                 location ~ ^/(api/)?[a-z0-9_]+\\.php$ {{\n{location}}}\n  }}\n}}\n",
                dir = dir.display(),
                tmp = tmp.display(),
                root = root.display(),
            ),
        )
        .unwrap();
        procs.push(spawn(
            Command::new("nginx")
                .arg("-e")
                .arg(dir.join("nginx-error.log"))
                .arg("-p")
                .arg(dir)
                .arg("-c")
                .arg(&conf),
            &dir.join("nginx.out"),
        ));
        wait_for("nginx", || TcpStream::connect(("127.0.0.1", port)).is_ok());
        Site { port, _procs: procs }
    }
}

#[derive(Debug)]
pub struct HttpResponse {
    pub status: String,
    pub headers: Vec<(String, String)>,
    pub body: Vec<u8>,
}

/// One request, written out byte for byte, read back the same way.
pub fn http(port: u16, method: &str, target: &str, headers: &[(String, String)], body: Option<&[u8]>) -> HttpResponse {
    let mut stream = TcpStream::connect(("127.0.0.1", port)).unwrap();
    let mut req = format!("{method} {target} HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n").into_bytes();
    for (k, v) in headers {
        req.extend_from_slice(format!("{k}: {v}\r\n").as_bytes());
    }
    if let Some(body) = body {
        req.extend_from_slice(format!("Content-Length: {}\r\n\r\n", body.len()).as_bytes());
        req.extend_from_slice(body);
    } else {
        req.extend_from_slice(b"\r\n");
    }
    stream.write_all(&req).unwrap();
    let mut raw = Vec::new();
    stream.read_to_end(&mut raw).unwrap();

    let split = raw.windows(4).position(|w| w == b"\r\n\r\n").expect("a header block");
    let head = String::from_utf8_lossy(&raw[..split]).into_owned();
    let mut rest = raw[split + 4..].to_vec();
    let mut lines = head.split("\r\n");
    let status = lines.next().unwrap().to_string();
    let headers: Vec<(String, String)> = lines
        .map(|l| {
            let (k, v) = l.split_once(':').unwrap();
            (k.to_string(), v.trim().to_string())
        })
        .collect();
    if headers
        .iter()
        .any(|(k, v)| k.eq_ignore_ascii_case("transfer-encoding") && v == "chunked")
    {
        let mut body = Vec::new();
        loop {
            let eol = rest.windows(2).position(|w| w == b"\r\n").unwrap();
            let size = usize::from_str_radix(String::from_utf8_lossy(&rest[..eol]).trim(), 16).unwrap();
            if size == 0 {
                break;
            }
            body.extend_from_slice(&rest[eol + 2..eol + 2 + size]);
            rest.drain(..eol + 2 + size + 2);
        }
        rest = body;
    }
    HttpResponse {
        status,
        headers,
        body: rest,
    }
}

/// Replaces the values that differ between two otherwise identical runs --
/// keycodes, random IPs, verification codes, password hashes -- with
/// numbered placeholders, numbered in the order the runs created them.
#[derive(Default)]
pub struct Masker {
    seeded: std::collections::HashSet<String>,
    values: BTreeMap<String, String>,
}

impl Masker {
    /// Nothing the seed already held is random.
    pub fn new(seed_dump: &[String]) -> Masker {
        let seeded = seed_dump
            .iter()
            .flat_map(|l| {
                l.split_once(": ")
                    .unwrap()
                    .1
                    .split('\t')
                    .map(str::to_string)
                    .collect::<Vec<_>>()
            })
            .collect();
        Masker {
            seeded,
            values: BTreeMap::new(),
        }
    }

    /// Learn the random values in rows the seed did not have.
    pub fn learn(&mut self, dump: &[String]) {
        // Which columns hold randomness, by position after the table name.
        let random_cols: &[(&str, &[usize])] = &[
            ("users", &[2, 8]),
            ("domains", &[2, 6]),
            ("transactions", &[5]),
            ("email_codes", &[2]),
        ];
        for line in dump {
            let (table, rest) = line.split_once(": ").unwrap();
            let Some((_, cols)) = random_cols.iter().find(|(t, _)| *t == table) else {
                continue;
            };
            let fields: Vec<&str> = rest.split('\t').collect();
            for &c in *cols {
                let v = fields[c];
                if v.is_empty() || v == "NULL" || self.seeded.contains(v) || self.values.contains_key(v) {
                    continue;
                }
                let n = self.values.len() + 1;
                let placeholder = if v.starts_with("$2") {
                    format!("{}<bcrypt{n}>", &v[..7])
                } else {
                    format!("<rand{n}>")
                };
                self.values.insert(v.to_string(), placeholder);
            }
        }
    }

    pub fn apply(&self, s: &str) -> String {
        let mut by_len: Vec<_> = self.values.iter().collect();
        by_len.sort_by_key(|(k, _)| std::cmp::Reverse(k.len()));
        let mut s = s.to_string();
        for (k, v) in by_len {
            s = s.replace(k.as_str(), v);
        }
        s
    }
}
