<?php

if (php_sapi_name() !== 'cli') {
    die('This script can only be run from the command line.');
}

ini_set('display_errors', 1);
error_reporting(E_ALL);

require_once('function_base.php');

echo "_tasks.php: Cleaning up up email_codes.\n";

$time = time();
$stmt = $db->prepare('DELETE FROM email_codes WHERE expiry < ?');
$stmt->bind_param('i', $time);
$stmt->execute();

echo "_tasks.php: Done.\n";
