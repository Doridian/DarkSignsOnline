<?php

if (php_sapi_name() !== 'cli') {
    die('This script can only be run from the command line.');
}

ini_set('display_errors', 1);
error_reporting(E_ALL);

require_once('function_base.php');

function tasklog($msg) {
    echo '[' . date('Y-m-d H:i:s') . '] ' . $msg . PHP_EOL;
}

function taskrun($taskname, $func) {
    $start = microtime(true);
    tasklog('<START> ' . $taskname);
    $func();
    tasklog('< END > ' . $taskname . ' (took ' . round(((microtime(true) - $start) * 1000.0), 3) . ' ms)');
}

taskrun('Remove expired email_codes', function() {
    global $db;
    $time = time();
    $stmt = $db->prepare('DELETE FROM email_codes WHERE expiry < ?');
    $stmt->bind_param('i', $time);
    $stmt->execute();
});
