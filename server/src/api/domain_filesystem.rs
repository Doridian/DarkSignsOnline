//! `domain_filesystem.php`: the files a domain keeps for its scripts.
//!
//! The owner can do anything to them. Anyone else needs the domain's
//! keycode -- which the domain's own scripts are handed when they run -- and
//! a file whose first line opens it up: `public` for every operation, or
//! `allowlist=read,append` for some. A domain's files are case-insensitive,
//! like the client's own filesystem, and are stored under the folded name.

use super::{authenticate, get_domain_info, upper};
use crate::ctx::{Ctx, Rec, Res, i, s};
use crate::php::{self, Zv};

fn is_public_operation_allowed(fileheader: &[u8], opname: &str) -> bool {
    let header = php::strtolower(php::trim(fileheader));
    if Zv::Str(header.clone()).is_empty() {
        return false;
    }
    if header.starts_with(b"public") {
        return true;
    }
    let Some(eq) = header.iter().position(|&c| c == b'=') else {
        return false;
    };
    if php::trim(&header[..eq]) != b"allowlist" {
        return false;
    }
    php::explode(b",", &header[eq + 1..])
        .into_iter()
        .any(|op| php::trim(op) == opname.as_bytes())
}

struct File {
    id: Zv,
    filename: Zv,
    contents: Zv,
}

impl File {
    fn from_rec(r: &Rec) -> File {
        File {
            id: r.get("id"),
            filename: r.get("filename"),
            contents: r.get("contents"),
        }
    }

    /// What the PHP got from a `verify_keycode` that returned nothing, for
    /// a name that folded away to nothing: every field NULL.
    fn none() -> File {
        File {
            id: Zv::Null,
            filename: Zv::Null,
            contents: Zv::Null,
        }
    }
}

struct Domain {
    d: Vec<u8>,
    info: Rec,
}

async fn verify_keycode(ctx: &mut Ctx, dom: &Domain, filename: &[u8], opname: &str, require_owner: bool) -> Res<File> {
    let is_owner = ctx.user_id() == dom.info.get("owner");
    let filename = php::strtolower(php::trim(filename));
    let err = |what: &str| {
        [
            &b"Error - ("[..],
            &filename,
            b") ",
            what.as_bytes(),
            b": ",
            &upper(&dom.d),
        ]
        .concat()
    };

    if !is_owner && require_owner {
        return ctx.die_error(err("Not owner"), 400);
    }
    if !ctx.req.request("is_local_script").is_str(b"true") || !is_owner {
        let keycode = ctx.req.request("keycode");
        if keycode != dom.info.get("keycode") {
            return ctx.die_error(err("Invalid Server Key"), 400);
        }
    }
    if Zv::Str(filename.clone()).is_empty() {
        return Ok(File::none());
    }

    let row = ctx
        .query_one(
            "SELECT * FROM domain_files WHERE domain = ? AND filename = ?",
            vec![dom.info.get("id").to_int().into(), filename.clone().into()],
        )
        .await?;
    if !is_owner {
        let Some(row) = &row else {
            return ctx.die_error(err("File not found"), 404);
        };
        let contents = row.get("contents").to_bytes();
        let header = php::explode(b"\r\n", &contents)[0];
        if !is_public_operation_allowed(header, opname) {
            return ctx.die_error(err("Private operation"), 403);
        }
    }
    Ok(match row {
        Some(row) => File::from_rec(&row),
        None => File {
            id: Zv::Int(-1),
            filename: Zv::Str(filename),
            contents: Zv::str(""),
        },
    })
}

/// Write a file's whole contents; empty contents delete it.
async fn write_file(ctx: &mut Ctx, dom: &Domain, file: &File, contents: Vec<u8>) -> Res {
    let is_new = matches!(file.id, Zv::Int(n) if n < 0);
    if contents.is_empty() {
        if is_new {
            return Ok(());
        }
        ctx.exec("DELETE FROM domain_files WHERE id = ?", vec![i(&file.id)])
            .await?;
    } else if is_new {
        ctx.exec(
            "INSERT INTO domain_files (domain, filename, contents) VALUES (?, ?, ?)",
            vec![dom.info.get("id").to_int().into(), s(&file.filename), contents.into()],
        )
        .await?;
    } else {
        ctx.exec(
            "UPDATE domain_files SET contents = ? WHERE id = ?",
            vec![contents.into(), i(&file.id)],
        )
        .await?;
    }
    Ok(())
}

