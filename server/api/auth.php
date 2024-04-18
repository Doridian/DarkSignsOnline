<?php

require_once('function.php');

echo '1001';

$d = getDomainInfo($user['username'] . '.usr');
echo $d['ip'];
