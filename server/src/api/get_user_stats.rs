//! `get_user_stats.php`: the player's balance.

use super::authenticate;
use crate::ctx::{Ctx, Res};

pub async fn run(ctx: &mut Ctx) -> Res {
    authenticate(ctx).await?;
    ctx.print_returnwith("2000", 1);
    let cash = ctx.user_field("cash").to_bytes();
    ctx.echo(b"STATS: You have $");
    ctx.echo(cash);
    ctx.echo(".00.");
    Ok(())
}
