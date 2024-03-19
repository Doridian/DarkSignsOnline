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
