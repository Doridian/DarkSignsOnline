<?php
global $db;
$db = new mysqli('HOST', 'USERNAME', 'PASSWORD', 'DATABASE');
if (!$db) {
    die('9999');
}

global $github_api_key;
$github_api_key = ''; // Leave blank for none

//error_reporting(E_ALL & ~E_NOTICE);
//ini_set('display_errors', 'On');
