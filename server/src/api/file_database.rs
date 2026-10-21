//! `file_database.php`: the script library players publish to and download
//! from. Every answer carries the legacy 2000 prefix (or the caller's
//! `returnwith`), whatever the protocol version.

use super::{authenticate, id_to_user, now};
use crate::ctx::{Ctx, Res, i, s};
use crate::php::{self, Zv};

fn or_empty(z: Zv) -> Zv {
    if z.is_null() { Zv::str("") } else { z }
}

pub async fn run(ctx: &mut Ctx) -> Res {
    authenticate(ctx).await?;
    ctx.print_returnwith("2000", -1);
    let uid = ctx.user_id();
    let ver = ctx.ver;

    let getfile = ctx.req.request("getfile");
    if !getfile.is_empty() {
        let row = ctx
            .query_one(
                "SELECT filename, filedata FROM file_database WHERE id = ? AND deleted = 0 AND ver = ?",
                vec![i(&getfile), ver.into()],
            )
            .await?;
        let Some(row) = row else {
            return ctx.die_error("File not found.", 404);
        };
        ctx.echo(row.get("filename").to_bytes());
        ctx.echo(":");
        return ctx.die(row.get("filedata").to_bytes());
    }

    let removenow = ctx.req.request("removenow");
    if !removenow.is_empty() {
        ctx.exec(
            "UPDATE file_database SET deleted = 1 WHERE id = ? AND owner = ? AND ver = ?",
            vec![i(&removenow), i(&uid), ver.into()],
        )
        .await?;
        return ctx.die([&b"File ID "[..], &removenow.to_bytes(), b" was removed."].concat());
    }

    let getforremoval = ctx.req.request("getforremoval");
    if !getforremoval.is_empty() {
        let rows = ctx
            .query(
                "SELECT id, title, version, createtime FROM file_database WHERE owner = ? AND deleted = 0 AND ver = ?",
                vec![i(&uid), ver.into()],
            )
            .await?;
        for row in rows {
            let entry = [
                &row.get("id").to_bytes()[..],
                b": ",
                &row.get("title").to_bytes(),
                b"(version ",
                &row.get("version").to_bytes(),
                b") ",
                php::date("d.m.Y", row.get("createtime").to_int()).as_bytes(),
            ]
            .concat();
            ctx.echo(php::dso_b64_encode(&entry));
            ctx.echo(":--:");
        }
        return Ok(());
    }

    let getcategory = ctx.req.request("getcategory");
    if !getcategory.is_empty() {
        let rows = ctx
            .query(
                "SELECT id, title, version, owner, LENGTH(filedata) AS filesize, description, createtime, filename FROM file_database WHERE category = ? AND deleted = 0 AND ver = ?",
                vec![s(&getcategory), ver.into()],
            )
            .await?;
        for row in rows {
            let time = row.get("createtime").to_int();
            let owner = id_to_user(ctx, &row.get("owner")).await?;
            let entry = [
                &row.get("id").to_bytes()[..],
                b":--:",
                &php::dso_b64_encode(&row.get("title").to_bytes()),
                b":--:",
                &php::dso_b64_encode(&row.get("version").to_bytes()),
                b":--:",
                &row.get("filesize").to_bytes(),
                b":--:",
                &owner,
                b":--:",
                &row.get("filename").to_bytes(),
                b":--:",
                &php::dso_b64_encode(&row.get("description").to_bytes()),
                b":--:",
                php::date("d.m.Y", time).as_bytes(),
                b":--:",
                php::date("H:i:s", time).as_bytes(),
                b":--:--:",
            ]
            .concat();
            ctx.echo(entry);
        }
        return Ok(());
    }

    let shortfilename = ctx.req.request("shortfilename");
    if !shortfilename.is_empty() {
        let name = shortfilename.to_bytes();
        if name.iter().any(|c| matches!(c, b'/' | b'\\' | b':')) {
            return ctx.die_error("Invalid filename.", 400);
        }
        // The name a download is saved under, and the client's filesystem
        // folds it, so store the name the file will actually have there.
        let name = php::strtolower(&name);
        let ip = ctx.req.remote_addr.clone();
        let field = |ctx: &Ctx, n| s(&or_empty(ctx.req.request(n)));
        ctx.exec(
            "INSERT INTO file_database (filename, filedata, version, title, description, category, createtime, ip, deleted, owner, ver) VALUES (?,?,?,?,?,?,?,?,0,?,?)",
            vec![
                name.into(),
                field(ctx, "filedata"),
                field(ctx, "version"),
                field(ctx, "title"),
                field(ctx, "description"),
                field(ctx, "category"),
                now().into(),
                ip.into(),
                i(&uid),
                ver.into(),
            ],
        )
        .await?;
        return ctx.die("Upload complete!");
    }

    ctx.die_error("Invalid request.", 400)
}
