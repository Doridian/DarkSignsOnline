<?php

use PHPMailer\PHPMailer\PHPMailer;

require_once('phpmailer/Exception.php');
require_once('phpmailer/PHPMailer.php');
require_once('phpmailer/SMTP.php');

global $mailer;
$mailer = new PHPMailer(true);
$mailer->isSMTP(true);
$mailer->Host = $SMTP_HOST;
$mailer->Port = (int)$SMTP_PORT;
if (!empty($SMTP_USERNAME)) {
    $mailer->SMTPAuth = true;
    $mailer->SMTPSecure = PHPMailer::ENCRYPTION_STARTTLS;
    $mailer->Username = $SMTP_USERNAME;
    $mailer->Password = $SMTP_PASSWORD;
}

function send_email($to_email, $to_name, $subject, $message) {
    global $mailer, $SMTP_FROM;
    $mailer->clearAddresses();
    $mailer->clearAttachments();
    $mailer->Debugoutput = 'html';
    $mailer->setFrom($SMTP_FROM, 'Dark Signs Online');
    $mailer->addAddress($to_email, $to_name);
    $mailer->isHTML(false);
    $mailer->Subject = $subject;
    $mailer->Body = $message;
    $mailer->send();
}
