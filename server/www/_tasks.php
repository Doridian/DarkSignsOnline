<?php

if (php_sapi_name() !== 'cli') {
    die('This script can only be run from the command line.');
}

ini_set('display_errors', 1);
error_reporting(E_ALL);

require_once('api/function_base.php');

function tasklog($msg) {
    echo '[' . date('Y-m-d H:i:s') . '] ' . $msg . PHP_EOL;
}

function taskrun($taskname, $func) {
    tasklog('<START> ' . $taskname);
    $start = microtime(true);
    $func();
    $end = microtime(true);
    tasklog('< END > ' . $taskname . ' (took ' . round((($end - $start) * 1000.0), 3) . ' ms)');
}

taskrun('Remove expired email_codes', function() {
    global $db;
    $time = time();
    $stmt = $db->prepare('DELETE FROM email_codes WHERE expiry < ?');
    $stmt->bind_param('i', $time);
    $stmt->execute();
});

function fetch_release($name, $tag) {
    global $db;
    $time = time();
    $stmt = $db->prepare('SELECT updatetime FROM releases WHERE name = ?');
    $stmt->bind_param('s', $name);
    $stmt->execute();
    $result = $stmt->get_result();
    $row = $result->fetch_assoc();
    $need_update = false;
    if ($row === null) {
        $need_update = true;
    } else {
        $updatetime = (int)$row['updatetime'];
        if ($time - $updatetime > 3600) {
            $need_update = true;
        }
    }

    if (!$need_update) {
        return;
    }

    tasklog('Fetching release info for ' . $name . ' (' . $tag . ')');
    $url = 'https://api.github.com/repos/Doridian/DarkSignsOnline/releases/' . $tag;
    $opts = [
        'http' => [
            'method' => 'GET',
            'header' => [
                'User-Agent: DarkSignsOnline-Server/1.0',
                'Accept: application/vnd.github.v3+json'
            ]
        ]
    ];
    $context = stream_context_create($opts);
    $json = file_get_contents($url, false, $context);
    if ($json === false) {
        tasklog('Failed to fetch release info for ' . $name);
        return;
    }
    $stmt = $db->prepare('REPLACE INTO releases (name, tag, json, updatetime) VALUES (?, ?, ?, ?)');
    $stmt->bind_param('sssi', $name, $tag, $json, $time);
    $stmt->execute();
    tasklog('Updated release info for ' . $name);
}

taskrun('Refresh releases', function() {
    fetch_release('stable', 'latest'); // versioned release
    fetch_release('nightly', 'tags/latest'); // nightly
});
