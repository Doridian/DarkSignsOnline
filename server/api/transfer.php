<?php

include_once('function.php');
global $db;

print_returnwith();

$amount = (int)$_REQUEST['amount'];
$amount2 = number_format($amount);

$to = userToId($_REQUEST['to']);
$description = $_REQUEST['description'];
$status = transaction($user['id'], $to, $description, $amount);

if ($ver > 1) {
	die($status);
}

$usercash = getCash($user['id']);
if ($status === 'COMPLETE') {
	die("Payment of $$amount2 to $to is complete. Your new balance is $$usercash.00");
}

die_error("Payment of $$amount2 to $to was DECLINED by the bank with error: $status");
