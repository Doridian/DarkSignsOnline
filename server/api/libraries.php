<?php

require_once('function.php');

$getlib = trim($_REQUEST['get']);
if (!empty($getlib)) {
    $stmt = $db->prepare('SELECT data FROM libraries WHERE hash = ?');
    $stmt->bind_param('s', $getlib);
    $stmt->execute();
    $result = $stmt->get_result();
    $lib = $result->fetch_assoc();
    if (!$lib) {
        die_error('not found', 404);
    }
    die($lib['data']);
}

$putlib = trim($_REQUEST['put']);
if (!empty($putlib)) {
    $data = $_REQUEST['data'];
    $myhash = dso_hash($data);
    if ($myhash !== $putlib) {
        die_error('hash mismatch (got ' . $putlib . '; expected ' . $myhash . ')', 409);
    }
    $time = time();
    $stmt = $db->prepare('INSERT INTO libraries (hash, data, owner, time) VALUES (?, ?, ?, ?);');
    $stmt->bind_param('ssii', $putlib, $data, $user['id'], $time);
    $stmt->execute();
    die('OK');
}

die_error('bad request');