pub async fn run(ctx: &mut Ctx) -> Res {
    authenticate(ctx).await?;
    ctx.print_returnwith("2000", 1);

    let d = php::trim(&ctx.req.request("d").to_bytes()).to_vec();
    let Some(info) = get_domain_info(ctx, &d).await? else {
        return ctx.die_error("Domain does not exist.", 400);
    };
    let dom = Domain { d, info };

    let fileserver = ctx.req.request("fileserver");
    if !fileserver.is_empty() {
        let file = verify_keycode(ctx, &dom, &fileserver.to_bytes(), "fileserver", false).await?;
        let maxlines = ctx.req.request("maxlines").to_int();
        let startline = ctx.req.request("startline").to_int().max(1);

        let contents = file.contents.to_bytes();
        let lines = php::explode(b"\r\n", &contents);
        let count = lines.len() as i64;
        let endline = if maxlines > 0 {
            (startline - 1).saturating_add(maxlines)
        } else {
            count
        };
        let mut x = startline - 1;
        while x < endline && x < count {
            ctx.echo(lines[x as usize]);
            ctx.echo("\r\n");
            x += 1;
        }
        return Ok(());
    }

    let write = ctx.req.request("write");
    if !write.is_empty() {
        let file = verify_keycode(ctx, &dom, &write.to_bytes(), "write", false).await?;
        let data = php::line_endings_to_dos(&ctx.req.request("filedata").to_bytes());
        return write_file(ctx, &dom, &file, data).await;
    }

    let append = ctx.req.request("append");
    if !append.is_empty() {
        let file = verify_keycode(ctx, &dom, &append.to_bytes(), "append", false).await?;
        let mut data = file.contents.to_bytes();
        data.extend_from_slice(&php::line_endings_to_dos(&ctx.req.request("filedata").to_bytes()));
        return write_file(ctx, &dom, &file, data).await;
    }

    let safeappend = ctx.req.request("safeappend");
    if !safeappend.is_empty() {
        // One line, signed with the name of whoever wrote it.
        let file = verify_keycode(ctx, &dom, &safeappend.to_bytes(), "safeappend", false).await?;
        let data = php::first_line(&ctx.req.request("filedata").to_bytes()).to_vec();
        let mut contents = file.contents.to_bytes();
        if !file.contents.is_empty() && !contents.ends_with(b"\r\n") {
            contents.extend_from_slice(b"\r\n");
        }
        contents.extend_from_slice(&ctx.user_field("username").to_bytes());
        contents.push(b':');
        contents.extend_from_slice(&data);
        contents.extend_from_slice(b"\r\n");
        return write_file(ctx, &dom, &file, contents).await;
    }

    let delete = ctx.req.request("delete");
    if !delete.is_empty() {
        let file = verify_keycode(ctx, &dom, &delete.to_bytes(), "delete", true).await?;
        return write_file(ctx, &dom, &file, Vec::new()).await;
    }

    let dir = ctx.req.request("dir");
    if !dir.is_empty() {
        verify_keycode(ctx, &dom, b"", "dir", true).await?;
        let rows = ctx
            .query(
                "SELECT filename FROM domain_files WHERE domain = ?",
                vec![dom.info.get("id").to_int().into()],
            )
            .await?;
        for row in rows {
            ctx.echo(row.get("filename").to_bytes());
            ctx.echo("\r\n");
        }
        return Ok(());
    }

    ctx.die_error("No action selected", 400)
}

#[cfg(test)]
mod tests {
    use super::is_public_operation_allowed;

    #[test]
    fn public_and_allowlists() {
        assert!(is_public_operation_allowed(b"  Public file", "write"));
        assert!(is_public_operation_allowed(b"AllowList = fileserver, append", "append"));
        assert!(!is_public_operation_allowed(b"allowlist=fileserver", "write"));
        assert!(!is_public_operation_allowed(b"0", "write"));
        assert!(!is_public_operation_allowed(b"secret", "fileserver"));
    }
}
