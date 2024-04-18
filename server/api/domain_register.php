<?php

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
if ($dInfo !== false) {
	die_error('Domain ' . $d . ' is already registed.', 409);
}

$timestamp = time();

$domain = explode('.', $d);
if (sizeof($domain) == 4 && validIP($d)) {
	// IP register.
	$domain[0] = intval($domain[0]);
	$domain[1] = intval($domain[1]);
	$domain[2] = intval($domain[2]);
	$domain[3] = intval($domain[3]);

	$ipdom = $domain[0] . '.' . $domain[1] . '.' . $domain[2] . '.' . $domain[3];

	// All good, register IP.
	$dprice = 40; // static price for IP registrations.
	if ($dprice > $user['cash']) {
		die_error('Insufficient balance. Try again when you have more money.', 402);
	} else {
		$db->begin_transaction();
		if (transaction($uid, BANK_USER_ID, 'IP Registration: ' . $ipdom, $dprice)) {
			make_new_domain('IP', $ipdom, $uid, '');
			$db->commit();
			die('Registration complete for ' . $ipdom . ', you have been charged $' . $dprice . '.');
		} else {
			$db->rollback();
			die_error('Registration of ' . $ipdom . ' has been DECLINED by the Dark Signs Bank.newlineCheck your bank account for further details.', 402);
		}
	}
} else if (sizeof($domain) === 2) {
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
			$db->begin_transaction();
			if (transaction($uid, BANK_USER_ID, 'Domain Registration: ' . $d, $dprice)) {
				make_new_domain('DOMAIN', $fixedip, $uid, $d);
				$db->commit();
				die('Registration complete for ' . $d . ', you have been charged $' . $dprice);
			} else {
				$db->rollback();
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
	if ($dInfoRoot['owner'] != $user['id']) {
		die_error($dInfoRoot['owner'] . '  ' . $user['id'] . '  You must be the owner of the full domain to register a sub domain.', 403);
	} else if ($dprice > $user['cash']) {
		die_error('Insufficient balance. Try again when you have more money.', 402);
	} else {
		$db->begin_transaction();
		if (transaction($uid, BANK_USER_ID, 'Subdomain Registration: ' . $d, $dprice)) {
			make_new_domain('SUBDOMAIN', $fixedip, $uid, $d, $dInfoRoot['id']);
			$db->commit();
			die('Registration complete for ' . $d . ', you have been charged $' . $dprice);
		} else {
			$db->rollback();
			die_error('Registration of ' . $d . ' has been DECLINED by the Dark Signs Bank.newlineCheck your bank account for further details.', 402);
		}
	}
}

die_error('Invalid domain name.');
