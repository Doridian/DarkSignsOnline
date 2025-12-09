<?php

require_once('function.php');

if (empty($_REQUEST['version'])) {
    die('0000OK');
}

$version = strtolower(trim($_REQUEST['version']));
if (empty($version)) {
    die('0000OK');
}

if ($version === 'dev') {
    die('0000OK');
}

$release_track = 'stable';
if (strpos($version, '.') === false) {
    $release_track = 'nightly';
    die('0000OK'); // nightly doesn't auto-update for now
}

$stmt = $db->prepare('SELECT json FROM releases WHERE name = ?');
$stmt->bind_param('s', $release_track);
$stmt->execute();
$result = $stmt->get_result();
$release =  json_decode($result->fetch_assoc()['json']);

$current = strtolower($release->name);

if ($version !== $current) {
    die('0002Client update available! Please download version ' . $release->name . ' at https://darksignsonline.com/download.php');
}

die('0000OK');
