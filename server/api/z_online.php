<?php

$rewrite_done = true;
require_once('function.php');

$version = $_REQUEST['version'];
if (empty($version)) {
    die('0000OK');
}

$is_nightly = true;
if (strpos($version, '.') !== false) {
    $is_nightly = false;
}

foreach (json_decode(file_get_contents('../releases.json')) as $release) {
    $name = $release->name;

    $is_for_nightly = false;
    if ($name === 'main' || $name === 'latest') {
        $is_for_nightly = true;
        $name = trim(file_get_contents('gitrev.txt'));
    }

    if ($is_nightly !== $is_for_nightly) {
        continue;
    }

    if ($version !== $name) {
        die('0002Client update available! Please download version ' . $name . ' at https://darksignsonline.com/download.php');
    }
}

die('0000OK');
