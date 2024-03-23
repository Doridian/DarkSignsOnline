<?php

$rewrite_done = true;
require_once('function.php');

print_returnwith('2001');

$type = $_GET['type'];
if ($type == 'domain')
{
	$stmt = $db->prepare('SELECT i.id AS id, d.name AS name, d.ext AS ext, COUNT(s.id) AS subdomains FROM iptable AS i LEFT JOIN domain AS d ON d.id = i.id LEFT JOIN subdomain AS s ON s.hostid = i.id WHERE i.owner = ? AND i.regtype="DOMAIN" GROUP BY i.id;');
	$stmt->bind_param('i', $user['id']);
	$stmt->execute();
	$result = $stmt->get_result();
	while ($loop = $result->fetch_assoc())
	{
		echo $loop['name'].'.'.$loop['ext'];
		if ($loop['subdomains'] > 0)
			echo '*';
		echo '$newline';
	}
	exit;
}
else if ($type == 'subdomain')
{
	$domain = $_GET['domain'];
	$dInfo = getDomainInfo($domain);
	if ($dInfo[0] <= 0)
	{
		die('Domain not found.');
	}
	if ($dInfo[1] !== $user['id'])
	{
		die('Permission denied.');
	}

	$stmt = $db->prepare('SELECT name FROM subdomain WHERE hostid=?');
	$stmt->bind_param('i', $dInfo[0]);
	$stmt->execute();
	$result = $stmt->get_result();

	while ($loop = $result->fetch_assoc())
	{
		echo $loop['name'].'.'.$domain.'$newline';
	}
	exit;
}
else if ($type == 'ip')
{
	$stmt = $db->prepare('SELECT ip FROM iptable WHERE owner=? AND regtype="IP"');
	$stmt->bind_param('i', $user['id']);
	$stmt->execute();
	$result = $stmt->get_result();
	while ($loop = $result->fetch_assoc())
	{
		echo $loop['ip'].'$newline';
	}
	exit;
}

die('Invalid type paramater.');
