//! `domain_connect.php`: fetch the script listening on a domain's port, so
//! the client can run it.

use super::{authenticate, get_domain_info};
use crate::ctx::{Ctx, Res};
use crate::php;

/// Every case-insensitive `fileserver(` in `line`, each replaced as
/// `preg_replace('/(fileserver\()/i', $replacement, $line)` would.
fn replace_fileserver(line: &[u8], replacement: &[u8]) -> Vec<u8> {
    const NEEDLE: &[u8] = b"fileserver(";
    let mut out = Vec::with_capacity(line.len());
    let mut rest = line;
    while let Some(at) = rest.windows(NEEDLE.len()).position(|w| w.eq_ignore_ascii_case(NEEDLE)) {
        out.extend_from_slice(&rest[..at]);
        let m = &rest[at..at + NEEDLE.len()];
        php::preg_expand(replacement, &[Some(m), Some(m)], &mut out);
        rest = &rest[at + NEEDLE.len()..];
    }
    out.extend_from_slice(rest);
    out
}

/// `preg_replace('/^(\s*SERVER )(WRITE |APPEND )/i', $replacement, $line)`.
fn replace_server_write(line: &[u8], replacement: &[u8]) -> Vec<u8> {
    let ws = line
        .iter()
        .take_while(|c| matches!(c, b' ' | b'\t' | b'\n' | 0x0B | 0x0C | b'\r'))
        .count();
    let after = &line[ws..];
    let starts = |s: &[u8], p: &[u8]| s.len() >= p.len() && s[..p.len()].eq_ignore_ascii_case(p);
    if !starts(after, b"SERVER ") {
        return line.to_vec();
    }
    let g1_end = ws + 7;
    let rest = &line[g1_end..];
    let Some(kw) = [&b"WRITE "[..], b"APPEND "].into_iter().find(|kw| starts(rest, kw)) else {
        return line.to_vec();
    };
    let g2_end = g1_end + kw.len();
    let mut out = Vec::with_capacity(line.len() + replacement.len());
    php::preg_expand(
        replacement,
        &[
            Some(&line[..g2_end]),
            Some(&line[..g1_end]),
            Some(&line[g1_end..g2_end]),
        ],
        &mut out,
    );
    out.extend_from_slice(&line[g2_end..]);
    out
}

pub async fn run(ctx: &mut Ctx) -> Res {
    authenticate(ctx).await?;
    ctx.print_returnwith("4100", 1);

    let port = ctx.req.request("port").to_int();
    if !(1..=65535).contains(&port) {
        return ctx.die_error("not found", 400);
    }
    let d = php::strtolower(&ctx.req.request("d").to_bytes());
    let Some(info) = get_domain_info(ctx, &d).await? else {
        return ctx.die_error("not found", 404);
    };
    let row = ctx
        .query_one(
            "SELECT code FROM domain_scripts WHERE domain = ? AND port = ? AND ver = ?;",
            vec![info.get("id").to_int().into(), port.into(), ctx.ver.into()],
        )
        .await?;
    let Some(row) = row else {
        return ctx.die_error("not found", 404);
    };
    let code = row.idx(0).to_bytes();
    let ip = info.get("ip").to_bytes();
    let keycode = info.get("keycode").to_bytes();

    match ctx.ver {
        1 => {
            // Version 1 scripts are rewritten on the way out: they name
            // their own server through variables set in a preamble, and the
            // filesystem calls are handed the server's key and name.
            ctx.echo("4100");
            let mut script = Vec::new();
            for (k, v) in [(&b"$serverdomain = \""[..], &d[..]), (b"\"\r\n$serverip = \"", &ip[..])] {
                script.extend_from_slice(k);
                script.extend_from_slice(v);
            }
            script.extend_from_slice(format!("\"\r\n$serverport = {port}\r\n").as_bytes());

            let fs_repl = [&b"$1"[..], &keycode, b", ", &d, b", "].concat();
            let sw_repl = [&b"$1"[..], &keycode, b":---:", &d, b":----:$2"].concat();
            let lines: Vec<Vec<u8>> = php::explode(b"\r\n", &code)
                .into_iter()
                .map(|v| replace_server_write(&replace_fileserver(v, &fs_repl), &sw_repl))
                .collect();
            script.extend_from_slice(&lines.join(&b"\r\n"[..]));

            ctx.echo(&d);
            ctx.echo(format!("_{port}::"));
            ctx.echo(php::dso_b64_encode(&script));
            Ok(())
        }
        2 => {
            let host = info.get("host");
            let host = if host.is_empty() { ip.clone() } else { host.to_bytes() };
            let out = [
                &host[..],
                format!(":-:{port}:-:").as_bytes(),
                &ip,
                b":-:UID-",
                &info.get("owner").to_bytes(),
                b":-:",
                &keycode,
                b":-:",
                &php::dso_b64_encode(&code),
            ]
            .concat();
            ctx.echo(out);
            Ok(())
        }
        _ => ctx.die_error("not found", 400),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn rewrites_like_preg_replace() {
        assert_eq!(
            replace_fileserver(b"x = FileServer(\"a\") + fileserver(1)", b"$1K, d, "),
            b"x = FileServer(K, d, \"a\") + fileserver(K, d, 1)"
        );
        assert_eq!(
            replace_server_write(b"\t server Write foo", b"$1K:---:d:----:$2"),
            b"\t server K:---:d:----:Write foo"
        );
        assert_eq!(
            replace_server_write(b"SERVER DELETE foo", b"$1K$2"),
            b"SERVER DELETE foo"
        );
        assert_eq!(
            replace_server_write(b"x SERVER WRITE foo", b"$1K$2"),
            b"x SERVER WRITE foo"
        );
    }
}
