<?php

use PHPMailer\PHPMailer\PHPMailer;
use PHPMailer\PHPMailer\Exception;

require_once('phpmailer/Exception.php');
require_once('phpmailer/PHPMailer.php');
require_once('phpmailer/SMTP.php');

global $mailer;
$mailer = new PHPMailer(true);
$mailer->isSMTP(true);
$mailer->SMTPAuth = true;
$mailer->SMTPSecure = PHPMailer::ENCRYPTION_STARTTLS;
$mailer->Host = $SMTP_HOST;
$mailer->Port = 587;
$mailer->Username = $SMTP_USERNAME;
$mailer->Password = $SMTP_PASSWORD;

function send_email($to_email, $to_name, $subject, $message) {
    global $mailer, $SMTP_FROM;
    $mailer->clearAddresses();
    $mailer->clearAttachments();
    $mailer->SMTPDebug = 2;
    $mailer->Debugoutput = 'html';
    $mailer->setFrom($SMTP_FROM, 'Dark Signs Online');
    $mailer->addAddress($to_email, $to_name);
    $mailer->isHTML(false);
    $mailer->Subject = $subject;
    $mailer->Body = $message;
    $mailer->send();
}
