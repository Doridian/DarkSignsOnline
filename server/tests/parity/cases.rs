//! The requests, in the order they are sent. Later cases see what earlier
//! ones did: a domain registered here is connected to further down.
//!
//! `{{sql:...}}` in a target or body is replaced with the first value the
//! query returns at the moment the case runs, for codes the server made up.

use crate::harness::Db;

pub struct Case {
    pub name: String,
    pub method: String,
    pub target: String,
    /// The target as written, before any `{{sql:}}` was filled in, so that
    /// the record of a request does not change with a random code.
    pub target_shown: String,
    pub headers: Vec<(String, String)>,
    pub body: Option<Vec<u8>>,
    pub expects_mail: bool,
}

fn b64(data: &[u8]) -> String {
    const A: &[u8; 64] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    let mut out = String::new();
    for c in data.chunks(3) {
        let n =
            (u32::from(c[0]) << 16) | (u32::from(*c.get(1).unwrap_or(&0)) << 8) | u32::from(*c.get(2).unwrap_or(&0));
        out.push(A[(n >> 18) as usize & 63] as char);
        out.push(A[(n >> 12) as usize & 63] as char);
        out.push(if c.len() > 1 {
            A[(n >> 6) as usize & 63] as char
        } else {
            '='
        });
        out.push(if c.len() > 2 { A[n as usize & 63] as char } else { '=' });
    }
    out
}

/// The wire format's base64, for script uploads.
fn dso_b64(data: &[u8]) -> String {
    b64(data).replace('+', "-").replace('/', "_").replace('=', "")
}

fn sha256(data: &[u8]) -> String {
    use sha2::Digest;
    sha2::Sha256::digest(data).iter().map(|b| format!("{b:02x}")).collect()
}

fn fill(s: &str, db: &Db) -> String {
    let mut s = s.to_string();
    while let Some(start) = s.find("{{sql:") {
        let end = start + s[start..].find("}}").unwrap();
        let value = db.sql(&format!("USE dso; {}", &s[start + 6..end]));
        s.replace_range(start..end + 2, value.lines().next().unwrap_or(""));
    }
    s
}

impl Case {
    fn new(name: &str, method: &str, target: &str) -> Case {
        Case {
            name: name.into(),
            method: method.into(),
            target: target.into(),
            target_shown: target.into(),
            headers: Vec::new(),
            body: None,
            expects_mail: false,
        }
    }

    pub fn resolve(mut self, db: &Db) -> Case {
        self.target = fill(&self.target, db);
        self.body = self.body.map(|b| fill(&String::from_utf8(b).unwrap(), db).into_bytes());
        self
    }

    fn header(mut self, k: &str, v: &str) -> Case {
        self.headers.push((k.into(), v.into()));
        self
    }

    fn auth(self, user: &str) -> Case {
        let creds = b64(format!("{user}:{user}pass").as_bytes());
        self.header("Authorization", &format!("Basic {creds}"))
    }

    fn auth_raw(self, user: &str, pass: &str) -> Case {
        let creds = b64(format!("{user}:{pass}").as_bytes());
        self.header("Authorization", &format!("Basic {creds}"))
    }

    fn v2(self) -> Case {
        self.header("DSO-Protocol-Version", "2")
    }

    fn form(mut self, body: &str) -> Case {
        self.body = Some(body.as_bytes().to_vec());
        self.header("Content-Type", "application/x-www-form-urlencoded")
    }

    fn mails(mut self) -> Case {
        self.expects_mail = true;
        self
    }
}

fn get(name: &str, target: &str) -> Case {
    Case::new(name, "GET", target)
}

fn post(name: &str, target: &str, body: &str) -> Case {
    Case::new(name, "POST", target).form(body)
}

