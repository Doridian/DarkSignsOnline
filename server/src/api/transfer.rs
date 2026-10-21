//! `transfer.php`: pay another player.

use super::{authenticate, get_cash, transaction, user_to_id};
use crate::ctx::{Ctx, Res};

pub async fn run(ctx: &mut Ctx) -> Res {
    authenticate(ctx).await?;
    ctx.print_returnwith("2000", 1);

    let amount = ctx.req.request("amount").to_int();
    let to = user_to_id(ctx, &ctx.req.request("to")).await?;
    let description = ctx.req.request("description");
    let uid = ctx.user_id().to_int();
    ctx.begin().await?;
    let status = transaction(ctx, uid, to, &description, amount).await?;
    ctx.commit().await?;
    if ctx.ver > 1 {
        return ctx.die(status);
    }

    // Version 1 wants a sentence. `$to` is the receiving account's id, not
    // its name, and always was.
    let usercash = get_cash(ctx, uid).await?;
    if status == "COMPLETE" {
        return ctx.die(format!(
            "Payment of ${amount}.00 to {to} is complete. Your new balance is ${usercash}.00"
        ));
    }
    ctx.die_error(
        format!("Payment of ${amount}.00 to {to} was DECLINED by the bank with error: {status}"),
        400,
    )
}
