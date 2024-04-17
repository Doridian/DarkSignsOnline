<?php

$rewrite_done = true;
require_once("function.php");

$price = [];
// List of prices.
$price['com'] = 120;
$price['net'] = 80;
$price['org'] = 80;
$price['edu'] = 299;
$price['mil'] = 1499;
$price['gov'] = 1499;
$price['dsn'] = 12999;
$price['ru'] = 40;

$uid = $user['id'];

$fixedip = $_REQUEST['fixedip'];
if (!empty($fixedip) && !validIP($fixedip)) {
	die_error('Invalid fixed IP.');
}

print_returnwith();

if (isset ($_REQUEST['prices'])) {
	$outprices = [];
	foreach ($price as $ext => $cost) {
		$outprices[] = $ext . ': $' . $cost;
	}
	die (implode(', ', $outprices) . '');
}

$d = strtolower($_REQUEST['d']);

$dInfo = getDomainInfo($d);

$timestamp = time();

if ($dInfo[0] > 0) {
	die_error('Domain ' . $d . ' is already registed.', 409);
}

$domain = explode('.', $d);
if (sizeof($domain) == 4 && validIP($d)) {
	// IP register.
	$domain[0] = intval($domain[0]);
	$domain[1] = intval($domain[1]);
	$domain[2] = intval($domain[2]);
	$domain[3] = intval($domain[3]);

	// All good, register IP.
	$dprice = 40; // static price for IP registrations.
	if ($dprice > $user['cash']) {
		die_error('Insufficient balance. Try again when you have more money.', 402);
	} else {
		if (transaction($uid, BANK_USER_ID, 'Domain Registration: ' . $domain[0] . '.' . $domain[1] . '.' . $domain[2] . '.' . $domain[3], $dprice)) {
			$keycode = make_keycode();
			$timestamp = time();
			$stmt = $db->prepare("INSERT INTO iptable (owner, ip, regtype, time, keycode) VALUES (?, ?, 'IP', ?, ?)");
			$stmt->bind_param('isis', $uid, $ipdom, $timestamp, $keycode);
			$stmt->execute();
			die('Registration complete for ' . $domain[0] . '.' . $domain[1] . '.' . $domain[2] . '.' . $domain[3] . ', you have been charged $' . $dprice . '.');
		} else {
			die_error('Registration of ' . $domain[0] . '.' . $domain[1] . '.' . $domain[2] . '.' . $domain[3] . ' has been DECLINED by the Dark Signs Bank.newlineCheck your bank account for further details.', 402);
		}
	}
} else if (sizeof($domain) == 2) {
	// Normal domain register.
	$ext = $domain[1];
	if (!empty($price[$ext])) {
		$dprice = $price[$ext];
		if (!empty($fixedip)) {
			$dprice += 40;
		}
		if ($dprice > $user['cash']) {
			die_error('Insufficient balance. Try again when you have more money.', 402);
		} else {
			if (transaction($uid, BANK_USER_ID, 'Domain Registration: ' . $d, $dprice)) {
				// Generate IP
				$randomip;
				if (!empty($fixedip)) {
					$randomip = $fixedip;
				} else {
					$res;
					$stmt = $db->prepare("SELECT * FROM iptable WHERE ip=?");
					do {
						$randomip = rand(1, 254) . "." . rand(0, 255) . "." . rand(0, 255) . "." . rand(0, 255);
						$stmt->bind_param('s', $randomip);
						$stmt->execute();
						$res = $stmt->get_result();
					} while ($res->num_rows != 0);
				}

				$keycode = make_keycode();
				$stmt = $db->prepare("INSERT INTO iptable (owner, ip, regtype, time, keycode) VALUES (?, ?, 'DOMAIN', ?, ?)");
				$stmt->bind_param('isis', $uid, $randomip, $timestamp, $keycode);
				$stmt->execute();
				$id = $db->insert_id;
				$stmt = $db->prepare("INSERT INTO domain (id, name, ext) VALUES (?, ?, ?)");
				$stmt->bind_param('iss', $id, $domain[0], $domain[1]);
				$stmt->execute();
				die('Registration complete for ' . $d . ', you have been charged $' . $dprice);
			} else {
				die_error('Registration of ' . $d . ' has been DECLINED by the Dark Signs Bank.newlineCheck your bank account for further details.', 402);
			}
		}
	} else {
		die_error('Invalid domain extension.');
	}
} else if (sizeof($domain) > 2) {
	// Subdomain register.
	$ext = array_pop($domain);
	$name = array_pop($domain);
	$host = implode('.', $domain);
	$dInfoRoot = getDomainInfo($name . '.' . $ext);
	$dprice = 20;
	if (!empty($fixedip)) {
		$dprice += 40;
	}
	if ($dInfoRoot[1] != $user['id']) {
		die_error($dInfoRoot[1] . '  ' . $user['id'] . '  You must be the owner of the full domain to register a sub domain.', 403);
	} else if ($dprice > $user['cash']) {
		die_error('Insufficient balance. Try again when you have more money.', 402);
	} else {
		if (transaction($uid, BANK_USER_ID, 'Domain Registration: ' . $d, $dprice)) {
			// Generate IP
			$randomip;
			if (!empty($fixedip)) {
				$randomip = $fixedip;
			} else {
				$res;
				$stmt = $db->prepare("SELECT * FROM iptable WHERE ip=?");
				do {
					$randomip = rand(1, 254) . "." . rand(0, 255) . "." . rand(0, 255) . "." . rand(0, 255);
					$stmt->bind_param('s', $randomip);
					$stmt->execute();
					$res = $stmt->get_result();
				} while ($res->num_rows != 0);
			}

			$keycode = make_keycode();
			$stmt = $db->prepare("INSERT INTO iptable (owner, ip, regtype, time, keycode) VALUES (?, ?, 'SUBDOMAIN', ?, ?)");
			$stmt->bind_param('isis', $uid, $randomip, $timestamp, $keycode);
			$stmt->execute();
			$id = $db->insert_id;
			$stmt = $db->prepare("INSERT INTO subdomain (id, hostid, name) VALUES (?, ?, ?)");
			$stmt->bind_param('iss', $id, $dInfoRoot[0], $host);
			$stmt->execute();

			die('Registration complete for ' . $d . ', you have been charged $' . $dprice);
		} else {
			die_error('Registration of ' . $d . ' has been DECLINED by the Dark Signs Bank.newlineCheck your bank account for further details.', 402);
		}
	}
}

die_error('Invalid domain name.');
