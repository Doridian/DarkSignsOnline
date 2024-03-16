<?php

$rewrite_done = true;
require_once ('function.php');

$price = [];
// List of prices.
$price['com'] = 120;
$price['net'] = 80;
$price['org'] = 80;
$price['edu'] = 299;
$price['mil'] = 1499;
$price['gov'] = 1499;
$price['dsn'] = 12999;

$uid = $user['id'];

// Return code for domain register.
echo '2000';

if (isset ($_REQUEST['prices'])) {
	$outprices = [];
	foreach ($price as $ext => $cost) {
		$outprices[] = $ext . ': $' . $cost;
	}
	die (implode(', ', $outprices) . '');
}

$d = strtolower($_REQUEST['d']);

$temp = getDomainInfo($d);

$timestamp = time();

if ($temp[0] === -1) {
	$domain = explode('.', $d);
	if (sizeof($domain) == 2) {
		// Normal domain register.
		$ext = $domain[1];
		if ($ext == 'com' || $ext == 'net' || $ext == 'org' || $ext == 'edu' || $ext == 'mil' || $ext == 'gov' || $ext == 'dsn') {
			if ($price[$ext] > $user['cash']) {
				die ('Insufficient balance. Try again when you have more money.');
			} else {
				//echo $user['name'];
				if (transaction($uid, BANK_USER_ID, 'Domain Registration: ' . $d, $price[$ext])) {
					// Generate IP
					$randomip;
					$res;
					$stmt = $db->prepare("SELECT * FROM iptable WHERE ip=?");
					do {
						$randomip = rand(1, 255) . "." . rand(1, 255) . "." . rand(1, 255) . "." . rand(1, 255);
						$stmt->bind_param('s', $randomip);
						$stmt->execute();
						$res = $stmt->get_result();
					} while ($res->num_rows != 0);

					$stmt = $db->prepare("INSERT INTO iptable (owner, ip) VALUES (?, ?)");
					$stmt->bind_param('is', $uid, $randomip);
					$stmt->execute();
					$id = $db->insert_id;
					$stmt = $db->prepare("INSERT INTO domain (id, name, ext, time, ip) VALUES (?, ?, ?, ?, ?)");
					$stmt->bind_param('issis', $id, $domain[0], $domain[1], $timestamp, $_SERVER['REMOTE_ADDR']);
					$stmt->execute();
					die ('Registration complete for ' . $d . ', you have been charged $' . $price[$ext] . '');
				} else {
					die ('Registration of ' . $d . ' has been DECLINED by the Dark Signs Bank.newlineCheck your bank account for further details.');
				}

			}
		} else {
			die ('Invalid domain extention.');
		}

	} else if (sizeof($domain) == 3) {
		// Subdomain register.
		$ext = $domain[2];
		$price = 20;
		if ($ext == 'com' || $ext == 'net' || $ext == 'org' || $ext == 'edu' || $ext == 'mil' || $ext == 'gov' || $ext == 'dsn' || ($ext == 'usr' && $user['username'] == $domain[1])) {
			$temp2 = getDomainInfo($domain[1] . '.' . $domain[2]);
			if ($temp2[1] != $user['id']) {
				die ($temp[1] . '  ' . $user['id'] . '  You must be the owner of the full domain to register a sub domain.');
			} else if ($price > $user['cash']) {
				die ('Insufficient balance. Try again when you have more money.');
			} else {
				if (transaction($uid, BANK_USER_ID, 'Domain Registration: ' . $d, $price)) {
					// Generate IP
					$randomip;
					$res;
					$stmt = $db->prepare("SELECT * FROM iptable WHERE ip=?");
					do {
						$randomip = rand(1, 255) . "." . rand(1, 255) . "." . rand(1, 255) . "." . rand(1, 255);
						$stmt->bind_param('s', $randomip);
						$stmt->execute();
						$res = $stmt->get_result();
					} while ($res->num_rows != 0);

					$stmt = $db->prepare("INSERT INTO iptable (owner, ip, regtype) VALUES (?, ?, 'SUBDOMAIN')");
					$stmt->bind_param('is', $uid, $randomip);
					$stmt->execute();
					$id = $db->insert_id;
					$stmt = $db->prepare("INSERT INTO subdomain (id, hostid, name, time, ip) VALUES (?, ?, ?, ?, ?)");
					$stmt->bind_param('issis', $id, $temp2[0], $domain[0], $timestamp, $_SERVER['REMOTE_ADDR']);
					$stmt->execute();

					die ('Registration complete for ' . $d . ', you have been charged $' . $price . '');
				} else {
					die ('Registration of ' . $d . ' has been DECLINED by the Dark Signs Bank.newlineCheck your bank account for further details.');
				}

			}
		} else {
			die ('Invalid domain extention.');
		}
	} else if (sizeof($domain) == 4) {
		// IP register.
		$domain[0] = intval($domain[0]);
		$domain[1] = intval($domain[1]);
		$domain[2] = intval($domain[2]);
		$domain[3] = intval($domain[3]);

		if ($domain[0] >= 0 && $domain[0] < 256 && $domain[1] >= 0 && $domain[1] < 256 && $domain[2] >= 0 && $domain[2] < 256 && $domain[3] >= 0 && $domain[3] < 256) {
			// IP is valid.
			$ipdom = $domain[0] . '.' . $domain[1] . '.' . $domain[2] . '.' . $domain[3];
			$stmt = $db->prepare('SELECT id FROM iptable WHERE ip=?');
			$stmt->bind_param('s', $ipdom);
			$stmt->execute();
			$ip_exists = $stmt->get_result()->num_rows;
			if ($ip_exists == 0) {
				// All good, register IP.
				$price = 40; // static price for IP registrations.
				if ($price > $user['cash']) {
					die ($user['cash'] . '  Insufficient balance. Try again when you have more money.');
				} else {
					if (transaction($uid, BANK_USER_ID, 'Domain Registration: ' . $domain[0] . '.' . $domain[1] . '.' . $domain[2] . '.' . $domain[3], $price)) {
						$stmt = $db->prepare("INSERT INTO iptable (owner, ip, regtype) VALUES (?, ?, 'IP')");
						$stmt->bind_param('is', $uid, $ipdom);
						$stmt->execute();
						die ('Registration complete for ' . $domain[0] . '.' . $domain[1] . '.' . $domain[2] . '.' . $domain[3] . ', you have been charged $' . $price . '.');
					} else {
						die ('Registration of ' . $domain[0] . '.' . $domain[1] . '.' . $domain[2] . '.' . $domain[3] . ' has been DECLINED by the Dark Signs Bank.newlineCheck your bank account for further details.');
					}
				}
			} else {
				// Fail, ip exists.
				die ('The IP address you tried to register already exists: ' . $d . '');
			}
		} else {
			die ('The IP address you tried to register was invalid: ' . $d . '');
		}
	} else {
		die ('The domain name is invalid: ' . $d . '');
	}
} else {
	die ('Domain ' . $d . ' is already registed.');
}
