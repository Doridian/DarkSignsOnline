<?php

require_once('function.php');

print_returnwith('2001');

$type = strtoupper(trim($_GET['type']));

switch ($type) {
	case 'DOMAIN':
	case 'IP':
		$stmt = $db->prepare('SELECT host, ip FROM domains WHERE owner = ? AND regtype = ?');
		$stmt->bind_param('is', $user['id'], $type);
		$stmt->execute();
		$result = $stmt->get_result();

		while ($loop = $result->fetch_assoc()) {
			echo 'IP: ' . $loop['ip'] . '; Host: ' . $loop['host'] . "\r\n";
		}
		exit;
	case 'SUBDOMAIN':
		$domain = $_GET['domain'];
		$dInfo = getDomainInfo($domain);
		if ($dInfo === false) {
			die('Domain not found.');
		}
		if ($dInfo['owner'] !== $user['id']) {
			die('Permission denied.');
		}

		$stmt = $db->prepare('SELECT host, ip FROM domains WHERE regtype = "SUBDOMAIN" AND parent = ?');
		$stmt->bind_param('i', $dInfo['id']);
		$stmt->execute();
		$result = $stmt->get_result();

		while ($loop = $result->fetch_assoc()) {
			echo 'IP: ' . $loop['ip'] . '; Host: ' . $loop['host'] . "\r\n";
		}
		exit;
}

die('Invalid type paramater.');
