<?php
global $db;
$db = new mysqli('HOST', 'USERNAME', 'PASSWORD', 'DATABASE');
if (!$db) {
    die('9999');
}

//error_reporting(E_ALL & ~E_NOTICE);
//ini_set('display_errors', 'On');
