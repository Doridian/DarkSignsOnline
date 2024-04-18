<?php

require_once('function.php');

echo '1001';

$d = getDomainInfo($user['username'] . '.usr');
if ($d === false) {
    $id = make_new_domain('DOMAIN', '', $user['id'], $user['username'] . '.usr');
    $d = getDomainById($id);
}
echo $d['ip'];
