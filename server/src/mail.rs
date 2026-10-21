//! The two emails the site sends: account verification and password reset.

use lettre::message::Mailbox;
use lettre::transport::smtp::authentication::Credentials;
use lettre::transport::smtp::client::{Tls, TlsParameters};
use lettre::{AsyncSmtpTransport, AsyncTransport, Message, Tokio1Executor};

use crate::App;
use crate::ctx::{Halt, Res};

/// Send one plain-text message. With SMTP credentials configured the
/// connection must be upgraded with STARTTLS before they are sent; without,
/// it is a plain relay, which is how the PHPMailer setup behaved.
pub async fn send(app: &App, to_email: &[u8], to_name: &str, subject: &str, body: &str) -> Res {
    let fail = |e: &dyn std::fmt::Display| Halt::Fatal(format!("mail: {e}"));
    let cfg = &app.smtp;
    let to_email = std::str::from_utf8(to_email).map_err(|e| fail(&e))?;
    let message = Message::builder()
        .from(Mailbox::new(
            Some("Dark Signs Online".into()),
            cfg.from.parse().map_err(|e| fail(&e))?,
        ))
        .to(Mailbox::new(
            Some(to_name.into()),
            to_email.parse().map_err(|e| fail(&e))?,
        ))
        .subject(subject)
        .body(body.to_string())
        .map_err(|e| fail(&e))?;

    let mut transport = AsyncSmtpTransport::<Tokio1Executor>::builder_dangerous(&cfg.host).port(cfg.port);
    if !cfg.username.is_empty() {
        let tls = TlsParameters::new(cfg.host.clone()).map_err(|e| fail(&e))?;
        transport = transport
            .tls(Tls::Required(tls))
            .credentials(Credentials::new(cfg.username.clone(), cfg.password.clone()));
    }
    transport.build().send(message).await.map_err(|e| fail(&e))?;
    Ok(())
}
