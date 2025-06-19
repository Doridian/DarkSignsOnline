<?php

$htmltitle = 'E-Mail Verification';
require('_top.php');
require_once('api/function_base.php');

$verify = $_REQUEST['code'];
if (empty($verify)) {
    die_frontend_msg('Error, no verification code provided.');
}

$stmt = $db->prepare('UPDATE users SET active = 1, emailverifycode = "" WHERE emailverifycode = ? AND active = 0');
$stmt->bind_param('s', $verify);
$stmt->execute();

if ($stmt->affected_rows <= 0) {
    die_frontend_msg('Error, invalid verification code.');
}

die_frontend_msg('E-Mail verification completed', 'You can now log in.');
