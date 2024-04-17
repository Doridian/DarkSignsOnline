<?php

$rewrite_done = true;
include_once('function.php');
global $db;

print_returnwith();

$amount = (int)$_REQUEST['amount'];

$to = userToId($_REQUEST['to']);
$description = $_REQUEST['description'];
$db->begin_transaction();
$status = transaction($user['id'], $to, $description, $amount);
$db->commit();
if ($ver > 1) {
	die($status);
}

$usercash = getCash($user['id']);
if ($status === 'COMPLETE') {
	die("Payment of $$amount.00 to $to is complete. Your new balance is $$usercash.00");
}

die_error("Payment of $$amount.00 to $to was DECLINED by the bank with error: $status");
