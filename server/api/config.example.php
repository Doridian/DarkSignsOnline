<?php
global $db;
$db = new mysqli('HOST', 'USERNAME', 'PASSWORD', 'DATABASE');
if (!$db) {
    die('9999');
}

$JWT_PUBLIC_KEY = '-----BEGIN PUBLIC KEY-----
PUT YOUR PUBLIC KEY HERE
-----END PUBLIC KEY-----';
$JWT_PRIVATE_KEY = '-----BEGIN PRIVATE KEY-----
PUT YOUR PRIVATE KEY HERE
-----END PRIVATE KEY-----';

//error_reporting(E_ALL & ~E_NOTICE);
//ini_set('display_errors', 'On');
