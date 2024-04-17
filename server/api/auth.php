<?php

require_once('function.php');

echo '1001';

$stmt = $db->prepare("SELECT ipt.ip FROM iptable ipt, domain d WHERE d.name=? AND d.ext='usr' AND d.id=ipt.id") or die($db->error);
$stmt->bind_param('s', $u);
$stmt->execute();
$res = $stmt->get_result();
$ip = $res->fetch_row()[0];
echo $ip;
