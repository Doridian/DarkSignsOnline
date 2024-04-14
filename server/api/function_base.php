<?php

$ver = (int)$_SERVER['HTTP_DSO_PROTOCOL_VERSION'];
if ($ver < 1) {
	$ver = 1;
}

function print_returnwith($def = '2000', $max_version = 1) {
	global $ver;
	if ($ver > $max_version && $max_version >= 0) {
		return;
	}

	$returnwith = (string)(int)$_GET['returnwith'];
	if (trim($returnwith) === '0' || empty($returnwith)) {
		$returnwith = $def;
	}
	echo $returnwith;
}

function make_keycode($length = 16) {
	$characters = '0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ';
	$charactersLength = strlen($characters);
	$keycode = '';
	for ($i = 0; $i < $length; $i++) {
		$keycode .= $characters[rand(0, $charactersLength - 1)];
	}
	return $keycode;
}

function die_error($str, $code = 400) {
	global $ver;
	if ($ver > 1) {
		header("HTTP/1.0 $code");
	}
	die($str);
}

define('BANK_USER_ID', 42);

require_once('config.php');

global $db;
$db = new mysqli($DB_HOST, $DB_USERNAME, $DB_PASSWORD, $DB_DATABASE);
if (!$db) {
    die_error('Database error', 500);
}

if (empty($need_db_credentials)) {
	unset($DB_HOST, $DB_USERNAME, $DB_PASSWORD, $DB_DATABASE);
}

if (empty($need_jwt_private_key)) {
	unset($JWT_PRIVATE_KEY);
}