// Built up in sections, one per endpoint, rather than as one literal.
#[allow(clippy::vec_init_then_push)]
pub fn all() -> Vec<Case> {
    let mut c = Vec::new();

    // ---- the ones with no account ----------------------------------------
    c.push(get("time", "/api/time.php"));
    c.push(Case::new("time preflight", "OPTIONS", "/api/time.php"));
    c.push(get("z_online", "/api/z_online.php"));
    c.push(get("token public key", "/api/domain_token_public.php"));
    c.push(Case::new("auth preflight", "OPTIONS", "/api/auth.php").header("Access-Control-Request-Method", "POST"));
    c.push(Case::new(
        "dsmail preflight lower-case method",
        "options",
        "/api/dsmail.php",
    ));
    c.push(get("no such endpoint", "/api/nope.php"));
    c.push(get("no such page", "/nope.php"));

    // ---- auth ------------------------------------------------------------
    c.push(get("auth without credentials", "/api/auth.php"));
    c.push(get("auth without credentials v2", "/api/auth.php").v2());
    c.push(get("auth wrong password", "/api/auth.php").auth_raw("alice", "wrong"));
    c.push(get("auth unknown user", "/api/auth.php").auth_raw("mallory", "x"));
    c.push(get("auth empty password", "/api/auth.php").auth_raw("alice", ""));
    c.push(get("auth user 0", "/api/auth.php").auth_raw("0", "x"));
    c.push(get("auth inactive", "/api/auth.php").auth("carol"));
    c.push(get("auth bearer scheme", "/api/auth.php").header("Authorization", "Bearer abc"));
    c.push(get("auth lower-case scheme", "/api/auth.php").header("Authorization", "basic YWxpY2U6YWxpY2VwYXNz"));
    c.push(get("auth alice", "/api/auth.php").auth("alice"));
    c.push(get("auth alice v2", "/api/auth.php").auth("alice").v2());
    c.push(get("auth bank makes its domain", "/api/auth.php").auth("bank"));
    c.push(get("auth bank again", "/api/auth.php").auth("bank"));

    // ---- stats -----------------------------------------------------------
    c.push(get("stats", "/api/get_user_stats.php").auth("alice"));
    c.push(get("stats returnwith", "/api/get_user_stats.php?returnwith=4444").auth("alice"));
    c.push(get("stats returnwith junk", "/api/get_user_stats.php?returnwith=12abc").auth("alice"));
    c.push(get("stats returnwith zero", "/api/get_user_stats.php?returnwith=0").auth("alice"));
    c.push(
        get("stats v2", "/api/get_user_stats.php?returnwith=4444")
            .auth("alice")
            .v2(),
    );
    c.push(get("stats v2 by query", "/api/get_user_stats.php?dso_version=2").auth("alice"));
    c.push(
        get("stats v3", "/api/get_user_stats.php")
            .auth("alice")
            .header("DSO-Protocol-Version", "3"),
    );
    c.push(
        get(
            "stats v0 header falls to query",
            "/api/get_user_stats.php?dso_version=2",
        )
        .auth("alice")
        .header("DSO-Protocol-Version", "0"),
    );

    // ---- chat ------------------------------------------------------------
    c.push(get("chat backlog", "/api/chat.php?action=read"));
    c.push(get("chat after 1", "/api/chat.php?action=read&last=1"));
    c.push(get("chat after everything", "/api/chat.php?action=read&last=99"));
    c.push(post("chat read by post", "/api/chat.php", "action=read&last=2"));
    c.push(post(
        "chat send without account",
        "/api/chat.php",
        "action=send&message=hi",
    ));
    c.push(
        post("chat send", "/api/chat.php", "action=send&message=hello+there")
            .auth("alice")
            .v2(),
    );
    c.push(
        post("chat emote", "/api/chat.php", "action=send&message=dances&emote=1")
            .auth("alice")
            .v2(),
    );
    c.push(
        post("chat emote zero", "/api/chat.php", "action=send&message=sits&emote=0")
            .auth("alice")
            .v2(),
    );
    c.push(
        post(
            "chat control characters",
            "/api/chat.php",
            "action=send&message=%09a%0D%0Ab%7F%7Fc%01",
        )
        .auth("alice")
        .v2(),
    );
    c.push(
        post("chat unicode", "/api/chat.php", "action=send&message=%C3%BC%E2%9C%93")
            .auth("alice")
            .v2(),
    );
    c.push(
        post("chat nothing", "/api/chat.php", "action=send&message=+%0A+")
            .auth("alice")
            .v2(),
    );
    c.push(post("chat nothing v1", "/api/chat.php", "action=send&message=").auth("alice"));
    c.push(
        post("chat not utf-8", "/api/chat.php", "action=send&message=a%FFb")
            .auth("alice")
            .v2(),
    );
    c.push(post("chat no action", "/api/chat.php", "").auth("alice").v2());
    for i in 0..10 {
        c.push(
            post(
                &format!("chat flood {i}"),
                "/api/chat.php",
                &format!("action=send&message=spam{i}"),
            )
            .auth("bob")
            .v2(),
        );
    }
    c.push(get("chat after the flood", "/api/chat.php?action=read&last=3"));

    // ---- dsmail ----------------------------------------------------------
    c.push(get("mail inbox", "/api/dsmail.php?action=inbox").auth("alice"));
    c.push(get("mail inbox after 1", "/api/dsmail.php?action=inbox&last=1").auth("alice"));
    c.push(
        get(
            "mail inbox v2 keeps the prefix",
            "/api/dsmail.php?action=inbox&returnwith=7001",
        )
        .auth("alice")
        .v2(),
    );
    c.push(
        post(
            "mail send",
            "/api/dsmail.php",
            "action=send&to=bob&subject=Hi+bob%0Aignored&message=line1%0D%0Aline2",
        )
        .auth("alice")
        .v2(),
    );
    c.push(
        post(
            "mail send again is ignored",
            "/api/dsmail.php",
            "action=send&to=bob&subject=Hi+bob&message=line1%0D%0Aline2",
        )
        .auth("alice")
        .v2(),
    );
    c.push(
        post(
            "mail send to two",
            "/api/dsmail.php",
            "action=send&to=bob,dave&subject=Both&message=m",
        )
        .auth("alice")
        .v2(),
    );
    c.push(
        post(
            "mail send to unknown",
            "/api/dsmail.php",
            "action=send&to=bob,nobody&subject=x&message=m",
        )
        .auth("alice")
        .v2(),
    );
    c.push(
        post(
            "mail send to eleven",
            "/api/dsmail.php",
            "action=send&to=a,b,c,d,e,f,g,h,i,j,k&subject=x&message=m",
        )
        .auth("alice")
        .v2(),
    );
    c.push(
        post("mail send to nobody", "/api/dsmail.php", "action=send")
            .auth("alice")
            .v2(),
    );
    c.push(get("mail inbox bob", "/api/dsmail.php?action=inbox").auth("bob"));
    c.push(
        post(
            "mail script to self",
            "/api/dsmail.php",
            "action=script_send_to_self&from=boss@alice.com&subject=Job&message=Do+it",
        )
        .auth("alice")
        .v2(),
    );
    c.push(
        post(
            "mail script to self again replaces",
            "/api/dsmail.php",
            "action=script_send_to_self&from=boss@alice.com&subject=Job&message=Do+it",
        )
        .auth("alice")
        .v2(),
    );
    c.push(
        post(
            "mail script named server",
            "/api/dsmail.php",
            "action=script_send_to_self&server=alice.com&from=x_y-z@www.alice.com&subject=S&message=M",
        )
        .auth("alice")
        .v2(),
    );
    c.push(
        post(
            "mail script bad from name",
            "/api/dsmail.php",
            "action=script_send_to_self&from=bad+name@alice.com&subject=S&message=M",
        )
        .auth("alice")
        .v2(),
    );
    c.push(
        post(
            "mail script long from name",
            "/api/dsmail.php",
            &format!("action=script_send_to_self&from={}@alice.com", "a".repeat(33)),
        )
        .auth("alice")
        .v2(),
    );
    c.push(
        post(
            "mail script other owner",
            "/api/dsmail.php",
            "action=script_send_to_self&from=x@bob.net&subject=S&message=M",
        )
        .auth("alice")
        .v2(),
    );
    c.push(
        post(
            "mail script no at",
            "/api/dsmail.php",
            "action=script_send_to_self&from=boss",
        )
        .auth("alice")
        .v2(),
    );
    c.push(
        post(
            "mail script unknown server",
            "/api/dsmail.php",
            "action=script_send_to_self&server=nope.com&from=a@alice.com",
        )
        .auth("alice")
        .v2(),
    );
    c.push(
        post(
            "mail script v1",
            "/api/dsmail.php",
            "action=script_send_to_self&from=boss",
        )
        .auth("alice"),
    );
    c.push(get("mail no action", "/api/dsmail.php").auth("alice").v2());
    c.push(get("mail inbox after", "/api/dsmail.php?action=inbox&last=2").auth("alice"));

    // ---- domain_register -------------------------------------------------
    c.push(get("register prices", "/api/domain_register.php?prices").auth("alice"));
    c.push(
        get("register prices v2", "/api/domain_register.php?prices=1")
            .auth("alice")
            .v2(),
    );
    c.push(get("register taken", "/api/domain_register.php?d=alice.com").auth("alice"));
    c.push(
        get("register taken v2", "/api/domain_register.php?d=ALICE.com")
            .auth("alice")
            .v2(),
    );
    c.push(
        get("register domain", "/api/domain_register.php?d=NewDomain.com")
            .auth("alice")
            .v2(),
    );
    c.push(
        get(
            "register with fixed ip",
            "/api/domain_register.php?d=fixed.net&fixedip=12.34.56.78",
        )
        .auth("alice")
        .v2(),
    );
    c.push(
        get(
            "register bad fixed ip",
            "/api/domain_register.php?d=other.net&fixedip=1.2.3",
        )
        .auth("alice")
        .v2(),
    );
    c.push(
        get(
            "register fixed ip zero",
            "/api/domain_register.php?d=zeroip.org&fixedip=0",
        )
        .auth("alice")
        .v2(),
    );
    c.push(
        get("register bad extension", "/api/domain_register.php?d=x.foo")
            .auth("alice")
            .v2(),
    );
    c.push(get("register bad extension v1", "/api/domain_register.php?d=x.foo").auth("alice"));
    c.push(
        get("register ip", "/api/domain_register.php?d=13.13.13.13")
            .auth("alice")
            .v2(),
    );
    c.push(
        get("register ip with zeros", "/api/domain_register.php?d=014.1.1.01")
            .auth("alice")
            .v2(),
    );
    c.push(
        get("register out of range ip", "/api/domain_register.php?d=1.2.3.999")
            .auth("alice")
            .v2(),
    );
    c.push(
        get("register subdomain", "/api/domain_register.php?d=shop.alice.com")
            .auth("alice")
            .v2(),
    );
    c.push(
        get(
            "register deep subdomain",
            "/api/domain_register.php?d=a.b.alice.com&fixedip=12.34.56.79",
        )
        .auth("alice")
        .v2(),
    );
    c.push(
        get(
            "register subdomain of someone else",
            "/api/domain_register.php?d=x.bob.net",
        )
        .auth("alice")
        .v2(),
    );
    c.push(
        get(
            "register subdomain of nothing",
            "/api/domain_register.php?d=a.b.nope.com",
        )
        .auth("alice")
        .v2(),
    );
    c.push(
        get("register too poor", "/api/domain_register.php?d=rich.dsn")
            .auth("bob")
            .v2(),
    );
    c.push(get("register broke", "/api/domain_register.php?d=cheap.ru").auth("dave"));
    c.push(
        get("register one label", "/api/domain_register.php?d=localhost")
            .auth("alice")
            .v2(),
    );
    c.push(get("register nothing", "/api/domain_register.php").auth("alice").v2());
    c.push(
        get("register a dollar", "/api/domain_register.php?d=pay$2.org")
            .auth("alice")
            .v2(),
    );
    c.push(
        get(
            "register returnwith",
            "/api/domain_register.php?d=x.foo&returnwith=4005",
        )
        .auth("alice"),
    );

    // ---- my_domains, lookup, meta, ping -----------------------------------
    c.push(get("my domains", "/api/my_domains.php?type=domain").auth("alice"));
    c.push(get("my ips", "/api/my_domains.php?type=+IP+").auth("alice"));
    c.push(get("my subdomains", "/api/my_domains.php?type=subdomain&domain=alice.com").auth("alice"));
    c.push(
        get(
            "my subdomains not mine",
            "/api/my_domains.php?type=subdomain&domain=bob.net",
        )
        .auth("alice"),
    );
    c.push(
        get(
            "my subdomains of nothing",
            "/api/my_domains.php?type=subdomain&domain=nope.com",
        )
        .auth("alice"),
    );
    c.push(get("my bad type", "/api/my_domains.php?type=x").auth("alice").v2());
    c.push(post("my type by post is ignored", "/api/my_domains.php", "type=domain").auth("alice"));
    c.push(get("lookup", "/api/lookup.php?d=alice.com").auth("bob"));
    c.push(get("lookup padded", "/api/lookup.php?d=+alice.com+").auth("bob").v2());
    c.push(get("lookup unknown", "/api/lookup.php?d=nope.com").auth("bob").v2());
    c.push(get("meta ip of", "/api/domain_meta.php?getip=alice.com").auth("bob"));
    c.push(
        get("meta ip of unknown", "/api/domain_meta.php?getip=nope.com")
            .auth("bob")
            .v2(),
    );
    c.push(get("meta name of ip with host", "/api/domain_meta.php?getdomain=11.0.1.1").auth("bob"));
    c.push(get("meta name of bare ip", "/api/domain_meta.php?getdomain=11.9.9.9").auth("bob"));
    c.push(
        get("meta name of unknown", "/api/domain_meta.php?getdomain=1.1.1.1")
            .auth("bob")
            .v2(),
    );
    c.push(get("meta nothing", "/api/domain_meta.php").auth("bob"));
    c.push(get("ping host", "/api/ping.php?domain=alice.com&port=0").auth("bob"));
    c.push(get("ping port v1", "/api/ping.php?domain=alice.com&port=80").auth("bob"));
    c.push(get("ping port v2 only", "/api/ping.php?domain=alice.com&port=81").auth("bob"));
    c.push(
        get("ping port v2", "/api/ping.php?domain=alice.com&port=81")
            .auth("bob")
            .v2(),
    );
    c.push(get("ping unknown", "/api/ping.php?domain=nope.com&port=0").auth("bob"));

    // ---- domain_connect, domain_download ---------------------------------
    c.push(get("connect v1 rewrites", "/api/domain_connect.php?d=ALICE.COM&port=80").auth("bob"));
    c.push(
        get(
            "connect v1 returnwith",
            "/api/domain_connect.php?d=bob.net&port=22&returnwith=4111",
        )
        .auth("alice"),
    );
    c.push(
        get("connect v2", "/api/domain_connect.php?d=alice.com&port=80")
            .auth("bob")
            .v2(),
    );
    c.push(
        get("connect v2 compiled", "/api/domain_connect.php?d=alice.com&port=81")
            .auth("bob")
            .v2(),
    );
    c.push(
        get("connect v2 bare ip", "/api/domain_connect.php?d=11.9.9.9&port=1")
            .auth("bob")
            .v2(),
    );
    c.push(
        get("connect port zero", "/api/domain_connect.php?d=alice.com&port=0")
            .auth("bob")
            .v2(),
    );
    c.push(
        get(
            "connect port too high",
            "/api/domain_connect.php?d=alice.com&port=65536",
        )
        .auth("bob"),
    );
    c.push(
        get("connect unknown", "/api/domain_connect.php?d=nope.com&port=80")
            .auth("bob")
            .v2(),
    );
    c.push(
        get("connect nothing there", "/api/domain_connect.php?d=alice.com&port=99")
            .auth("bob")
            .v2(),
    );
    c.push(
        get("connect v3", "/api/domain_connect.php?d=alice.com&port=80")
            .auth("bob")
            .header("DSO-Protocol-Version", "3"),
    );
    c.push(
        get(
            "download",
            "/api/domain_download.php?d=alice.com&port=80&filename=got.ds",
        )
        .auth("bob"),
    );
    c.push(
        get(
            "download v2",
            "/api/domain_download.php?d=+alice.com&port=80&filename=got.ds",
        )
        .auth("bob")
        .v2(),
    );
    c.push(
        get("download compiled", "/api/domain_download.php?d=alice.com&port=81")
            .auth("bob")
            .v2(),
    );
    c.push(
        get("download nothing there", "/api/domain_download.php?d=alice.com&port=99")
            .auth("bob")
            .v2(),
    );
    c.push(get("download unknown", "/api/domain_download.php?d=nope.com&port=99").auth("bob"));

    // ---- domain_upload, domain_close -------------------------------------
    let script = dso_b64(b"Say \"up\"\nfileserver(1)\r  SERVER WRITE x\r\n");
    c.push(
        post(
            "upload v2",
            "/api/domain_upload.php",
            &format!("d=alice.com&port=82&filedata={script}"),
        )
        .auth("alice")
        .v2(),
    );
    c.push(
        post(
            "upload v1",
            "/api/domain_upload.php",
            &format!("d=alice.com&port=82&filedata={script}"),
        )
        .auth("alice"),
    );
    c.push(
        post(
            "upload replaces",
            "/api/domain_upload.php",
            "d=alice.com&port=82&filedata=U2F5IDI",
        )
        .auth("alice")
        .v2(),
    );
    c.push(
        post(
            "upload to a dollar domain",
            "/api/domain_upload.php",
            &format!("d=pay$1.org&port=5&filedata={script}"),
        )
        .auth("alice"),
    );
    c.push(
        get(
            "connect to what was uploaded v1",
            "/api/domain_connect.php?d=alice.com&port=82",
        )
        .auth("bob"),
    );
    c.push(
        get(
            "connect to a dollar domain",
            "/api/domain_connect.php?d=pay$1.org&port=5",
        )
        .auth("bob"),
    );
    c.push(
        get(
            "connect to what was uploaded v2",
            "/api/domain_connect.php?d=alice.com&port=82",
        )
        .auth("bob")
        .v2(),
    );
    c.push(
        post(
            "upload not mine",
            "/api/domain_upload.php",
            "d=alice.com&port=83&filedata=eA",
        )
        .auth("bob")
        .v2(),
    );
    c.push(
        post(
            "upload bad port",
            "/api/domain_upload.php",
            "d=alice.com&port=0&filedata=eA",
        )
        .auth("alice")
        .v2(),
    );
    c.push(
        post(
            "upload unknown",
            "/api/domain_upload.php",
            "d=nope.com&port=1&filedata=eA",
        )
        .auth("alice")
        .v2(),
    );
    c.push(
        get(
            "upload by get is ignored",
            "/api/domain_upload.php?d=alice.com&port=84&filedata=eA",
        )
        .auth("alice")
        .v2(),
    );
    c.push(
        get("close", "/api/domain_close.php?d=alice.com&port=82")
            .auth("alice")
            .v2(),
    );
    c.push(
        get("close again", "/api/domain_close.php?d=alice.com&port=82")
            .auth("alice")
            .v2(),
    );
    c.push(get("close v1 port", "/api/domain_close.php?d=alice.com&port=82").auth("alice"));
    c.push(
        get("close not mine", "/api/domain_close.php?d=alice.com&port=80")
            .auth("bob")
            .v2(),
    );
    c.push(
        get("close unknown", "/api/domain_close.php?d=nope.com&port=80")
            .auth("bob")
            .v2(),
    );

    // ---- domain_filesystem ----------------------------------------------
    let fs = "/api/domain_filesystem.php";
    let key = "keycode=AliceComKeycode1";
    c.push(
        get(
            "fs owner read",
            &format!("{fs}?d=alice.com&fileserver=public.txt&is_local_script=true"),
        )
        .auth("alice"),
    );
    c.push(
        get(
            "fs owner read lines",
            &format!("{fs}?d=alice.com&fileserver=PUBLIC.TXT&is_local_script=true&startline=2&maxlines=2"),
        )
        .auth("alice"),
    );
    c.push(
        get(
            "fs owner read from",
            &format!("{fs}?d=alice.com&fileserver=public.txt&is_local_script=true&startline=3"),
        )
        .auth("alice")
        .v2(),
    );
    c.push(
        get(
            "fs owner read past end",
            &format!("{fs}?d=alice.com&fileserver=public.txt&is_local_script=true&startline=9"),
        )
        .auth("alice"),
    );
    c.push(
        get(
            "fs owner read missing",
            &format!("{fs}?d=alice.com&fileserver=missing.txt&is_local_script=true"),
        )
        .auth("alice"),
    );
    c.push(
        get(
            "fs owner read blank name",
            &format!("{fs}?d=alice.com&fileserver=+&is_local_script=true"),
        )
        .auth("alice"),
    );
    c.push(
        get(
            "fs owner without key",
            &format!("{fs}?d=alice.com&fileserver=public.txt"),
        )
        .auth("alice")
        .v2(),
    );
    c.push(
        get(
            "fs owner with key",
            &format!("{fs}?d=alice.com&fileserver=private.txt&{key}"),
        )
        .auth("alice")
        .v2(),
    );
    c.push(
        get(
            "fs other public",
            &format!("{fs}?d=alice.com&fileserver=public.txt&{key}"),
        )
        .auth("bob")
        .v2(),
    );
    c.push(
        get(
            "fs other local script still needs key",
            &format!("{fs}?d=alice.com&fileserver=public.txt&is_local_script=true"),
        )
        .auth("bob")
        .v2(),
    );
    c.push(
        get(
            "fs other wrong key",
            &format!("{fs}?d=alice.com&fileserver=public.txt&keycode=nope"),
        )
        .auth("bob")
        .v2(),
    );
    c.push(
        get(
            "fs other private",
            &format!("{fs}?d=alice.com&fileserver=private.txt&{key}"),
        )
        .auth("bob")
        .v2(),
    );
    c.push(
        get(
            "fs other missing",
            &format!("{fs}?d=alice.com&fileserver=missing.txt&{key}"),
        )
        .auth("bob")
        .v2(),
    );
    c.push(
        get(
            "fs other allowlisted",
            &format!("{fs}?d=alice.com&fileserver=allow.txt&{key}"),
        )
        .auth("bob")
        .v2(),
    );
    c.push(
        post(
            "fs other write not allowlisted",
            fs,
            &format!("d=alice.com&write=allow.txt&filedata=x&{key}"),
        )
        .auth("bob")
        .v2(),
    );
    c.push(
        post(
            "fs other safeappend allowlisted",
            fs,
            &format!("d=alice.com&safeappend=allow.txt&filedata=hi%0Dthere&{key}"),
        )
        .auth("bob")
        .v2(),
    );
    c.push(
        post(
            "fs other append public",
            fs,
            &format!("d=alice.com&append=public.txt&filedata=%0Abob&{key}"),
        )
        .auth("bob")
        .v2(),
    );
    c.push(
        post("fs other delete", fs, &format!("d=alice.com&delete=public.txt&{key}"))
            .auth("bob")
            .v2(),
    );
    c.push(
        get("fs other dir", &format!("{fs}?d=alice.com&dir=1&{key}"))
            .auth("bob")
            .v2(),
    );
    c.push(get("fs owner dir", &format!("{fs}?d=alice.com&dir=1&is_local_script=true")).auth("alice"));
    c.push(
        post(
            "fs owner write new",
            fs,
            "d=alice.com&write=New.txt&filedata=a%0Ab%0Dc&is_local_script=true",
        )
        .auth("alice")
        .v2(),
    );
    c.push(
        post(
            "fs owner append",
            fs,
            "d=alice.com&append=new.txt&filedata=d%0A&is_local_script=true",
        )
        .auth("alice")
        .v2(),
    );
    c.push(
        post(
            "fs owner safeappend",
            fs,
            "d=alice.com&safeappend=new.txt&filedata=e%0Af&is_local_script=true",
        )
        .auth("alice")
        .v2(),
    );
    c.push(
        post(
            "fs owner safeappend after a zero",
            fs,
            "d=alice.com&safeappend=zero.txt&filedata=z&is_local_script=true",
        )
        .auth("alice")
        .v2(),
    );
    c.push(
        post(
            "fs owner safeappend new file",
            fs,
            "d=alice.com&safeappend=fresh.txt&filedata=f&is_local_script=true",
        )
        .auth("alice")
        .v2(),
    );
    c.push(
        get(
            "fs owner read new",
            &format!("{fs}?d=alice.com&fileserver=new.txt&is_local_script=true"),
        )
        .auth("alice"),
    );
    c.push(
        post(
            "fs owner write empty deletes",
            fs,
            "d=alice.com&write=new.txt&filedata=&is_local_script=true",
        )
        .auth("alice")
        .v2(),
    );
    c.push(
        post(
            "fs owner write empty nothing",
            fs,
            "d=alice.com&write=never.txt&is_local_script=true",
        )
        .auth("alice")
        .v2(),
    );
    c.push(
        post(
            "fs owner delete",
            fs,
            "d=alice.com&delete=fresh.txt&is_local_script=true",
        )
        .auth("alice")
        .v2(),
    );
    c.push(
        post(
            "fs owner write blank name",
            fs,
            "d=alice.com&write=+&filedata=x&is_local_script=true",
        )
        .auth("alice")
        .v2(),
    );
    c.push(get("fs no action", &format!("{fs}?d=alice.com")).auth("alice").v2());
    c.push(
        get("fs unknown domain", &format!("{fs}?d=nope.com&dir=1"))
            .auth("alice")
            .v2(),
    );
    c.push(get("fs unknown domain v1", &format!("{fs}?d=nope.com&dir=1")).auth("alice"));

    // ---- domain_token, domain_unregister ---------------------------------
    c.push(get("token", "/api/domain_token.php?d=Alice.com&info=hello").auth("alice"));
    c.push(
        get(
            "token unicode info",
            "/api/domain_token.php?d=alice.com&info=%C3%A9%F0%9F%98%80%22%2F%5C%0A",
        )
        .auth("alice"),
    );
    c.push(get("token no info", "/api/domain_token.php?d=alice.com").auth("bob"));
    c.push(
        get(
            "token not owned local",
            "/api/domain_token.php?d=alice.com&is_local_script=true",
        )
        .auth("bob")
        .v2(),
    );
    c.push(get("token no domain", "/api/domain_token.php").auth("bob").v2());
    c.push(
        get("token unknown", "/api/domain_token.php?d=nope.com")
            .auth("bob")
            .v2(),
    );
    c.push(get("token info not utf-8", "/api/domain_token.php?d=alice.com&info=%FF").auth("bob"));
    c.push(
        post("unregister not mine", "/api/domain_unregister.php", "d=alice.com")
            .auth("bob")
            .v2(),
    );
    c.push(
        post("unregister unknown", "/api/domain_unregister.php", "d=nope.com")
            .auth("bob")
            .v2(),
    );
    c.push(
        get(
            "unregister by get is ignored",
            "/api/domain_unregister.php?d=newdomain.com",
        )
        .auth("alice")
        .v2(),
    );
    c.push(
        post("unregister", "/api/domain_unregister.php", "d=+NewDomain.com")
            .auth("alice")
            .v2(),
    );

    // ---- file_database ---------------------------------------------------
    let fdb = "/api/file_database.php";
    c.push(get("library category", &format!("{fdb}?returnwith=4301&getcategory=Games")).auth("bob"));
    c.push(
        get(
            "library category with spaces",
            &format!("{fdb}?returnwith=4301&getcategory=Tools+(Hacking)"),
        )
        .auth("bob"),
    );
    c.push(
        get("library category v2", &format!("{fdb}?getcategory=Games"))
            .auth("bob")
            .v2(),
    );
    c.push(get("library get", &format!("{fdb}?returnwith=4304&getfile=1")).auth("bob"));
    c.push(get("library get unicode", &format!("{fdb}?getfile=2")).auth("bob"));
    c.push(get("library get deleted", &format!("{fdb}?getfile=3")).auth("bob").v2());
    c.push(
        get("library get junk id", &format!("{fdb}?getfile=abc"))
            .auth("bob")
            .v2(),
    );
    c.push(
        get("library get huge id", &format!("{fdb}?getfile=99999999999999999999"))
            .auth("bob")
            .v2(),
    );
    c.push(get("library mine", &format!("{fdb}?returnwith=4302&getforremoval=a")).auth("alice"));
    c.push(get("library remove not mine", &format!("{fdb}?returnwith=4303&removenow=1")).auth("bob"));
    c.push(get("library remove", &format!("{fdb}?returnwith=4303&removenow=1")).auth("alice"));
    c.push(post(
        "library upload",
        fdb,
        "returnwith=4300&category=Games&title=Pong&filesize=8&version=1.0&description=Bats+%C3%BC&shortfilename=Pong.DS&filedata=Say+%22pong%22",
    )
    .auth("bob"));
    c.push(
        post(
            "library upload again",
            fdb,
            "category=Games&title=Pong&version=1.0&shortfilename=pong.ds&filedata=x",
        )
        .auth("bob")
        .v2(),
    );
    c.push(
        post("library upload bad name", fdb, "category=Games&shortfilename=a/b.ds")
            .auth("bob")
            .v2(),
    );
    c.push(
        post("library upload bare", fdb, "shortfilename=bare.ds")
            .auth("bob")
            .v2(),
    );
    c.push(get("library category after", &format!("{fdb}?getcategory=Games")).auth("bob"));
    c.push(get("library nothing", fdb).auth("bob").v2());

    // ---- libraries -------------------------------------------------------
    let data = "lib data ü";
    c.push(
        get(
            "lib get",
            "/api/libraries.php?get=a948904f2f0f479b8f8197694b30184b0d2ed1c1cd2a1ec0fb85d299a192a447",
        )
        .auth("bob"),
    );
    c.push(get("lib get missing", "/api/libraries.php?get=00").auth("bob").v2());
    c.push(
        post("lib put mismatch", "/api/libraries.php", "put=abc&data=x")
            .auth("bob")
            .v2(),
    );
    c.push(
        post(
            "lib put",
            "/api/libraries.php",
            &format!("put={}&data=lib+data+%C3%BC", sha256(data.as_bytes())),
        )
        .auth("bob")
        .v2(),
    );
    c.push(
        post(
            "lib put twice",
            "/api/libraries.php",
            &format!("put={}&data=lib+data+%C3%BC", sha256(data.as_bytes())),
        )
        .auth("bob")
        .v2(),
    );
    c.push(
        post(
            "lib put without data",
            "/api/libraries.php",
            &format!("put={}", sha256(b"")),
        )
        .auth("bob")
        .v2(),
    );
    c.push(get("lib nothing", "/api/libraries.php").auth("bob"));

    // ---- textspace -------------------------------------------------------
    c.push(get("text download", "/api/textspace.php?download=5").auth("bob"));
    c.push(
        get("text download empty channel", "/api/textspace.php?download=9")
            .auth("bob")
            .v2(),
    );
    c.push(
        get("text download bad channel", "/api/textspace.php?download=-1")
            .auth("bob")
            .v2(),
    );
    c.push(
        post("text upload channel 1", "/api/textspace.php", "upload=1&textdata=x")
            .auth("bob")
            .v2(),
    );
    c.push(
        post("text upload", "/api/textspace.php", "upload=7&textdata=new+%0Atext")
            .auth("bob")
            .v2(),
    );
    c.push(
        post("text upload without text", "/api/textspace.php", "upload=8")
            .auth("bob")
            .v2(),
    );
    c.push(get("text download uploaded", "/api/textspace.php?download=7").auth("bob"));
    c.push(get("text nothing", "/api/textspace.php").auth("bob").v2());

    // ---- transfer --------------------------------------------------------
    let tr = "/api/transfer.php";
    c.push(get("transfer v1", &format!("{tr}?to=bob&amount=100&description=gift")).auth("alice"));
    c.push(
        get("transfer v2", &format!("{tr}?to=bob&amount=12abc&description=more"))
            .auth("alice")
            .v2(),
    );
    c.push(
        get(
            "transfer too much",
            &format!("{tr}?to=alice&amount=1000000&description=x"),
        )
        .auth("bob"),
    );
    c.push(
        get(
            "transfer too much v2",
            &format!("{tr}?to=alice&amount=1000000&description=x"),
        )
        .auth("bob")
        .v2(),
    );
    c.push(
        get("transfer to self", &format!("{tr}?to=alice&amount=1&description=x"))
            .auth("alice")
            .v2(),
    );
    c.push(get("transfer negative", &format!("{tr}?to=bob&amount=-5&description=x")).auth("alice"));
    c.push(
        get("transfer to nobody", &format!("{tr}?to=nobody&amount=1&description=x"))
            .auth("alice")
            .v2(),
    );
    c.push(
        get("transfer without description", &format!("{tr}?to=bob&amount=1"))
            .auth("alice")
            .v2(),
    );
    c.push(get("stats after transfers", "/api/get_user_stats.php").auth("bob"));

    // ---- the website -----------------------------------------------------
    c.push(get("home", "/"));
    c.push(get("home by name", "/index.php"));
    c.push(get("terms", "/termsofuse.php"));
    c.push(Case::new("terms head", "HEAD", "/termsofuse.php"));
    c.push(get("sign-up form", "/create_account.php"));
    c.push(get("forgot form", "/forgot_password.php"));
    c.push(get("verify without code", "/verify.php"));
    c.push(get("verify bad code", "/verify.php?code=nope"));
    c.push(get("verify carol", "/verify.php?code=CarolVerifyCode1"));
    c.push(get("verify carol again", "/verify.php?code=CarolVerifyCode1"));
    c.push(get("auth carol now", "/api/auth.php").auth("carol"));

    let ca = "/create_account.php";
    let ok = "agreetos=yes&agecheck=yes";
    c.push(post(
        "sign-up without agreeing",
        ca,
        "username=newbie&password=secret1&email=n%40example.com&agreetos=yes",
    ));
    c.push(post(
        "sign-up short name",
        ca,
        &format!("username=ab&password=secret1&email=n%40example.com&{ok}"),
    ));
    c.push(post(
        "sign-up long name",
        ca,
        &format!(
            "username={}&password=secret1&email=n%40example.com&{ok}",
            "a".repeat(21)
        ),
    ));
    c.push(post(
        "sign-up short password",
        ca,
        &format!("username=newbie&password=12345&email=n%40example.com&{ok}"),
    ));
    c.push(post(
        "sign-up bad email",
        ca,
        &format!("username=newbie&password=secret1&email=not-an-email&{ok}"),
    ));
    c.push(post(
        "sign-up local email",
        ca,
        &format!("username=newbie&password=secret1&email=a%40localhost&{ok}"),
    ));
    c.push(post(
        "sign-up bad name",
        ca,
        &format!("username=new_bie&password=secret1&email=n%40example.com&{ok}"),
    ));
    c.push(post(
        "sign-up email taken",
        ca,
        &format!("username=newbie&password=secret1&email=alice%40example.com&{ok}"),
    ));
    c.push(post(
        "sign-up name taken",
        ca,
        &format!("username=+Alice+&password=secret1&email=x%40example.com&{ok}"),
    ));
    c.push(
        post(
            "sign-up",
            ca,
            &format!("username=New+Bie&password=secret1&email=O%27Brien%40example.com&{ok}"),
        )
        .mails(),
    );
    c.push(post(
        "sign-up quoted email taken",
        ca,
        &format!("username=other&password=secret1&email=O%27Brien%40example.com&{ok}"),
    ));
    c.push(get("sign-up not yet verified", "/api/auth.php").auth_raw("new-bie", "secret1"));
    c.push(get(
        "verify sign-up",
        "/verify.php?code={{sql:SELECT emailverifycode FROM users WHERE username='new-bie'}}",
    ));
    c.push(get("sign-up can log in", "/api/auth.php").auth_raw("new-bie", "secret1"));
    c.push(get("sign-up by get is the form", &format!("{ca}?username=x&{ok}")));

    let fp = "/forgot_password.php";
    let fp2 = "/forgot_password2.php";
    c.push(post("forgot wrong pair", fp, "username=bob&email=alice%40example.com"));
    c.push(post("forgot only one", fp, "username=bob"));
    c.push(post("forgot", fp, "username=+BOB&email=bob%40example.com").mails());
    c.push(get("reset without code", fp2));
    c.push(get("reset expired", &format!("{fp2}?code=BobExpiredCode01")));
    c.push(get("reset form", &format!("{fp2}?code=BobResetCode0001")));
    c.push(get("reset form any case", &format!("{fp2}?code=bobresetcode0001")));
    c.push(post("reset short password", fp2, "code=BobResetCode0001&password=123"));
    c.push(post("reset", fp2, "code=BobResetCode0001&password=newbobpass"));
    c.push(post("reset reused", fp2, "code=BobResetCode0001&password=newbobpass"));
    c.push(get("bob old password", "/api/auth.php").auth("bob"));
    c.push(get("bob new password", "/api/auth.php").auth_raw("bob", "newbobpass"));
    c.push(get(
        "reset mailed code",
        &format!("{fp2}?code={{{{sql:SELECT code FROM email_codes WHERE user=2 AND code NOT LIKE 'Bob%'}}}}"),
    ));

    c
}
