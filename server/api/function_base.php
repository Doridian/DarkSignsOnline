<?php

function make_keycode($length = 16)
{
	$characters = '0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ';
	$charactersLength = strlen($characters);
	$keycode = '';
	for ($i = 0; $i < $length; $i++) {
		$keycode .= $characters[rand(0, $charactersLength - 1)];
	}
	return $keycode;
}

define('BANK_USER_ID', 42);

require_once('config.php');

global $db;
$db = new mysqli($DB_HOST, $DB_USERNAME, $DB_PASSWORD, $DB_DATABASE);
if (!$db) {
    die('9999');
}

if (empty($need_db_credentials)) {
	unset($DB_HOST, $DB_USERNAME, $DB_PASSWORD, $DB_DATABASE);
}

if (empty($need_jwt_private_key)) {
	unset($JWT_PRIVATE_KEY);
}
